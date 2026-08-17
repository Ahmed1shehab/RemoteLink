import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
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
  });

  group('MobileTransferStore', () {
    late Directory tempDir;
    late MobileTransferStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mobile_store_test_');
      store = MobileTransferStore(tempDir);
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
      final destination = File('${tempDir.path}/test.bin');
      expect(destination.existsSync(), isTrue);
      expect(await destination.readAsBytes(), <int>[1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });

  group('TransferScreen Widget Tests', () {
    testWidgets('renders targets and lets user switch input modes',
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
      expect(find.text('Text / URL'), findsOneWidget);
      expect(find.text('File'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.text('Send Text'), findsOneWidget);

      // Switch to File mode. This used to assert a "File path" text field, in
      // which the user was expected to type an absolute path by hand — the
      // screen offers a picker now, and the field is gone.
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      expect(find.text('Choose files'), findsOneWidget);
      expect(find.text('Send File'), findsOneWidget);

      // Switch to Photo mode
      await tester.tap(find.text('Photo'));
      await tester.pumpAndSettle();
      expect(find.text('Choose photos'), findsOneWidget);
      expect(find.text('Send Photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
      expect(find.text('Cancel'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
