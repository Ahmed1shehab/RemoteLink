import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';

/// What happened when a magic packet was sent.
///
/// "Sent" is as much as anything can honestly report. Wake-on-LAN has no
/// acknowledgement — the target is switched off, and its adapter answers
/// nothing — so success here means the datagrams left this device, not that a
/// computer woke up. The UI copy is written to match.
final class WakeAttempt {
  const WakeAttempt({required this.deliveredTo, required this.failures});

  /// Broadcast addresses the packet actually reached the network stack for.
  final List<String> deliveredTo;

  /// Addresses the OS refused, with the reason, for the log.
  final Map<String, String> failures;

  bool get anyDelivered => deliveredTo.isNotEmpty;
}

/// Sends Wake-on-LAN magic packets.
///
/// An interface rather than a bare function so a widget test can assert what
/// the Wake button sends without opening a socket — binding a real UDP socket
/// in a test is exactly the "passes alone, fails beside anything else" failure
/// `CONTRIBUTING.md` warns about.
abstract interface class WakeOnLanSender {
  Future<WakeAttempt> wake(MacAddress mac, {String? lastKnownAddress});
}

/// Broadcasts the packet over UDP.
final class UdpWakeOnLanSender implements WakeOnLanSender {
  const UdpWakeOnLanSender();

  @override
  Future<WakeAttempt> wake(MacAddress mac, {String? lastKnownAddress}) async {
    final log = Log.scoped('mobile.wake');
    final packet = buildMagicPacket(mac);
    final delivered = <String>[];
    final failures = <String, String>{};

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final targets = wakeTargetsFor(
        lastKnownAddress: lastKnownAddress,
        localAddresses: await _localAddresses(),
      );

      for (final target in targets) {
        // Each target is tried independently. A phone whose network refuses
        // the limited broadcast may still deliver a directed one, and sharing
        // one try block would throw the second attempt away with the first —
        // the same reasoning the discovery layer applies to multicast and
        // broadcast.
        try {
          socket.send(packet, InternetAddress(target), kWakeOnLanPort);
          delivered.add(target);
        } on SocketException catch (e) {
          failures[target] = e.message;
        }
      }

      log.info(
        'sent wake-on-lan magic packet',
        fields: <String, Object?>{
          'mac': mac.canonical,
          'delivered': delivered.length,
          'refused': failures.length,
        },
      );
    } on SocketException catch (e) {
      failures['*'] = e.message;
      log.warn('could not open a socket to send a magic packet', error: e);
    } finally {
      socket?.close();
    }

    return WakeAttempt(deliveredTo: delivered, failures: failures);
  }

  /// This phone's own IPv4 addresses, used to derive the directed broadcast of
  /// the network it is actually on.
  Future<List<String>> _localAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      return <String>[
        for (final interface in interfaces)
          for (final address in interface.addresses) address.address,
      ];
    } on SocketException {
      return const <String>[];
    }
  }
}

/// The sender used by the device list. Overridden in tests.
final wakeOnLanSenderProvider = Provider<WakeOnLanSender>(
  (ref) => const UdpWakeOnLanSender(),
);
