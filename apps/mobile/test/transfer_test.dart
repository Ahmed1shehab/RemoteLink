import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/transfer/file_exporter.dart';
import 'package:remotelink_mobile/src/features/transfer/image_preview.dart';
import 'package:remotelink_mobile/src/features/transfer/mobile_transfer_store.dart';
import 'package:remotelink_mobile/src/features/transfer/transfer_controller.dart';
import 'package:remotelink_mobile/src/features/transfer/transfer_model.dart';
import 'package:remotelink_mobile/src/features/transfer/transfer_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  group('Mobile Transfer Models & Utilities', () {
    test('generateTextSnippetFileName produces sanitized timestamped filename',
        () {
      final time = DateTime.utc(2026, 8, 16, 15, 30, 45);
      final name = generateTextSnippetFileName(timestamp: time);
      expect(name, 'snippet_20260816_153045.txt');
    });

    test('formatBytes formats B, KB, MB, and GB', () {
      expect(formatBytes(500), '500 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatBytes(3 * 1024 * 1024 * 1024), '3.00 GB');
    });

    test('formatSpeed and formatEta format transfer rates and durations', () {
      expect(formatSpeed(800), '800 B/s');
      expect(formatSpeed(1500 * 1024), '1.5 MB/s');
      expect(formatEta(null), '--');
      expect(formatEta(const Duration(seconds: 45)), '45s');
      expect(formatEta(const Duration(minutes: 2, seconds: 15)), '2m 15s');
      expect(formatEta(const Duration(hours: 1, minutes: 30)), '1h 30m');
    });

    test('TransferSpeedTracker calculates rate and ETA correctly', () {
      final tracker = TransferSpeedTracker();
      final t0 = DateTime(2026, 8, 16, 12, 0, 0);
      tracker.record(0, now: t0);
      final t1 = DateTime(2026, 8, 16, 12, 0, 1);
      tracker.record(1024 * 1024, now: t1); // 1 MB transferred in 1 second

      final speed = tracker.calculateSpeed(now: t1);
      expect(speed, greaterThan(1000000));

      final eta = tracker.calculateEta(10 * 1024 * 1024, 1024 * 1024, speed);
      expect(eta?.inSeconds, closeTo(9, 1));
    });

    test('MemoryOutgoingFile reads slices accurately', () async {
      final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]);
      final file = MemoryOutgoingFile(bytes);
      expect(file.size, 8);

      final slice = await file.read(2, 4);
      expect(slice, <int>[3, 4, 5, 6]);

      expect(() => file.read(6, 4), throwsRangeError);
    });

    test('retry is offered only for outgoing recoverable transfers', () {
      TransferRecord record(TransferDirection direction) => TransferRecord(
            transferId: 'retry-1',
            peerId: const DeviceId('desktop-1'),
            peerName: 'Desktop',
            direction: direction,
            status: TransferStatus.failed,
            files: const <TransferFileProgress>[],
            totalBytes: 0,
            transferredBytes: 0,
            createdAt: DateTime(2026),
          );

      expect(record(TransferDirection.outgoing).canRetry, isTrue);
      expect(record(TransferDirection.incoming).canRetry, isFalse);
    });
  });

  group('MobileTransferStore', () {
    late Directory tempDir;
    late MobileTransferStore store;
    late _RecordingExporter exporter;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mobile_store_test_');
      exporter = _RecordingExporter();
      store = MobileTransferStore(tempDir, exporter: exporter);
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('sanitiseFileName rejects directory traversal path components', () {
      expect(
        () => sanitiseFileName('../../etc/passwd'),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => sanitiseFileName(r'..\Windows\System32\cmd.exe'),
        throwsA(isA<ProtocolError>()),
      );
      expect(sanitiseFileName('valid_file.txt'), 'valid_file.txt');
    });

    test('prepares incoming files and writes partials', () async {
      final offer = FileOffer(
        transferId: 't-1',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-safe',
            fileName: 'safe_document.pdf',
            size: 100,
            fileType: 'application/pdf',
          ),
        ],
      );

      final files = await store.prepare(offer, namespace: 'session-1');
      final incoming = files['f-safe']!;
      expect(incoming.offer.fileName, 'safe_document.pdf');

      await incoming.write(0, Uint8List.fromList(<int>[1, 2, 3, 4]));
      await incoming.delete();
    });

    test('records chunk byte ranges and creates final file on commit',
        () async {
      final offer = FileOffer(
        transferId: 't-1',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-1',
            fileName: 'test.bin',
            size: 8,
            fileType: 'application/octet-stream',
          ),
        ],
      );

      final files = await store.prepare(offer, namespace: 'session-2');
      final incoming = files['f-1']!;
      await incoming.write(0, Uint8List.fromList(<int>[1, 2, 3, 4]));
      await incoming.write(4, Uint8List.fromList(<int>[5, 6, 7, 8]));

      await incoming.commit();

      // The file is handed to the phone, and the staging root is left clean:
      // the assembled bytes sitting beside the partials is a transient state
      // that ends inside commit().
      expect(exporter.exported, hasLength(1));
      expect(exporter.exported.single.bytes, <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(
        File('${tempDir.path}/test.bin').existsSync(),
        isFalse,
        reason: 'the staging root is not where a delivered file lives',
      );
    });

    test('a delivered file stays openable from the transfer list', () async {
      // The transfer list names files that have arrived, and tapping one of
      // those names should open it. That needs the file to still be somewhere,
      // and this is the record of where.
      final offer = FileOffer(
        transferId: 't-keep',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-1',
            fileName: 'holiday.jpg',
            size: 4,
            fileType: 'image/jpeg',
          ),
        ],
      );

      final incoming =
          (await store.prepare(offer, namespace: 'session-keep'))['f-1']!;
      await incoming.write(0, Uint8List.fromList(<int>[7, 7, 7, 7]));
      await incoming.commit();

      final kept = store.keptPath(transferId: 't-keep', fileId: 'f-1');
      expect(kept, isNotNull);
      expect(File(kept!).readAsBytesSync(), <int>[7, 7, 7, 7]);
      expect(
        kept,
        contains(kReceivedDirectoryName),
        reason: 'kept files are gathered in one place the cache can drop',
      );
    });

    test('a refused export keeps nothing to open', () async {
      // The mirror of the test above, and the more important half. A file the
      // user declined to receive is not one to hold on to on their behalf.
      final failing = _RecordingExporter(
        throws: const ExportError(ExportFailure.permissionDenied),
      );
      final failingStore = MobileTransferStore(tempDir, exporter: failing);
      final offer = FileOffer(
        transferId: 't-refused',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-1',
            fileName: 'refused.jpg',
            size: 2,
            fileType: 'image/jpeg',
          ),
        ],
      );

      final incoming = (await failingStore.prepare(offer,
          namespace: 'session-refused'))['f-1']!;
      await incoming.write(0, Uint8List.fromList(<int>[1, 2]));
      await expectLater(incoming.commit(), throwsA(isA<ExportError>()));

      expect(
        failingStore.keptPath(transferId: 't-refused', fileId: 'f-1'),
        isNull,
      );
      final keep = Directory('${tempDir.path}/$kReceivedDirectoryName');
      expect(
        !keep.existsSync() || keep.listSync().isEmpty,
        isTrue,
        reason: 'a refused file leaves the app exactly as it found it',
      );
    });

    test('the keep drops the oldest file once it is full', () async {
      // Otherwise this is a photo library the user cannot see, did not ask for,
      // and has no way to empty.
      for (var index = 0; index < kKeptFileCount + 3; index++) {
        final offer = FileOffer(
          transferId: 't-full-$index',
          files: <OfferedFile>[
            OfferedFile(
              fileId: 'f-1',
              fileName: 'shot_$index.jpg',
              size: 1,
              fileType: 'image/jpeg',
            ),
          ],
        );
        final incoming =
            (await store.prepare(offer, namespace: 'session-full-$index'))[
                'f-1']!;
        await incoming.write(0, Uint8List.fromList(<int>[index]));
        await incoming.commit();
      }

      final keep = Directory('${tempDir.path}/$kReceivedDirectoryName');
      expect(keep.listSync().whereType<File>(), hasLength(kKeptFileCount));
      expect(
        store.keptPath(transferId: 't-full-0', fileId: 'f-1'),
        isNull,
        reason: 'the first file in is the first one out',
      );
      expect(
        store.keptPath(
          transferId: 't-full-${kKeptFileCount + 2}',
          fileId: 'f-1',
        ),
        isNotNull,
        reason: 'the newest arrival is the last thing to be dropped',
      );
    });

    test('an export that fails still leaves nothing behind', () async {
      // The path that matters most. A refused photo permission or a dismissed
      // share sheet must not turn the staging directory into the storage this
      // app is not supposed to have.
      final failing = _RecordingExporter(
        throws: const ExportError(ExportFailure.cancelled),
      );
      final failingStore = MobileTransferStore(tempDir, exporter: failing);
      final offer = FileOffer(
        transferId: 't-fail',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-1',
            fileName: 'declined.bin',
            size: 4,
            fileType: 'application/octet-stream',
          ),
        ],
      );

      final incoming = (await failingStore.prepare(offer,
          namespace: 'session-fail'))['f-1']!;
      await incoming.write(0, Uint8List.fromList(<int>[9, 9, 9, 9]));

      await expectLater(incoming.commit(), throwsA(isA<ExportError>()));
      expect(File('${tempDir.path}/declined.bin').existsSync(), isFalse);
      expect(
        File('${tempDir.path}/$kReceivedDirectoryName/declined.bin')
            .existsSync(),
        isFalse,
        reason: 'the keep is for files that were delivered, not attempted',
      );
    });

    test('a photo goes to the library and a document to the share sheet',
        () async {
      // The whole of the routing rule, asserted on the one thing that decides
      // it. The photo library cannot hold a PDF, and a photo filed into a
      // folder is a photo missing from the camera roll.
      for (final (name, mime) in const <(String, String)>[
        ('holiday.jpg', 'image/jpeg'),
        ('clip.mov', 'video/quicktime'),
        ('report.pdf', 'application/pdf'),
      ]) {
        final offer = FileOffer(
          transferId: 't-$name',
          files: <OfferedFile>[
            OfferedFile(fileId: 'f-1', fileName: name, size: 1, fileType: mime),
          ],
        );
        final incoming =
            (await store.prepare(offer, namespace: 'session-mime'))['f-1']!;
        await incoming.write(0, Uint8List.fromList(<int>[1]));
        await incoming.commit();
      }

      expect(
        exporter.exported.map((e) => e.mimeType),
        <String>['image/jpeg', 'video/quicktime', 'application/pdf'],
        reason: 'the exporter is told the type, and decides from it',
      );
    });

    test('a hostile fileType from a peer does not influence destination path',
        () async {
      final hostileOffer = FileOffer(
        transferId: 'hostile-mime-mobile',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-1',
            fileName: 'safe_document.pdf',
            size: 4,
            fileType: '../../../../evil/path/traversal.sh',
          ),
        ],
      );

      final files = await store.prepare(hostileOffer, namespace: 'session-3');
      final incoming = files['f-1']!;
      await incoming.write(0, Uint8List.fromList(<int>[1, 2, 3, 4]));
      await incoming.commit();

      expect(exporter.exported.single.bytes, <int>[1, 2, 3, 4]);
      expect(File('${tempDir.path}/safe_document.pdf').existsSync(), isFalse);
      expect(File('${tempDir.parent.path}/traversal.sh').existsSync(), isFalse);
    });
  });

  group('TransferScreen Widget Tests', () {
    testWidgets('renders targets with Media first and File second',
        (tester) async {
      final now = DateTime.now();
      final targetPeer = TrustedPeer(
        id: const DeviceId('desktop-device-id'),
        name: 'Ahmed MacBook',
        platform: PlatformKind.macos,
        publicKey: Uint8List(32),
        pairedAt: now,
        permissionTier: PermissionTier.extended.wireValue,
      );

      const targetDevice = DeviceInfo(
        id: DeviceId('desktop-device-id'),
        name: 'Ahmed MacBook',
        platform: PlatformKind.macos,
        role: PeerRole.server,
        appVersion: '0.1.0',
      );

      final beacon = Beacon(
        kind: BeaconKind.announce,
        deviceId: const DeviceId('desktop-device-id'),
        name: 'Ahmed MacBook',
        platform: PlatformKind.macos,
        servicePort: 41234,
        protocolVersion: 1,
        publicKeyFingerprint: Uint8List(8),
        capabilities: const Capabilities(Capabilities.sessionResumption),
      );

      final discoveredDevice = DiscoveredDevice(
        beacon: beacon,
        address: '192.168.1.50',
        firstSeen: now,
        lastSeen: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            // The screen sends to the connected computer and only that one,
            // so this is the seam that decides whether Send is live.
            // Overridden directly rather than by faking a session: the
            // provider it reads needs an established `Session`, which cannot
            // be built in a widget test without a socket.
            transferTargetProvider.overrideWithValue(
              (id: targetPeer.id, name: targetPeer.name),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            connectedPeerProvider.overrideWith(
              (ref) => Stream<DeviceInfo?>.value(targetDevice),
            ),
            discoveredDevicesProvider.overrideWith(
              (ref) => Stream<List<DiscoveredDevice>>.value(<DiscoveredDevice>[
                discoveredDevice,
              ]),
            ),
            trustedPeersProvider.overrideWith(
              (ref) async => <TrustedPeer>[targetPeer],
            ),
            mobileTransferStoreProvider.overrideWith(
              (ref) async => MobileTransferStore(Directory.systemTemp),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: TransferScreen())),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Send to device'), findsOneWidget);
      expect(find.text('Text / URL'), findsNothing);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Media'), findsOneWidget);
      expect(find.text('Send Media'), findsOneWidget);
      expect(find.text('Choose media'), findsOneWidget);

      // Switch to File mode. This used to assert a "File path" text field, in
      // which the user was expected to type an absolute path by hand — the
      // screen offers a picker now, and the field is gone.
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      expect(find.text('Choose files'), findsOneWidget);
      expect(find.text('Send File'), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'a long device name renders without an overflow in the target dropdown',
        (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Max device name length allowed by protocol is 64 graphemes.
      const longName =
          'My Very Long Desktop Workstation Computer Name Graphemes 1234567';
      expect(longName.length, lessThanOrEqualTo(64));

      final now = DateTime.now();
      final targetPeer = TrustedPeer(
        id: const DeviceId('desktop-long-name-id'),
        name: longName,
        platform: PlatformKind.macos,
        publicKey: Uint8List(32),
        pairedAt: now,
        permissionTier: PermissionTier.extended.wireValue,
      );

      final beacon = Beacon(
        kind: BeaconKind.announce,
        deviceId: const DeviceId('desktop-long-name-id'),
        name: longName,
        platform: PlatformKind.macos,
        servicePort: 41234,
        protocolVersion: 1,
        publicKeyFingerprint: Uint8List(8),
        capabilities: const Capabilities(Capabilities.sessionResumption),
      );

      final discoveredDevice = DiscoveredDevice(
        beacon: beacon,
        address: '192.168.1.50',
        firstSeen: now,
        lastSeen: now,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            // The screen sends to the connected computer and only that one,
            // so this is the seam that decides whether Send is live.
            // Overridden directly rather than by faking a session: the
            // provider it reads needs an established `Session`, which cannot
            // be built in a widget test without a socket.
            transferTargetProvider.overrideWithValue(
              (id: targetPeer.id, name: targetPeer.name),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            discoveredDevicesProvider.overrideWith(
              (ref) => Stream<List<DiscoveredDevice>>.value(<DiscoveredDevice>[
                discoveredDevice,
              ]),
            ),
            trustedPeersProvider.overrideWith(
              (ref) async => <TrustedPeer>[targetPeer],
            ),
            mobileTransferStoreProvider.overrideWith(
              (ref) async => MobileTransferStore(Directory.systemTemp),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: TransferScreen())),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'choosing and sending a video results in an offer with video MIME type',
        (tester) async {
      await tester.runAsync(() async {
        final phoneIdentity = await DeviceIdentity.generate();
        final desktopIdentity = await DeviceIdentity.generate();

        final desktopTrust = InMemoryTrustStore();
        await desktopTrust.upsert(
          TrustedPeer(
            id: phoneIdentity.id,
            publicKey: phoneIdentity.publicKey,
            name: 'Test Phone',
            platform: PlatformKind.android,
            pairedAt: DateTime.now(),
            permissionTier: PermissionTier.extended.wireValue,
          ),
        );

        final server = RemoteLinkServer(
          identity: desktopIdentity,
          capabilities: const Capabilities(Capabilities.sessionResumption),
          trustStore: desktopTrust,
          clock: SystemClock(),
          port: 0,
        );
        await server.start();

        final client = RemoteLinkClient(
          identity: phoneIdentity,
          capabilities: const Capabilities(Capabilities.sessionResumption),
          clock: SystemClock(),
        );

        final acceptedFuture = server.accepted.first;

        final connectedFuture = client.states.firstWhere(
          (s) => s == ClientState.connected,
        );

        await client.connect(
          ConnectionTarget(
            host: '127.0.0.1',
            port: server.boundPort,
            deviceId: desktopIdentity.id,
            serverPublicKey: desktopIdentity.publicKey,
          ),
        );

        await connectedFuture.timeout(const Duration(seconds: 10));
        final serverSession =
            await acceptedFuture.timeout(const Duration(seconds: 10));

        final tempDir =
            Directory.systemTemp.createTempSync('video_transfer_test');

        final videoFile = File('${tempDir.path}/holiday.mp4')
          ..writeAsStringSync('dummy mp4 video bytes');

        final container = ProviderContainer(
          overrides: <Override>[
            clientProvider.overrideWith((ref) async => client),
            // The screen sends to the connected computer and only that one,
            // so this is the seam that decides whether Send is live.
            // Overridden directly rather than by faking a session: the
            // provider it reads needs an established `Session`, which cannot
            // be built in a widget test without a socket.
            transferTargetProvider.overrideWithValue(
              (id: const DeviceId('desktop-1'), name: 'Work Mac'),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            transferControllerProvider.overrideWith(
              (ref) => MobileTransferController(
                ref,
                customTransferStore: MobileTransferStore(tempDir),
              ),
            ),
          ],
        );

        try {
          await container.read(clientProvider.future);
          final controller =
              container.read(transferControllerProvider.notifier);

          final offerFuture = serverSession.session.messages.firstWhere(
            (msg) => msg is FileOffer,
          );

          await controller.sendFiles(
            targetPeerId: desktopIdentity.id,
            targetPeerName: 'Desktop Server',
            files: <File>[videoFile],
            fileNames: <String>['holiday.mp4'],
          );

          final receivedMessage =
              await offerFuture.timeout(const Duration(seconds: 5));
          expect(receivedMessage, isA<FileOffer>());
          final offer = receivedMessage as FileOffer;
          expect(offer.files, hasLength(1));
          expect(offer.files.single.fileName, 'holiday.mp4');
          expect(offer.files.single.fileType, 'video/mp4');
          expect(
              offer.files.single.fileType, isNot('application/octet-stream'));
        } finally {
          container.dispose();
          tempDir.deleteSync(recursive: true);
          await client.dispose();
          await server.stop();
          await desktopTrust.dispose();
        }
      });
    });

    testWidgets('renders active transfers with progress, speed, ETA and cancel',
        (tester) async {
      final transferRecord = TransferRecord(
        transferId: 'transfer-1',
        peerId: const DeviceId('desktop-1'),
        peerName: 'Ahmed Desktop',
        direction: TransferDirection.outgoing,
        status: TransferStatus.inProgress,
        files: const <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'f-1',
            fileName: 'video_clip.mp4',
            totalBytes: 10 * 1024 * 1024,
            transferredBytes: 5 * 1024 * 1024,
          ),
        ],
        totalBytes: 10 * 1024 * 1024,
        transferredBytes: 5 * 1024 * 1024,
        speedBytesPerSecond: 2 * 1024 * 1024,
        eta: const Duration(seconds: 3),
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            // The screen sends to the connected computer and only that one,
            // so this is the seam that decides whether Send is live.
            // Overridden directly rather than by faking a session: the
            // provider it reads needs an established `Session`, which cannot
            // be built in a widget test without a socket.
            transferTargetProvider.overrideWithValue(
              (id: const DeviceId('desktop-1'), name: 'Work Mac'),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            transferControllerProvider.overrideWith((ref) {
              final controller = MobileTransferController(
                ref,
                customTransferStore: MobileTransferStore(Directory.systemTemp),
              );
              controller.state = TransferState(
                transfers: <TransferRecord>[transferRecord],
              );
              return controller;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: TransferScreen())),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('To Ahmed Desktop'), findsOneWidget);
      expect(find.text('video_clip.mp4'), findsOneWidget);
      expect(find.text('5.0 MB / 10.0 MB'), findsWidgets);
      expect(find.text('Transferring'), findsOneWidget);
      expect(find.text('·  2.0 MB/s'), findsOneWidget);
      expect(find.text('·  ETA: 3s'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a received file is something the list can open', (tester) async {
      // The complaint this answers: tapping the name of a photo that had just
      // arrived did nothing, and the only way to see it was to leave the app
      // and find it in the gallery.
      //
      // Asserted on the row rather than on the preview it pushes. Opening it
      // for real would put an `Image.file` on screen, and a file-backed image
      // never finishes decoding under a test's fake clock — the suite hangs
      // until it times out. The tap itself is covered by the stale-path test
      // below, which follows the same handler all the way to its message.
      // Synchronous, and it has to be: a widget test runs on a fake clock, and
      // awaiting real filesystem I/O outside `runAsync` is a future that never
      // completes.
      final directory =
          Directory.systemTemp.createTempSync('received_open_test_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final photo = File('${directory.path}/holiday.png')
        ..writeAsBytesSync(base64Decode(_kOnePixelPng));

      final received = TransferRecord(
        transferId: 'in-open',
        peerId: const DeviceId('desktop-1'),
        peerName: 'Work Mac',
        direction: TransferDirection.incoming,
        status: TransferStatus.completed,
        files: <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'f-1',
            fileName: 'holiday.png',
            totalBytes: 4,
            transferredBytes: 4,
            isComplete: true,
            savedPath: photo.path,
          ),
          // Sent, not received, so there is nothing of it on this phone.
          const TransferFileProgress(
            fileId: 'f-2',
            fileName: 'notes.txt',
            totalBytes: 4,
            transferredBytes: 4,
            isComplete: true,
          ),
        ],
        totalBytes: 8,
        transferredBytes: 8,
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            transferTargetProvider.overrideWithValue(
              (id: const DeviceId('desktop-1'), name: 'Work Mac'),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            transferControllerProvider.overrideWith((ref) {
              final controller = MobileTransferController(
                ref,
                customTransferStore: MobileTransferStore(Directory.systemTemp),
              );
              controller.state =
                  TransferState(transfers: <TransferRecord>[received]);
              return controller;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: TransferScreen())),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(
        find.ancestor(
          of: find.text('holiday.png'),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
        reason: 'a file that is still here is a file you can press',
      );
      expect(
        find.ancestor(
          of: find.text('notes.txt'),
          matching: find.byType(InkWell),
        ),
        findsNothing,
        reason: 'and one that never landed here is not',
      );
      // Which of the two things a tap does, said before it happens.
      expect(find.byIcon(Icons.zoom_out_map_rounded), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a file the phone no longer holds says so rather than nothing',
        (tester) async {
      // The cache this keeps files in is the OS's to empty, so the path on a
      // row can go stale between being drawn and being tapped.
      final received = TransferRecord(
        transferId: 'in-gone',
        peerId: const DeviceId('desktop-1'),
        peerName: 'Work Mac',
        direction: TransferDirection.incoming,
        status: TransferStatus.completed,
        files: const <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'f-1',
            fileName: 'evicted.png',
            totalBytes: 4,
            transferredBytes: 4,
            isComplete: true,
            savedPath: '/does/not/exist/evicted.png',
          ),
        ],
        totalBytes: 4,
        transferredBytes: 4,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            transferTargetProvider.overrideWithValue(
              (id: const DeviceId('desktop-1'), name: 'Work Mac'),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            transferControllerProvider.overrideWith((ref) {
              final controller = MobileTransferController(
                ref,
                customTransferStore: MobileTransferStore(Directory.systemTemp),
              );
              controller.state =
                  TransferState(transfers: <TransferRecord>[received]);
              return controller;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: TransferScreen())),
        ),
      );

      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('evicted.png'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ImagePreviewPage), findsNothing);
      expect(
        find.text('This file is no longer stored on your phone.'),
        findsOneWidget,
      );
    });

    testWidgets('shows incoming transfer prompt and handles Accept and Decline',
        (tester) async {
      final incomingOffer = FileOffer(
        transferId: 'in-1',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-1',
            fileName: 'report.pdf',
            size: 2048 * 1024,
            fileType: 'application/pdf',
          ),
          OfferedFile(
            fileId: 'f-2',
            fileName: 'notes.txt',
            size: 512,
            fileType: 'text/plain',
          ),
        ],
      );

      final pending = PendingIncomingTransfer(
        transferId: 'in-1',
        peerId: const DeviceId('desktop-1'),
        peerName: 'Work Mac',
        offer: incomingOffer,
        isFirstTransferFromDevice: true,
        destinationPath: '/sdcard/Download/RemoteLink',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            identityProvider.overrideWith(
              (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
            ),
            // The screen sends to the connected computer and only that one,
            // so this is the seam that decides whether Send is live.
            // Overridden directly rather than by faking a session: the
            // provider it reads needs an established `Session`, which cannot
            // be built in a widget test without a socket.
            transferTargetProvider.overrideWithValue(
              (id: const DeviceId('desktop-1'), name: 'Work Mac'),
            ),
            clientStateProvider.overrideWith(
              (ref) => Stream<ClientState>.value(ClientState.connected),
            ),
            transferControllerProvider.overrideWith((ref) {
              final controller = MobileTransferController(
                ref,
                customTransferStore: MobileTransferStore(Directory.systemTemp),
              );
              controller.state = TransferState(
                pendingIncoming: pending,
              );
              return controller;
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: TransferScreen())),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Incoming transfer from Work Mac'), findsWidgets);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('Accept'), findsWidgets);
      expect(find.text('Decline'), findsWidgets);
      expect(
        find.textContaining('First transfer'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// Captures what was exported instead of opening a share sheet.
///
/// The real exporter puts a file in the photo library or in front of the user,
/// neither of which a test can do — so this stands in, and reads the bytes
/// before commit() deletes them, which is the only moment they exist.
final class _RecordingExporter implements IncomingFileExporter {
  _RecordingExporter({this.throws});

  /// Typed rather than `Object?`, so the throw below is one the analyzer can
  /// see is an exception.
  final ExportError? throws;
  final List<({String mimeType, List<int> bytes})> exported =
      <({String mimeType, List<int> bytes})>[];

  @override
  Future<void> export(File file, {required String mimeType}) async {
    exported.add((mimeType: mimeType, bytes: await file.readAsBytes()));
    if (throws case final error?) throw error;
  }
}

/// A one-pixel PNG, so the preview has something real to decode.
const String _kOnePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGMAAQAABQABDQott'
    'AAAAABJRU5ErkJggg==';
