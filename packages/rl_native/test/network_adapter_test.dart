import 'dart:io';

import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';
import 'package:test/test.dart';

void main() {
  final wifi = NetworkAdapter(
    name: 'en0',
    ipv4Addresses: const <String>['192.168.1.42'],
    macAddress: MacAddress.tryParse('00:1A:2B:3C:4D:5E'),
  );
  final docker = NetworkAdapter(
    name: 'bridge100',
    ipv4Addresses: const <String>['172.17.0.1'],
    macAddress: MacAddress.tryParse('02:42:AC:11:00:01'),
  );
  const loopback = NetworkAdapter(
    name: 'lo0',
    ipv4Addresses: <String>['127.0.0.1'],
  );

  group('adapterCarrying', () {
    test('picks the adapter holding the address, not the first one', () {
      // The failure this guards against is silent: a machine has several
      // hardware addresses, all six bytes and all well-formed, and only the one
      // on the reachable network wakes anything.
      expect(
        adapterCarrying(
                <NetworkAdapter>[docker, loopback, wifi], '192.168.1.42')
            ?.name,
        'en0',
      );
      expect(
        adapterCarrying(<NetworkAdapter>[docker, wifi], '172.17.0.1')?.name,
        'bridge100',
      );
    });

    test('skips adapters that have no hardware address', () {
      // Loopback matches by address but has nothing to advertise, and returning
      // it would mask a real adapter further down the list.
      expect(
        adapterCarrying(<NetworkAdapter>[loopback, wifi], '127.0.0.1'),
        isNull,
      );
    });

    test('returns null when nothing matches or there is no address', () {
      expect(adapterCarrying(<NetworkAdapter>[wifi], '10.0.0.1'), isNull);
      expect(adapterCarrying(<NetworkAdapter>[wifi], null), isNull);
      expect(adapterCarrying(const <NetworkAdapter>[], '192.168.1.42'), isNull);
    });
  });

  group('UnsupportedNetworkAdapterBackend', () {
    test('reports nothing instead of throwing', () async {
      const backend = UnsupportedNetworkAdapterBackend('no implementation');
      expect(backend.isAvailable, isFalse);
      expect(await backend.adapters(), isEmpty);
      backend.dispose();
    });
  });

  group('NativeBackends.createNetworkAdapters', () {
    test('enumerates real interfaces on a supported platform', () async {
      final backend = NativeBackends.createNetworkAdapters();
      addTearDown(backend.dispose);

      if (!Platform.isMacOS && !Platform.isWindows) {
        expect(backend.isAvailable, isFalse);
        return;
      }

      expect(backend.isAvailable, isTrue);
      final adapters = await backend.adapters();
      expect(
        adapters,
        isNotEmpty,
        reason: 'every host has at least a loopback interface',
      );

      // Cross-checked against dart:io rather than against a hard-coded name:
      // interface naming differs per host, but any adapter this backend reports
      // an IPv4 address for must be one `NetworkInterface` also sees.
      final known = <String>{
        for (final interface in await NetworkInterface.list(
          includeLoopback: true,
          type: InternetAddressType.IPv4,
        ))
          for (final address in interface.addresses) address.address,
      };
      for (final adapter in adapters) {
        for (final address in adapter.ipv4Addresses) {
          expect(known, contains(address));
        }
        // A reported address is either absent or genuinely six bytes; a
        // truncated read would show up here.
        expect(adapter.macAddress?.bytes.length ?? 6, 6);
      }

      // At least one adapter with an IPv4 address should have a MAC — a host
      // with networking has hardware behind it. Loopback is excluded because it
      // legitimately has neither.
      final routable = adapters.where(
        (adapter) =>
            adapter.ipv4Addresses.any((address) => address != '127.0.0.1'),
      );
      if (routable.isNotEmpty) {
        expect(
          routable.any((adapter) => adapter.macAddress != null),
          isTrue,
          reason: 'a host with a routable address has a hardware address too',
        );
      }
    });
  });
}
