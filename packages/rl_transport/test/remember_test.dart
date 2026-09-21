import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';
import 'package:test/test.dart';

/// Remembering a device means each end stops asking about the other, and that
/// is a promise neither end may make alone. Everything here is about the one
/// failure that matters: an agreement settling on fewer than two yeses.
void main() {
  DeviceId id(String value) => DeviceId.fromDigest(
        List<int>.filled(32, value.codeUnitAt(0)),
      );

  TrustedPeer peer({
    bool autoAdmit = false,
    bool rememberAsked = false,
    bool revoked = false,
  }) =>
      TrustedPeer(
        id: id('a'),
        publicKey: Uint8List(32),
        name: 'Pixel 9 Pro',
        platform: PlatformKind.android,
        pairedAt: DateTime.utc(2026),
        permissionTier: 2,
        autoAdmit: autoAdmit,
        rememberAsked: rememberAsked,
        revoked: revoked,
      );

  group('RememberAgreement', () {
    test('is not agreed until both answers are in', () {
      final agreement = RememberAgreement(peerId: id('a'), peerName: 'Phone')
        ..recordMine(agreed: true);

      expect(agreement.isSettled, isFalse);
      expect(agreement.isAgreed, isFalse);

      agreement.recordTheirs(agreed: true);
      expect(agreement.isSettled, isTrue);
      expect(agreement.isAgreed, isTrue);
    });

    test('one no is enough to settle it as no', () {
      final agreement = RememberAgreement(peerId: id('a'), peerName: 'Phone')
        ..recordMine(agreed: true)
        ..recordTheirs(agreed: false);

      expect(agreement.isSettled, isTrue);
      expect(agreement.isAgreed, isFalse);
    });

    test('a second answer from either end is ignored', () {
      // A peer has no legitimate reason to answer twice, and a local double tap
      // must not send two answers. Both are the same guard.
      final agreement = RememberAgreement(peerId: id('a'), peerName: 'Phone');

      expect(agreement.recordMine(agreed: false), isTrue);
      expect(agreement.recordMine(agreed: true), isFalse);
      expect(agreement.mine, isFalse);

      expect(agreement.recordTheirs(agreed: false), isTrue);
      expect(agreement.recordTheirs(agreed: true), isFalse);
      expect(agreement.theirs, isFalse);
    });

    test('a settled no records the asking without granting anything', () {
      final agreement = RememberAgreement(peerId: id('a'), peerName: 'Phone')
        ..recordMine(agreed: false)
        ..recordTheirs(agreed: true);

      final stored = agreement.applyTo(peer());
      expect(stored.autoAdmit, isFalse);
      expect(stored.rememberAsked, isTrue);
    });

    test('an agreement never lowers a promise already made', () {
      // Forgetting a device is something a person does in the device list. A
      // later session whose prompt was dismissed must not quietly undo it.
      final agreement = RememberAgreement(peerId: id('a'), peerName: 'Phone')
        ..recordMine(agreed: false)
        ..recordTheirs(agreed: false);

      expect(agreement.applyTo(peer(autoAdmit: true)).autoAdmit, isTrue);
    });
  });

  group('shouldAskToRemember', () {
    test('asks about a trusted device nobody has decided on', () {
      expect(shouldAskToRemember(peer()), isTrue);
    });

    test('does not ask about a device already remembered or already asked', () {
      expect(shouldAskToRemember(peer(autoAdmit: true)), isFalse);
      expect(shouldAskToRemember(peer(rememberAsked: true)), isFalse);
    });

    test('does not ask about a revoked device, or one it does not know', () {
      expect(shouldAskToRemember(peer(revoked: true)), isFalse);
      expect(shouldAskToRemember(null), isFalse);
    });
  });
}
