import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';

/// One network interface as the host OS describes it.
@immutable
final class NetworkAdapter {
  const NetworkAdapter({
    required this.name,
    required this.ipv4Addresses,
    this.macAddress,
  });

  /// OS-level interface name — `en0`, `Ethernet`, `{GUID}`.
  final String name;

  /// IPv4 addresses currently assigned, as dotted quads.
  ///
  /// Carried alongside the hardware address because on its own a MAC is not
  /// actionable: a laptop has one for Wi-Fi, one for Ethernet, one per virtual
  /// adapter, and the only way to tell which one a phone can reach is to match
  /// it against the address the service is answering on.
  final List<String> ipv4Addresses;

  /// Hardware address, or null for interfaces that have none (loopback, and
  /// most tunnels).
  final MacAddress? macAddress;
}

/// Enumerates this host's network interfaces, including their MAC addresses.
///
/// `NetworkInterface` in `dart:io` gets as far as the addresses and then stops
/// — it has no notion of a hardware address at all — so this is the one part of
/// the feature that has to go through the platform, which is why it lives
/// behind an interface in this package rather than in `apps/`.
abstract interface class NetworkAdapterBackend {
  bool get isAvailable;

  /// Reads the current interface list. Not cached: adapters come and go as
  /// cables and VPNs do.
  Future<List<NetworkAdapter>> adapters();

  void dispose();
}

/// Fallback for platforms with no implementation yet.
///
/// Returning nothing rather than throwing is deliberate: a missing MAC means
/// the phone shows no Wake button, which is the honest outcome, whereas an
/// exception would take down whatever was enumerating addresses at the time.
final class UnsupportedNetworkAdapterBackend implements NetworkAdapterBackend {
  const UnsupportedNetworkAdapterBackend([this.unavailableReason]);

  final String? unavailableReason;

  @override
  bool get isAvailable => false;

  @override
  Future<List<NetworkAdapter>> adapters() async => const <NetworkAdapter>[];

  @override
  void dispose() {}
}

/// The adapter carrying [address], or null when nothing matches.
///
/// Pulled out as a free function so the selection rule — the part that is easy
/// to get wrong and impossible to observe from the outside — can be tested
/// without a host to enumerate. Picking the wrong adapter is not a visible
/// failure: the phone stores a perfectly well-formed MAC that belongs to a
/// Docker bridge and wakes nothing, forever.
NetworkAdapter? adapterCarrying(
  List<NetworkAdapter> adapters,
  String? address,
) {
  if (address == null) return null;
  for (final adapter in adapters) {
    if (adapter.macAddress == null) continue;
    if (adapter.ipv4Addresses.contains(address)) return adapter;
  }
  return null;
}
