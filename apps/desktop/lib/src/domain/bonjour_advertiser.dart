import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_transport/rl_transport.dart';

/// DNS-SD service type. Must match the client's browse type exactly.
const String kBonjourServiceType = '_remotelink._tcp';

/// Publishes this computer over Bonjour / DNS-SD.
///
/// Runs alongside the UDP beacon rather than replacing it. The UDP path needs
/// no native plugin and works on networks where Bonjour is filtered; Bonjour is
/// the only route an iPhone can use without the multicast entitlement Apple
/// grants by application. Advertising on both costs one extra socket and makes
/// the phone's discovery work in both worlds.
///
/// The TXT record carries the same fields as the UDP beacon, so a client can
/// build an identical [Beacon] from either source and everything downstream is
/// unaware of which route found the computer.
final class BonjourAdvertiser {
  BonjourAdvertiser({required Beacon Function() describe}) : _describe = describe;

  /// Read fresh on every (re)publish, so a capability change — Accessibility
  /// being granted, say — reaches new browsers rather than being frozen at
  /// startup.
  final Beacon Function() _describe;

  final Log _log = Log.scoped('desktop.bonjour');

  BonsoirBroadcast? _broadcast;
  bool _failed = false;

  /// Whether the advertisement is live.
  bool get isAdvertising => _broadcast != null;

  Future<void> start() async {
    if (_broadcast != null || _failed) return;

    try {
      final beacon = _describe();
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          // The service name is what a generic Bonjour browser shows, so it is
          // the human name rather than the device id.
          name: beacon.name,
          type: kBonjourServiceType,
          port: beacon.servicePort,
          attributes: <String, String>{
            'id': beacon.deviceId.value,
            'fp': base64Url
                .encode(beacon.publicKeyFingerprint)
                .replaceAll('=', ''),
            'cap': beacon.capabilities.bits.toString(),
            'plat': beacon.platform.wireValue.toString(),
            'pv': beacon.protocolVersion.toString(),
            'pair': beacon.acceptsNewPairings ? '1' : '0',
          },
        ),
      );

      await broadcast.ready;
      await broadcast.start();
      _broadcast = broadcast;

      _log.info(
        'advertising over Bonjour',
        fields: <String, Object?>{
          'type': kBonjourServiceType,
          'port': beacon.servicePort,
        },
      );
    } on Object catch (e) {
      // Never fatal. Losing Bonjour costs iPhones their automatic discovery;
      // taking the whole service down over it would cost everyone everything.
      _failed = true;
      _log.warn(
        'Bonjour advertising unavailable; the UDP beacon still runs',
        error: e,
      );
    }
  }

  /// Republishes with the current description.
  ///
  /// DNS-SD has no cheap "update my TXT record" in this plugin, so a change is
  /// a stop and a start. Called rarely — only when capabilities actually change
  /// — because browsers see the service disappear and reappear.
  Future<void> refresh() async {
    if (_broadcast == null) return;
    await stop();
    await start();
  }

  Future<void> stop() async {
    final broadcast = _broadcast;
    _broadcast = null;
    if (broadcast == null) return;
    try {
      await broadcast.stop();
    } on Object catch (e) {
      _log.debug(() => 'Bonjour stop failed: $e');
    }
  }
}
