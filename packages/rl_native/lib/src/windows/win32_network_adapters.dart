// ignore_for_file: camel_case_types, constant_identifier_names

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';

import '../network_adapter_backend.dart';

// ── Win32 structs ────────────────────────────────────────────────────────────

/// `IP_ADDR_STRING` from `<iptypes.h>`. A linked list of dotted-quad strings.
final class IP_ADDR_STRING extends Struct {
  external Pointer<IP_ADDR_STRING> next;

  @Array(16)
  external Array<Uint8> ipAddress;

  @Array(16)
  external Array<Uint8> ipMask;

  @Uint32()
  external int context;
}

/// `IP_ADAPTER_INFO` from `<iptypes.h>`, declared as far as the address list.
///
/// The members after `ipAddressList` — gateway, DHCP server, WINS, lease times
/// — are not read, and leaving them off cannot shift the offsets of the ones
/// above, which is what makes a partial declaration safe here. The array
/// lengths are the documented `MAX_ADAPTER_*` constants and must not be
/// "tidied": they are what the kernel writes into, so a shorter one would put
/// every field after it at the wrong offset.
final class IP_ADAPTER_INFO extends Struct {
  external Pointer<IP_ADAPTER_INFO> next;

  @Uint32()
  external int comboIndex;

  /// `MAX_ADAPTER_NAME_LENGTH + 4`.
  @Array(260)
  external Array<Uint8> adapterName;

  /// `MAX_ADAPTER_DESCRIPTION_LENGTH + 4`.
  @Array(132)
  external Array<Uint8> description;

  @Uint32()
  external int addressLength;

  /// `MAX_ADAPTER_ADDRESS_LENGTH`.
  @Array(8)
  external Array<Uint8> address;

  @Uint32()
  external int index;

  @Uint32()
  external int type;

  @Uint32()
  external int dhcpEnabled;

  external Pointer<IP_ADDR_STRING> currentIpAddress;

  external IP_ADDR_STRING ipAddressList;
}

typedef _GetAdaptersInfoNative = Uint32 Function(
  Pointer<IP_ADAPTER_INFO> adapterInfo,
  Pointer<Uint32> sizePointer,
);
typedef _GetAdaptersInfoDart = int Function(
  Pointer<IP_ADAPTER_INFO> adapterInfo,
  Pointer<Uint32> sizePointer,
);

/// Windows interface enumeration via `GetAdaptersInfo` in `iphlpapi.dll`.
///
/// `GetAdaptersInfo` rather than the newer `GetAdaptersAddresses` because this
/// feature is IPv4-only by nature — a magic packet is broadcast to an IPv4
/// subnet — and the older call hands back exactly that, with the addresses
/// already formatted as dotted quads and no unicast-address list to walk.
final class Win32NetworkAdapterBackend implements NetworkAdapterBackend {
  Win32NetworkAdapterBackend()
      : _iphlpapi = DynamicLibrary.open('iphlpapi.dll') {
    _getAdaptersInfo =
        _iphlpapi.lookupFunction<_GetAdaptersInfoNative, _GetAdaptersInfoDart>(
      'GetAdaptersInfo',
    );
  }

  final DynamicLibrary _iphlpapi;
  late final _GetAdaptersInfoDart _getAdaptersInfo;

  final Log _log = Log.scoped('native.network');

  static const int ERROR_SUCCESS = 0;
  static const int ERROR_BUFFER_OVERFLOW = 111;

  @override
  bool get isAvailable => true;

  @override
  Future<List<NetworkAdapter>> adapters() async {
    final sizePointer = calloc<Uint32>();
    Pointer<IP_ADAPTER_INFO> buffer = nullptr;
    try {
      // Asked for the size first rather than guessing at a buffer: the list
      // grows with every VPN, virtual switch, and docking station, and a fixed
      // buffer would silently truncate on exactly the machines that have the
      // most adapters.
      sizePointer.value = 0;
      final probe = _getAdaptersInfo(nullptr, sizePointer);
      if (probe != ERROR_BUFFER_OVERFLOW && probe != ERROR_SUCCESS) {
        _log.warn(
          'GetAdaptersInfo could not report a buffer size',
          fields: <String, Object?>{'error': probe},
        );
        return const <NetworkAdapter>[];
      }
      if (sizePointer.value == 0) return const <NetworkAdapter>[];

      buffer = calloc<Uint8>(sizePointer.value).cast<IP_ADAPTER_INFO>();
      final status = _getAdaptersInfo(buffer, sizePointer);
      if (status != ERROR_SUCCESS) {
        _log.warn(
          'GetAdaptersInfo failed',
          fields: <String, Object?>{'error': status},
        );
        return const <NetworkAdapter>[];
      }

      final adapters = <NetworkAdapter>[];
      for (var entry = buffer; entry != nullptr; entry = entry.ref.next) {
        adapters.add(
          NetworkAdapter(
            name: _readCString(entry.ref.adapterName, 260),
            ipv4Addresses: _readAddresses(entry.ref),
            macAddress: _readMac(entry.ref),
          ),
        );
      }
      return adapters;
    } finally {
      if (buffer != nullptr) calloc.free(buffer);
      calloc.free(sizePointer);
    }
  }

  MacAddress? _readMac(IP_ADAPTER_INFO info) {
    // Tunnels and loopback report a shorter address — or none — and there is
    // nothing to wake behind them.
    if (info.addressLength != MacAddress.length) return null;
    return MacAddress(<int>[
      for (var i = 0; i < MacAddress.length; i++) info.address[i],
    ]);
  }

  List<String> _readAddresses(IP_ADAPTER_INFO info) {
    final addresses = <String>[];

    // An adapter that is present but unplugged lists 0.0.0.0. Keeping it would
    // let it match nothing while looking like a real address.
    void add(String text) {
      if (text.isEmpty || text == '0.0.0.0') return;
      addresses.add(text);
    }

    // The first address is stored inline in the adapter record; any further
    // ones hang off it as a linked list.
    add(_readCString(info.ipAddressList.ipAddress, 16));
    for (var node = info.ipAddressList.next;
        node != nullptr;
        node = node.ref.next) {
      add(_readCString(node.ref.ipAddress, 16));
    }
    return addresses;
  }

  /// Reads a fixed-width, NUL-terminated ASCII field.
  String _readCString(Array<Uint8> source, int capacity) {
    final units = <int>[];
    for (var i = 0; i < capacity; i++) {
      final unit = source[i];
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  @override
  void dispose() {}
}
