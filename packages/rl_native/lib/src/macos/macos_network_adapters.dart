import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:rl_core/rl_core.dart';

import '../network_adapter_backend.dart';

// ── BSD structs ──────────────────────────────────────────────────────────────

/// `struct ifaddrs` from `<ifaddrs.h>`.
///
/// Only the first four members are declared. The layout of the rest does not
/// matter because nothing here walks past `ifaAddr`, and the FFI layout rules
/// insert the same padding the C compiler does — so the offsets of the members
/// that *are* declared are correct regardless.
final class IfAddrs extends Struct {
  external Pointer<IfAddrs> ifaNext;
  external Pointer<Utf8> ifaName;

  @Uint32()
  external int ifaFlags;

  external Pointer<Uint8> ifaAddr;
}

typedef _GetIfAddrsNative = Int32 Function(Pointer<Pointer<IfAddrs>>);
typedef _GetIfAddrsDart = int Function(Pointer<Pointer<IfAddrs>>);

typedef _FreeIfAddrsNative = Void Function(Pointer<IfAddrs>);
typedef _FreeIfAddrsDart = void Function(Pointer<IfAddrs>);

/// macOS interface enumeration via `getifaddrs`.
///
/// The sockaddr structures are read byte-wise rather than declared as FFI
/// structs. `sockaddr_dl` is variable-length — the interface name and the
/// hardware address share one trailing buffer — so a fixed-size `@Array`
/// declaration would either truncate a long name or read past the allocation.
/// Reading the three length bytes and then slicing is both shorter and
/// correct for every interface.
final class MacosNetworkAdapterBackend implements NetworkAdapterBackend {
  MacosNetworkAdapterBackend()
      : _libSystem = DynamicLibrary.open('/usr/lib/libSystem.B.dylib') {
    _getIfAddrs = _libSystem.lookupFunction<_GetIfAddrsNative, _GetIfAddrsDart>(
      'getifaddrs',
    );
    _freeIfAddrs =
        _libSystem.lookupFunction<_FreeIfAddrsNative, _FreeIfAddrsDart>(
      'freeifaddrs',
    );
  }

  final DynamicLibrary _libSystem;
  late final _GetIfAddrsDart _getIfAddrs;
  late final _FreeIfAddrsDart _freeIfAddrs;

  final Log _log = Log.scoped('native.network');

  /// `AF_INET` and `AF_LINK` as BSD numbers them. `AF_LINK` is the datalink
  /// entry, which is where a hardware address lives on macOS — there is no
  /// `AF_PACKET` as there is on Linux.
  static const int _afInet = 2;
  static const int _afLink = 18;

  @override
  bool get isAvailable => true;

  @override
  Future<List<NetworkAdapter>> adapters() async {
    final head = calloc<Pointer<IfAddrs>>();
    try {
      if (_getIfAddrs(head) != 0) {
        _log.warn('getifaddrs failed; no hardware addresses are available');
        return const <NetworkAdapter>[];
      }

      // One interface produces several entries — one per address family — so
      // they are folded back together by name before being handed out.
      final macs = <String, MacAddress>{};
      final addresses = <String, List<String>>{};
      final order = <String>[];

      for (var entry = head.value;
          entry != nullptr;
          entry = entry.ref.ifaNext) {
        final name = entry.ref.ifaName == nullptr
            ? ''
            : entry.ref.ifaName.toDartString();
        if (name.isEmpty) continue;
        if (!order.contains(name)) order.add(name);

        final sockaddr = entry.ref.ifaAddr;
        if (sockaddr == nullptr) continue;

        switch (sockaddr[1]) {
          case _afLink:
            final mac = _readLinkAddress(sockaddr);
            if (mac != null) macs[name] = mac;
          case _afInet:
            // sockaddr_in: sin_len, sin_family, sin_port (2), then the address.
            (addresses[name] ??= <String>[]).add(
              '${sockaddr[4]}.${sockaddr[5]}.${sockaddr[6]}.${sockaddr[7]}',
            );
        }
      }

      if (head.value != nullptr) _freeIfAddrs(head.value);

      return <NetworkAdapter>[
        for (final name in order)
          NetworkAdapter(
            name: name,
            ipv4Addresses: addresses[name] ?? const <String>[],
            macAddress: macs[name],
          ),
      ];
    } finally {
      calloc.free(head);
    }
  }

  /// Extracts the hardware address from a `sockaddr_dl`.
  ///
  /// ```text
  /// 0  sdl_len   1  sdl_family  2  sdl_index (2 bytes)
  /// 4  sdl_type  5  sdl_nlen    6  sdl_alen   7  sdl_slen
  /// 8  sdl_data[] — interface name, then the address, then the selector
  /// ```
  MacAddress? _readLinkAddress(Pointer<Uint8> sockaddr) {
    final nameLength = sockaddr[5];
    final addressLength = sockaddr[6];
    // Loopback and tunnels report a zero-length address. That is not a fault:
    // they genuinely have no hardware address, and there is nothing to wake.
    if (addressLength != MacAddress.length) return null;

    final start = 8 + nameLength;
    return MacAddress(<int>[
      for (var i = 0; i < addressLength; i++) sockaddr[start + i],
    ]);
  }

  @override
  void dispose() {}
}
