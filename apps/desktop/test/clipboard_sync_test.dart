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
    _imagePng = null;
    _isConcealed = concealed;
    _changeCount++;
  }

  void copyImageLocally(List<int> pngBytes, {bool concealed = false}) {
    _imagePng = pngBytes;
    _text = null;
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

Future<ClipboardUpdate> _makeImageUpdate(
  List<int> pngBytes, {
  String originDeviceId = 'phone-device-1',
  int originSequence = 1,
}) async {
  final data = pngBytes is Uint8List ? pngBytes : Uint8List.fromList(pngBytes);
  final digest = await Primitives.sha256(data);
  final hash = Uint8List.sublistView(digest, 0, 16);
  return ClipboardUpdate(
    items: <ClipboardItem>[
      ClipboardItem(
        contentType: ClipboardContentType.imagePng,
        data: data,
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

    test('an image under the auto-sync threshold syncs', () async {
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

      final samplePng =
          Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
      backend.copyImageLocally(samplePng);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, hasLength(1));
      final update = outboundUpdates.first;
      expect(update.items, hasLength(1));
      expect(update.items.first.contentType,
          equals(ClipboardContentType.imagePng));
      expect(update.items.first.data, equals(samplePng));

      await sub.cancel();
      await service.dispose();
    });

    test('an image over 1 MiB does not sync automatically', () async {
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

      // 1 MiB + 1 byte
      final largeImage = Uint8List(1024 * 1024 + 1);
      backend.copyImageLocally(largeImage);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, isEmpty);

      await sub.cancel();
      await service.dispose();
    });

    test('an image over 10 MiB is skipped entirely', () async {
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

      // 10 MiB + 1 byte
      final oversizedImage = Uint8List(10 * 1024 * 1024 + 1);
      backend.copyImageLocally(oversizedImage);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, isEmpty);

      // Inbound oversized image is also skipped
      final inboundBackend = FakeClipboardBackend();
      final inboundService = ClipboardSyncService(
        clipboard: inboundBackend,
        localDeviceId: localDeviceId,
      );
      final oversizedUpdate = await _makeImageUpdate(oversizedImage);
      final applied = await inboundService.applyRemote(oversizedUpdate);
      expect(applied, isFalse);
      expect(inboundBackend.readImagePng(), isNull);
      await inboundService.dispose();

      await sub.cancel();
      await service.dispose();
    });

    test('a concealed image is never broadcast', () async {
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

      final samplePng =
          Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 4, 5, 6]);
      backend.copyImageLocally(samplePng, concealed: true);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, isEmpty);

      // Normal un-concealed image copy should sync
      backend.copyImageLocally(samplePng, concealed: false);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.first.items.first.data, equals(samplePng));

      await sub.cancel();
      await service.dispose();
    });

    test('an inbound image update is applied to the local clipboard', () async {
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

      final samplePng =
          Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 7, 8, 9]);
      final update = await _makeImageUpdate(samplePng);

      final applied = await service.applyRemote(update);
      expect(applied, isTrue);
      expect(backend.readImagePng(), equals(samplePng));

      // Echo suppression: poller tick should not produce an outbound echo
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(outboundUpdates, isEmpty);

      await sub.cancel();
      await service.dispose();
    });

    test('snapshot returns current image or null if concealed or > 1 MiB',
        () async {
      final samplePng =
          Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 10, 11]);
      final backend = FakeClipboardBackend();
      backend.writeImagePng(samplePng);

      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
      );

      final snap = await service.snapshot();
      expect(snap, isNotNull);
      expect(snap!.items, hasLength(1));
      expect(
          snap.items.first.contentType, equals(ClipboardContentType.imagePng));
      expect(snap.items.first.data, equals(samplePng));

      // Concealed image snapshot returns null
      backend.isConcealed = true;
      expect(await service.snapshot(), isNull);

      // Unconcealed but > 1 MiB returns null
      backend.isConcealed = false;
      backend.writeImagePng(Uint8List(1024 * 1024 + 1));
      expect(await service.snapshot(), isNull);

      await service.dispose();
    });

    test(
        'toggling off for one device stops sync for that device ONLY, with a second connected device still receiving updates',
        () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      const device1 = DeviceId('phone-device-1');
      const device2 = DeviceId('phone-device-2');

      // Both devices are enabled by default
      expect(service.isPeerEnabled(device1), isTrue);
      expect(service.isPeerEnabled(device2), isTrue);

      // 1. Toggle off sync for device 1 via ClipboardSyncToggle
      service.handleToggle(
        device1,
        const ClipboardSyncToggle(
          enabled: false,
          allowImages: false,
          allowFiles: false,
        ),
      );

      expect(service.isPeerEnabled(device1), isFalse);
      expect(service.isPeerEnabled(device2), isTrue);

      // 2. Local copy on the host
      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      backend.copyLocally('broadcast message');
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(outboundUpdates, hasLength(1));
      final update = outboundUpdates.first;
      expect(update.plainText, equals('broadcast message'));

      // Outbound recipient filtering simulation matching DesktopService._broadcastClipboard
      final targets =
          <DeviceId>[device1, device2].where(service.isPeerEnabled).toList();
      expect(targets, contains(device2));
      expect(targets, isNot(contains(device1)));

      // 3. Inbound update from device 1 (disabled) is rejected and NOT written to host
      final updateFromDevice1 = await _makeUpdate(
        'from phone 1',
        originDeviceId: device1.value,
      );
      final applied1 = await service.applyRemote(updateFromDevice1);
      expect(applied1, isFalse);
      expect(backend.readText(), equals('broadcast message')); // unchanged

      // 4. Inbound update from device 2 (enabled) is applied and written to host
      final updateFromDevice2 = await _makeUpdate(
        'from phone 2',
        originDeviceId: device2.value,
      );
      final applied2 = await service.applyRemote(updateFromDevice2);
      expect(applied2, isTrue);
      expect(backend.readText(), equals('from phone 2'));

      await sub.cancel();
      await service.dispose();
    });

    test('the setting survives a simulated reconnect', () async {
      final backend = FakeClipboardBackend(initialText: 'current clipboard');
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      const device1 = DeviceId('phone-device-1');
      const device2 = DeviceId('phone-device-2');

      // Toggle off device 1
      service.handleToggle(
        device1,
        const ClipboardSyncToggle(
          enabled: false,
          allowImages: false,
          allowFiles: false,
        ),
      );

      expect(service.isPeerEnabled(device1), isFalse);

      // Simulate device 1 reconnecting and requesting snapshot
      final snap1 = await service.snapshot(peerId: device1);
      expect(snap1, isNull);

      // Device 2 requesting snapshot gets the content
      final snap2 = await service.snapshot(peerId: device2);
      expect(snap2, isNotNull);
      expect(snap2!.plainText, equals('current clipboard'));

      // Inbound from device 1 is still rejected after reconnect
      final update1 = await _makeUpdate(
        'reconnected phone 1',
        originDeviceId: device1.value,
      );
      expect(await service.applyRemote(update1), isFalse);

      // Re-enabling device 1 restores sync and snapshot
      service.handleToggle(
        device1,
        const ClipboardSyncToggle(
          enabled: true,
          allowImages: true,
          allowFiles: false,
        ),
      );
      expect(service.isPeerEnabled(device1), isTrue);
      final restoredSnap = await service.snapshot(peerId: device1);
      expect(restoredSnap, isNotNull);
      expect(restoredSnap!.plainText, equals('current clipboard'));

      final applied = await service.applyRemote(update1);
      expect(applied, isTrue);
      expect(backend.readText(), equals('reconnected phone 1'));

      await service.dispose();
    });

    test(
        'toggling off does not disturb concealed-content handling or the echo suppression already there',
        () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      const device1 = DeviceId('phone-device-1');
      const device2 = DeviceId('phone-device-2');

      // Disable device 1
      service.handleToggle(
        device1,
        const ClipboardSyncToggle(
          enabled: false,
          allowImages: false,
          allowFiles: false,
        ),
      );

      final outboundUpdates = <ClipboardUpdate>[];
      final sub = service.outbound.listen(outboundUpdates.add);

      service.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      // 1. Concealed text is not broadcast
      backend.copyLocally('secret-password', concealed: true);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(outboundUpdates, isEmpty);

      // 2. Echo suppression on device 2 (enabled device)
      final updateFromDevice2 = await _makeUpdate(
        'device 2 text',
        originDeviceId: device2.value,
      );
      final applied = await service.applyRemote(updateFromDevice2);
      expect(applied, isTrue);
      expect(backend.readText(), equals('device 2 text'));

      // Wait for poll - should NOT echo back
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(outboundUpdates, isEmpty);

      // 3. Normal local copy is broadcast
      backend.copyLocally('normal text', concealed: false);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(outboundUpdates, hasLength(1));
      expect(outboundUpdates.first.plainText, equals('normal text'));

      await sub.cancel();
      await service.dispose();
    });

    test(
        'respects allowImages directionally per device without disabling text sync',
        () async {
      final backend = FakeClipboardBackend();
      final service = ClipboardSyncService(
        clipboard: backend,
        localDeviceId: localDeviceId,
        pollInterval: testPollInterval,
      );

      const device1 = DeviceId('phone-device-1');

      // Device 1 allows text but disallows images
      service.handleToggle(
        device1,
        const ClipboardSyncToggle(
          enabled: true,
          allowImages: false,
          allowFiles: false,
        ),
      );

      expect(service.isPeerEnabled(device1), isTrue);
      expect(service.allowsImagesForPeer(device1), isFalse);

      // Text from device 1 is applied
      final textUpdate =
          await _makeUpdate('text ok', originDeviceId: device1.value);
      expect(await service.applyRemote(textUpdate), isTrue);
      expect(backend.readText(), equals('text ok'));

      // Image from device 1 is rejected
      final samplePng = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2]);
      final imageUpdate =
          await _makeImageUpdate(samplePng, originDeviceId: device1.value);
      expect(await service.applyRemote(imageUpdate), isFalse);

      await service.dispose();
    });
  });
}
