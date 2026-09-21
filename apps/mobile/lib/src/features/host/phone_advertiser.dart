import 'dart:convert';

import 'package:bonsoir/bonsoir.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_transport/rl_transport.dart';

import '../devices/bonjour_discovery.dart';

/// Something that makes this phone findable.
///
/// An interface for one reason, and it is not extensibility: publishing a
/// Bonjour record needs a platform plugin, so the real one cannot run in a
/// widget test at all. Without a seam here, every test of the listening half
/// would either register a fake method channel or watch the advertiser fail on
/// its own — the second of which passes for the wrong reason.
abstract interface class NetworkAdvertiser {
  /// Whether the advertisement is live.
  bool get isAdvertising;

  Future<void> start();

  /// Republishes with the current description.
  Future<void> refresh();

  Future<void> stop();
}

/// An advertiser for a platform that has none, or for a test.
final class InertAdvertiser implements NetworkAdvertiser {
  const InertAdvertiser();

  @override
  bool get isAdvertising => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> stop() async {}
}

/// Publishes this phone over Bonjour / DNS-SD.
///
/// A near-copy of the desktop's advertiser, and deliberately a copy rather than
/// a shared class: `bonsoir` is a Flutter plugin, and CONTRIBUTING §1 keeps
/// Flutter out of `packages/`, so there is nowhere beneath `apps/` for one
/// version of this to live. `motion.dart` is duplicated for exactly the same
/// reason.
///
/// Bonjour is the whole discovery story on iOS. The UDP beacon needs the
/// multicast entitlement Apple grants by written application, and a phone that
/// cannot be found is a phone that cannot be sent to — so where the desktop
/// treats Bonjour as the second of two routes, here it is the first and on one
/// platform the only one.
final class PhoneAdvertiser implements NetworkAdvertiser {
  PhoneAdvertiser({required Beacon Function() describe}) : _describe = describe;

  /// Read fresh on every (re)publish, so a rename reaches new browsers rather
  /// than being frozen at whatever the phone was called when hosting started.
  final Beacon Function() _describe;

  final Log _log = Log.scoped('mobile.host.bonjour');

  BonsoirBroadcast? _broadcast;
  bool _failed = false;

  @override
  bool get isAdvertising => _broadcast != null;

  @override
  Future<void> start() async {
    if (_broadcast != null || _failed) return;

    try {
      final beacon = _describe();
      final broadcast = BonsoirBroadcast(
        service: BonsoirService(
          // What a generic Bonjour browser shows, so it is the human name
          // rather than the device id.
          name: beacon.name,
          // The same constant this app browses with. A phone offering to
          // receive a file is the same kind of service as a computer offering
          // to be driven — the beacon's platform and capability fields are what
          // tell them apart — and publishing under a type that did not match
          // the browse exactly would simply make this phone invisible.
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
        'advertising this phone over Bonjour',
        fields: <String, Object?>{
          'type': kBonjourServiceType,
          'port': beacon.servicePort,
        },
      );
    } on Object catch (e) {
      // Never fatal, and on a phone that matters more than on the desktop: the
      // user asked to be discoverable, and failing to advertise costs them
      // being found, not being able to send. Taking the host down over it would
      // cost them both.
      _failed = true;
      _log.warn('Bonjour advertising unavailable on this phone', error: e);
    }
  }

  /// Republishes with the current description.
  ///
  /// DNS-SD has no cheap "update my TXT record" in this plugin, so a change is
  /// a stop and a start. Called only when something a browser can see actually
  /// changes, because browsers watch the service disappear and come back.
  @override
  Future<void> refresh() async {
    if (_broadcast == null) return;
    await stop();
    await start();
  }

  @override
  Future<void> stop() async {
    final broadcast = _broadcast;
    _broadcast = null;
    _failed = false;
    if (broadcast == null) return;
    try {
      await broadcast.stop();
    } on Object catch (e) {
      _log.debug(() => 'Bonjour stop failed: $e');
    }
  }
}
