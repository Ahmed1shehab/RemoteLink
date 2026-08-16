import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/clipboard_sync.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

final class FakeClipboardBackend implements ClipboardBackend {
  FakeClipboardBackend({
    this.isAvailable = true,
    int initialChangeCount = 0,
    String? initialText,
    bool isConcealed = false,
  })  : _changeCount = initialChangeCount,
        _text = initialText,
        _isConcealed = isConcealed;

  @override
  bool isAvailable;

  int _changeCount;
  @override
  int get changeCount => _changeCount;

  String? _text;
  @override
  String? readText() => _text;

  @override
  void writeText(String text) {
    _text = text;
    _changeCount++;
  }

  bool _isConcealed;
  @override
  bool get isConcealed => _isConcealed;

  set isConcealed(bool value) => _isConcealed = value;

  List<int>? _imagePng;
  @override
  List<int>? readImagePng() => _imagePng;

  @override
  void writeImagePng(List<int> pngBytes) {
    _imagePng = pngBytes;
    _changeCount++;
  }

  void copyLocally(String text, {bool concealed = false}) {
    _text = text;
    _isConcealed = concealed;
    _changeCount++;
  }

  @override
  void dispose() {}
}

Future<Uint8List> _hash16(String text) async {
  final bytes = utf8.encode(text);
  final digest = await Primitives.sha256(bytes);
  return Uint8List.sublistView(digest, 0, 16);
}

Future<ClipboardUpdate> _makeUpdate(
  String text, {
  String originDeviceId = 'phone-device-1',
  int originSequence = 1,
}) async {
  final bytes = utf8.encode(text);
  final hash = await _hash16(text);
  return ClipboardUpdate(
    items: <ClipboardItem>[
      ClipboardItem(
        contentType: ClipboardContentType.text,
        data: Uint8List.fromList(bytes),
      ),
    ],
    contentHash: hash,
    originDeviceId: originDeviceId,
    originSequence: originSequence,
  );
}

void main() {
  const localDeviceId = DeviceId('desktop-device-1');
  const testPollInterval = Duration(milliseconds: 10);

  group('ClipboardSyncService', () {
    test(
        'local copy performed immediately after an applied remote update is still detected and broadcast',
        () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // 1. Remote update arrives and is applied
      final update = await _makeUpdate('remote text');
      await service.applyRemote(update);

      // 2. Immediately after applying remote, local user copies text
      // before the next poll tick
      backend.copyLocally('local text');

      // 3. Wait for poller to tick
      await Future<void>.delayed(const Duration(milliseconds: 35));

      // Assert the local copy was detected and broadcast
      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.first.plainText, equals('local text'));

      await sub.cancel();
      await service.dispose();
    });

    test('copying identical text twice in a row syncs both times', () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // 1. Copy text locally
      backend.copyLocally('repeated text');
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.first.plainText, equals('repeated text'));

      // 2. Copy identical text again locally
      backend.copyLocally('repeated text');
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, hasLength(2));
      expect(outboundUpdates[1].plainText, equals('repeated text'));

      await sub.cancel();
      await service.dispose();
    });

    test('an applied remote update is NOT echoed back', () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Apply remote update
      final update = await _makeUpdate('from phone');
      await service.applyRemote(update);

      // Poller ticks
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Outbound should be empty (no echo)
      expect(outboundUpdates, isEmpty);

      await sub.cancel();
      await service.dispose();
    });

    test('no sync loop under an alternating local/remote write sequence',
        () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // 1. Local write
      backend.copyLocally('local 1');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.last.plainText, equals('local 1'));

      // 2. Remote update applied
      final update1 = await _makeUpdate('remote 1', originSequence: 2);
      await service.applyRemote(update1);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      // Remote update should not echo
      expect(outboundUpdates, hasLength(1));

      // 3. Second local write
      backend.copyLocally('local 2');
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(outboundUpdates, hasLength(2));
      expect(outboundUpdates.last.plainText, equals('local 2'));

      // 4. Second remote update applied
      final update2 = await _makeUpdate('remote 2', originSequence: 4);
      await service.applyRemote(update2);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      // Remote update should not echo
      expect(outboundUpdates, hasLength(2));

      await sub.cancel();
      await service.dispose();
    });

    test('concealed content is never broadcast', () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Copy concealed text (e.g. from password manager)
      backend.copyLocally('secret-password', concealed: true);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, isEmpty);

      // Next normal copy should work
      backend.copyLocally('normal text', concealed: false);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.first.plainText, equals('normal text'));

      await sub.cancel();
      await service.dispose();
    });

    test('self-written hash expires after 2 seconds allowing a re-copy',
        () async {
      final clock = FakeClock();
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        clock: clock,
        pollInterval: testPollInterval,
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Apply a remote write
      final update = await _makeUpdate('password123');
      await service.applyRemote(update);

      // Wait for echo suppression to consume it on poll
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(outboundUpdates, isEmpty);

      // Advance clock past 2-second expiry
      clock.advance(const Duration(milliseconds: 2500));

      // User re-copies the exact same password locally
      backend.copyLocally('password123');
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Re-copy must be broadcast
      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.first.plainText, equals('password123'));

      await sub.cancel();
      await service.dispose();
    });

    test('retains up to 3 recent self-written hashes in a ring buffer',
        () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // Apply 4 remote updates without letting poller tick between them
      // to overflow the 3-entry ring buffer
      final u1 = await _makeUpdate('msg1', originSequence: 1);
      final u2 = await _makeUpdate('msg2', originSequence: 2);
      final u3 = await _makeUpdate('msg3', originSequence: 3);
      final u4 = await _makeUpdate('msg4', originSequence: 4);

      await service.applyRemote(u1);
      await service.applyRemote(u2);
      await service.applyRemote(u3);
      await service.applyRemote(u4);

      // u1 should have been evicted from the 3-entry buffer ([u2, u3, u4] retained).
      // If the user now copies 'msg1' locally:
      backend.copyLocally('msg1');
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // 'msg1' is no longer in self-writes so it must be broadcast!
      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.first.plainText, equals('msg1'));

      await sub.cancel();
      await service.dispose();
    });

    test('snapshot returns current clipboard content or null if concealed',
        () async {
      final backend = FakeClipboardBackend(initialText: 'initial snippet');
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
      );

      final snap = await service.snapshot();
      expect(snap, isNotNull);
      expect(snap!.plainText, equals('initial snippet'));
      expect(snap.originDeviceId, equals(localDeviceId.value));

      // Concealed clipboard returns null snapshot
      backend.isConcealed = true;
      final concealedSnap = await service.snapshot();
      expect(concealedSnap, isNull);

      await service.dispose();
    });

    test('remoteWins resolves concurrent conflicts deterministically', () {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: const DeviceId('desktop-b'),
      );

      // Higher sequence wins
      final higherSeq = ClipboardUpdate(
        items: const <ClipboardItem>[],
        contentHash: Uint8List(16),
        originDeviceId: 'desktop-a',
        originSequence: 5,
      );
      expect(service.remoteWins(higherSeq), isTrue);

      // On sequence tie, lexicographically greater deviceId wins
      final tieHigherDevice = ClipboardUpdate(
        items: const <ClipboardItem>[],
        contentHash: Uint8List(16),
        originDeviceId: 'desktop-c',
        originSequence: 0,
      );
      expect(service.remoteWins(tieHigherDevice), isTrue);

      final tieLowerDevice = ClipboardUpdate(
        items: const <ClipboardItem>[],
        contentHash: Uint8List(16),
        originDeviceId: 'desktop-a',
        originSequence: 0,
      );
      expect(service.remoteWins(tieLowerDevice), isFalse);
    });
  });
}
