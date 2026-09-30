import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';
import 'package:remotelink_desktop/src/domain/transfer_model.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import 'support/fakes.dart';

void main() {
  group('Desktop Transfer Models & Utilities', () {
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
      tracker.record(1024 * 1024, now: t1); // 1 MB in 1 second

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

    test('FileBackedOutgoingFile reads slices accurately', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('file_backed_test_');
      final tempFile = File('${tempDir.path}/test.bin');
      await tempFile.writeAsBytes(<int>[10, 20, 30, 40, 50]);

      try {
        final outgoing = FileBackedOutgoingFile(tempFile, 5);
        expect(outgoing.size, 5);

        final slice = await outgoing.read(1, 3);
        expect(slice, <int>[20, 30, 40]);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('retry is offered only for outgoing recoverable transfers', () {
      // The desktop was missing the direction check the phone has had all
      // along, so a photo cancelled on its way in from a phone grew a Retry
      // button that could only throw.
      TransferRecord record(TransferDirection direction) => TransferRecord(
            transferId: 'retry-1',
            peerId: const DeviceId('phone-1'),
            peerName: 'Pixel 8 Pro',
            direction: direction,
            status: TransferStatus.cancelled,
            files: const <TransferFileProgress>[],
            totalBytes: 0,
            transferredBytes: 0,
            createdAt: DateTime(2026),
          );

      expect(record(TransferDirection.outgoing).canRetry, isTrue);
      expect(record(TransferDirection.incoming).canRetry, isFalse);
    });

    test('terminal rows can be removed and retry clears the old error', () {
      final record = TransferRecord(
        transferId: 'failed-1',
        peerId: const DeviceId('phone-1'),
        peerName: 'Pixel 8 Pro',
        direction: TransferDirection.outgoing,
        status: TransferStatus.failed,
        files: const <TransferFileProgress>[],
        totalBytes: 0,
        transferredBytes: 0,
        createdAt: DateTime(2026),
        failure: TransferFailure.connectionLost,
      );
      expect(record.canRemove, isTrue);
      expect(
          record
              .copyWith(status: TransferStatus.offered, clearFailure: true)
              .failure,
          isNull);
      expect(record.copyWith(status: TransferStatus.inProgress).canRemove,
          isFalse);
    });
  });

  test('abort, disk failure and disconnect end rows; terminal rows remove',
      () async {
    final pair = await _createRealServerClientPair();
    final store = _BlockingTransferStore();
    final service = DesktopService(
      identity: await DeviceIdentity.generate(),
      trustStore: pair.trustStore,
      deviceName: 'Test Computer',
      appVersion: '0.1.0',
      clock: SystemClock(),
      incomingTransferStore: store,
      input: const UnsupportedInputBackend('test'),
      clipboardBackend: const UnsupportedClipboardBackend(),
      media: const UnsupportedMediaBackend(),
      brightness: const UnsupportedBrightnessBackend('test'),
      systemInfo: const UnsupportedSystemInfoBackend('test'),
      networkAdapters: const UnsupportedNetworkAdapterBackend('test'),
      screenCapture: const UnsupportedScreenCaptureBackend('test'),
    );
    try {
      await service.registerSessionForTesting(pair.session);
      FileOffer offer(String id) => FileOffer(
            transferId: id,
            files: <OfferedFile>[
              OfferedFile(
                  fileId: 'photo',
                  fileName: 'photo.jpg',
                  size: 10,
                  fileType: 'image/jpeg'),
            ],
          );

      await service.handleMessageForTesting(pair.session, offer('cancelled'));
      await Future<void>.delayed(Duration.zero);
      expect(service.transfers.single.status, TransferStatus.prompting);
      await service.handleMessageForTesting(
        pair.session,
        const FileAbort(
          transferId: 'cancelled',
          reason: FileAbortReason.cancelled,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(service.transfers.single.status, TransferStatus.cancelled);
      expect(service.transfers.single.failure, TransferFailure.cancelledByPeer);
      expect(service.removeTransfer('cancelled'), isTrue);
      expect(service.transfers, isEmpty);

      await service.handleMessageForTesting(pair.session, offer('local'));
      await Future<void>.delayed(Duration.zero);
      expect(service.removeTransfer('local'), isFalse);
      await service.cancelTransfer('local');
      expect(service.transfers.single.status, TransferStatus.cancelled);
      expect(service.transfers.single.failure, TransferFailure.cancelledByYou);
      expect(service.removeTransfer('local'), isTrue);

      await service.handleMessageForTesting(pair.session, offer('blocked'));
      await Future<void>.delayed(Duration.zero);
      final pending = PendingIncomingTransfer(
        transferId: 'blocked',
        peerId: pair.session.peerId,
        peerName: 'Pixel 8 Pro',
        offer: offer('blocked'),
        isFirstTransferFromDevice: false,
        destinationPath: '',
      );
      final accepting = service.approveIncomingTransfer(pending);
      await store.entered.future.timeout(const Duration(seconds: 2));
      await service.handleMessageForTesting(
          pair.session,
          const FileAbort(
            transferId: 'blocked',
            reason: FileAbortReason.cancelled,
          ));
      await Future<void>.delayed(Duration.zero);
      expect(service.transfers.single.status, TransferStatus.cancelled,
          reason: 'queued storage cleanup must not hold the UI row open');
      store.release.complete();
      await accepting;
      expect(service.removeTransfer('blocked'), isTrue);

      final brokenOffer = offer('broken');
      await service.handleMessageForTesting(pair.session, brokenOffer);
      await Future<void>.delayed(Duration.zero);
      final acceptance = pair.client.messages.firstWhere(
        (message) => message is FileAccept && message.transferId == 'broken',
      );
      await service.approveIncomingTransfer(PendingIncomingTransfer(
        transferId: 'broken',
        peerId: pair.session.peerId,
        peerName: 'Pixel 8 Pro',
        offer: brokenOffer,
        isFirstTransferFromDevice: false,
        destinationPath: '',
      ));
      final accepted = await acceptance.timeout(const Duration(seconds: 2));
      final remoteAbort = pair.client.messages.firstWhere(
        (message) => message is FileAbort && message.transferId == 'broken',
      );
      await FileTransferSender(
        exporterSecret: pair.session.session.exporterSecret,
      ).sendAccepted(
        offer: brokenOffer,
        accept: accepted as FileAccept,
        sources: <String, OutgoingFile>{
          'photo': MemoryOutgoingFile(Uint8List(10)),
        },
        sendChunk: (chunk) =>
            service.handleMessageForTesting(pair.session, chunk),
        sendComplete: (_) async {},
      );
      expect(
          (await remoteAbort.timeout(const Duration(seconds: 2)) as FileAbort)
              .reason,
          FileAbortReason.ioError);
      expect(service.transfers.single.status, TransferStatus.failed);
      expect(service.removeTransfer('broken'), isTrue);

      final goodOffer = offer('good');
      await service.handleMessageForTesting(pair.session, goodOffer);
      await Future<void>.delayed(Duration.zero);
      final goodAcceptance = pair.client.messages.firstWhere(
        (message) => message is FileAccept && message.transferId == 'good',
      );
      await service.approveIncomingTransfer(PendingIncomingTransfer(
        transferId: 'good',
        peerId: pair.session.peerId,
        peerName: 'Pixel 8 Pro',
        offer: goodOffer,
        isFirstTransferFromDevice: false,
        destinationPath: '',
      ));
      final confirmation = pair.client.messages.firstWhere(
        (message) => message is FileComplete && message.transferId == 'good',
      );
      await FileTransferSender(
        exporterSecret: pair.session.session.exporterSecret,
      ).sendAccepted(
        offer: goodOffer,
        accept: await goodAcceptance as FileAccept,
        sources: <String, OutgoingFile>{
          'photo': MemoryOutgoingFile(Uint8List(10)),
        },
        sendChunk: (chunk) =>
            service.handleMessageForTesting(pair.session, chunk),
        sendComplete: (complete) =>
            service.handleMessageForTesting(pair.session, complete),
      );
      expect(await confirmation.timeout(const Duration(seconds: 2)),
          isA<FileComplete>());
      expect(service.transfers.single.status, TransferStatus.completed);
      expect(service.removeTransfer('good'), isTrue);

      await service.handleMessageForTesting(pair.session, offer('lost'));
      await Future<void>.delayed(Duration.zero);
      await service.endSessionForTesting(pair.session);
      expect(service.transfers.single.status, TransferStatus.failed);
      expect(service.transfers.single.failure, TransferFailure.connectionLost);
      expect(service.removeTransfer('lost'), isTrue);
    } finally {
      await pair.client.disconnect();
      await pair.server.stop();
      await service.stop();
    }
  });

  group('Desktop HomeScreen Widget Tests', () {
    testWidgets('renders send card empty state when no device is connected',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: desktopHomeOverrides,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Send to device'), findsOneWidget);
      expect(
          find.text('Connect a device to send files or text.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders send card with target device, inputs, and drag & drop',
        (tester) async {
      late RemoteLinkServer server;
      late RemoteLinkClient client;
      late ConnectedDevice device;

      await tester.runAsync(() async {
        final pair = await _createRealServerClientPair();
        server = pair.server;
        client = pair.client;
        device = ConnectedDevice(
          serverSession: pair.session,
          tier: PermissionTier.extended,
          name: 'Pixel 8 Pro',
        );
      });

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              ...desktopHomeOverrides,
              connectedDevicesProvider.overrideWith(
                (ref) => Stream<List<ConnectedDevice>>.value(
                    <ConnectedDevice>[device]),
              ),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        await tester.pump();
        await tester.pump();

        expect(find.text('Send to device'), findsOneWidget);
        expect(find.text('File / Drag & Drop'), findsOneWidget);
        expect(find.text('Text / URL'), findsOneWidget);
        expect(find.text('Drag and drop files here to send'), findsOneWidget);
        expect(find.text('Send File'), findsOneWidget);

        // Switch to text mode
        await tester.tap(find.text('Text / URL'));
        await tester.pumpAndSettle();
        expect(find.text('Text or URL snippet'), findsOneWidget);
        expect(find.text('Send Text'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.runAsync(() async {
          await client.disconnect();
          await server.stop();
        });
      }
    });

    testWidgets('survives the selected device disconnecting', (tester) async {
      // The crash this exists for: `DropdownButtonFormField` asserts when its
      // value names no item, and the selected id was only ever set when it was
      // null — so a phone that dropped off the network left a dangling
      // selection. The assert took out the entire send card, and with it the
      // transfers list and clipboard panel below it, so the report was "the
      // desktop is broken" rather than "the dropdown is stale".
      late RemoteLinkServer serverA;
      late RemoteLinkClient clientA;
      late ConnectedDevice deviceA;
      late RemoteLinkServer serverB;
      late RemoteLinkClient clientB;
      late ConnectedDevice deviceB;

      final devices = StreamController<List<ConnectedDevice>>.broadcast();
      addTearDown(devices.close);

      // Two genuinely different peers, because that is the case that breaks:
      // the same device reconnecting keeps the id valid, so a test that reuses
      // one passes against the bug. The report showed a dropdown holding
      // 889ECP… while the only connected device was R6J8T….
      await tester.runAsync(() async {
        final pairA = await _createRealServerClientPair();
        serverA = pairA.server;
        clientA = pairA.client;
        deviceA = ConnectedDevice(
          serverSession: pairA.session,
          tier: PermissionTier.extended,
          name: 'Pixel 8 Pro',
        );

        final pairB = await _createRealServerClientPair();
        serverB = pairB.server;
        clientB = pairB.client;
        deviceB = ConnectedDevice(
          serverSession: pairB.session,
          tier: PermissionTier.extended,
          name: 'iPhone 17',
        );
      });

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: <Override>[
              ...desktopHomeOverrides,
              connectedDevicesProvider.overrideWith((ref) => devices.stream),
            ],
            child: const MaterialApp(home: HomeScreen()),
          ),
        );

        // A pump before the first event: the provider subscribes to the stream
        // asynchronously, and a broadcast controller drops anything added
        // before that happens.
        // A pump before the first event: the provider subscribes to the stream
        // asynchronously, and a broadcast controller drops anything added
        // before that happens.
        await tester.pump();
        devices.add(<ConnectedDevice>[deviceA]);
        await tester.pump();
        await tester.pump();
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

        // The first phone goes away and a different one takes its place, in a
        // single update — no empty list in between to reset the selection.
        devices.add(<ConnectedDevice>[deviceB]);
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        expect(find.text('Send File'), findsOneWidget);

        // And the list emptying entirely still leaves a usable card.
        devices.add(const <ConnectedDevice>[]);
        await tester.pump();
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(
          find.text('Connect a device to send files or text.'),
          findsOneWidget,
        );
      } finally {
        await tester.runAsync(() async {
          await clientA.disconnect();
          await serverA.stop();
          await clientB.disconnect();
          await serverB.stop();
        });
      }
    });

    testWidgets('offers a way to grant Screen Recording when it is missing',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            screenCaptureAvailabilityProvider.overrideWith(
              (ref) => Stream<({bool available, BackendFailure? reason})>.value(
                (
                  available: false,
                  reason: BackendFailure.screenRecordingPermission,
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      // Without this the only trace of a missing grant was a log line, and the
      // phone's screen-share button silently never appeared.
      //
      // Written against the release switch rather than against `false`, so that
      // flipping `kScreenSharingShipped` back on restores the assertion instead
      // of leaving a test that quietly proves nothing.
      expect(
        find.textContaining('Screen Recording permission'),
        kScreenSharingShipped ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Open Settings'),
        kScreenSharingShipped ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('says where screen sharing lives once it is available',
        (tester) async {
      // With the permission granted the desktop previously said nothing at all
      // about screen sharing: no button, because the phone starts it, and no
      // banner, because the banner is for the missing-permission case. Someone
      // looking here for it found an empty window.
      await tester.pumpWidget(
        ProviderScope(
          overrides: desktopHomeOverrides,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('start it from the phone'),
        kScreenSharingShipped ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('says nothing about sharing when it cannot share',
        (tester) async {
      // The banner is the message in this case, and two messages about the
      // same thing is one too many.
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            screenCaptureAvailabilityProvider.overrideWith(
              (ref) => Stream<({bool available, BackendFailure? reason})>.value(
                (
                  available: false,
                  reason: BackendFailure.screenRecordingPermission
                ),
              ),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.textContaining('start it from the phone'), findsNothing);
      expect(
        find.textContaining('Screen Recording permission'),
        kScreenSharingShipped ? findsOneWidget : findsNothing,
      );
    });

    testWidgets(
        'renders active and recent transfers list with progress and controls',
        (tester) async {
      final inProgressRecord = TransferRecord(
        transferId: 't-desktop-1',
        peerId: const DeviceId('phone-1'),
        peerName: 'Pixel 8 Pro',
        direction: TransferDirection.outgoing,
        status: TransferStatus.inProgress,
        files: const <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'file-1',
            fileName: 'archive.tar.gz',
            totalBytes: 50 * 1024 * 1024,
            transferredBytes: 25 * 1024 * 1024,
          ),
        ],
        totalBytes: 50 * 1024 * 1024,
        transferredBytes: 25 * 1024 * 1024,
        speedBytesPerSecond: 5 * 1024 * 1024,
        eta: const Duration(seconds: 5),
        createdAt: DateTime.now(),
      );

      final failedRecord = TransferRecord(
        transferId: 't-desktop-2',
        peerId: const DeviceId('phone-1'),
        peerName: 'Pixel 8 Pro',
        direction: TransferDirection.incoming,
        status: TransferStatus.failed,
        files: const <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'file-2',
            fileName: 'image.png',
            totalBytes: 1024 * 1024,
            transferredBytes: 512 * 1024,
          ),
        ],
        totalBytes: 1024 * 1024,
        transferredBytes: 512 * 1024,
        failure: TransferFailure.timedOut,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            transfersProvider.overrideWith(
              (ref) => Stream<List<TransferRecord>>.value(<TransferRecord>[
                inProgressRecord,
                failedRecord,
              ]),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Transfers'), findsOneWidget);
      expect(find.text('To Pixel 8 Pro'), findsOneWidget);
      expect(find.text('archive.tar.gz'), findsOneWidget);
      expect(find.text('Transferring'), findsOneWidget);
      expect(find.text('·  5.0 MB/s'), findsOneWidget);
      expect(find.text('·  ETA: 5s'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);

      expect(find.text('From Pixel 8 Pro'), findsOneWidget);
      expect(find.text('image.png'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Transfer timed out'), findsOneWidget);
      // Not on an incoming transfer, and this assertion used to say the
      // opposite. Retrying re-sends the offer, and the offer belongs to
      // whichever side chose the files — so on a file arriving from the phone
      // the button had nothing behind it but a `StateError`.
      expect(find.text('Retry'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a transfer waiting on this computer says so', (tester) async {
      // "Awaiting response" on a file arriving from a phone describes the
      // phone, which is not what is waiting — and sent the user looking for
      // something to press on the wrong device.
      final incoming = TransferRecord(
        transferId: 't-prompting',
        peerId: const DeviceId('phone-1'),
        peerName: 'Pixel 8 Pro',
        direction: TransferDirection.incoming,
        status: TransferStatus.prompting,
        files: const <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'file-1',
            fileName: 'holiday.jpg',
            totalBytes: 1024,
            transferredBytes: 0,
          ),
        ],
        totalBytes: 1024,
        transferredBytes: 0,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            transfersProvider.overrideWith(
              (ref) => Stream<List<TransferRecord>>.value(
                <TransferRecord>[incoming],
              ),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      expect(find.text('Waiting for you'), findsOneWidget);
      expect(find.text('Awaiting response'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows incoming transfer dialog with details and buttons',
        (tester) async {
      final incomingOffer = FileOffer(
        transferId: 'offer-1',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'f-1',
            fileName: 'dataset.csv',
            size: 4096 * 1024,
            fileType: 'text/csv',
          ),
          OfferedFile(
            fileId: 'f-2',
            fileName: 'summary.txt',
            size: 1024,
            fileType: 'text/plain',
          ),
        ],
      );

      final pending = PendingIncomingTransfer(
        transferId: 'offer-1',
        peerId: const DeviceId('phone-1'),
        peerName: 'Pixel 8 Pro',
        offer: incomingOffer,
        isFirstTransferFromDevice: true,
        destinationPath: '/Users/test/Downloads/RemoteLink',
      );

      final incomingController =
          StreamController<PendingIncomingTransfer>.broadcast();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            incomingTransferRequestProvider.overrideWith(
              (ref) => incomingController.stream,
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      incomingController.add(pending);
      await tester.pumpAndSettle();

      expect(find.text('Incoming transfer from Pixel 8 Pro'), findsOneWidget);
      expect(find.text('dataset.csv'), findsOneWidget);
      expect(find.text('summary.txt'), findsOneWidget);
      expect(find.text('4.0 MB'), findsWidgets);
      expect(find.text('1.0 KB'), findsWidgets);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(
        find.textContaining('First transfer from this device'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await incomingController.close();
    });
  });
}

/// Holds one acceptance open and makes another file fail during a chunk write.
final class _BlockingTransferStore implements IncomingTransferStore {
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<Map<String, IncomingFile>> prepare(FileOffer offer,
      {required String namespace}) async {
    if (offer.transferId == 'blocked') {
      entered.complete();
      await release.future;
    }
    if (offer.transferId == 'broken') {
      return <String, IncomingFile>{
        'photo': _ThrowingIncomingFile(offer.files.single),
      };
    }
    if (offer.transferId == 'good') {
      return <String, IncomingFile>{
        'photo': _MemoryIncomingFile(offer.files.single),
      };
    }
    return <String, IncomingFile>{};
  }
}

final class _MemoryIncomingFile implements IncomingFile {
  _MemoryIncomingFile(this.offer) : _bytes = Uint8List(offer.size);

  @override
  final OfferedFile offer;
  final Uint8List _bytes;
  final List<ReceivedRange> _ranges = <ReceivedRange>[];

  @override
  List<ReceivedRange> get receivedRanges => _ranges;

  @override
  Future<void> write(int offset, Uint8List bytes) async {
    _bytes.setRange(offset, offset + bytes.length, bytes);
    _ranges.add(ReceivedRange(offset, offset + bytes.length));
  }

  @override
  Stream<List<int>> read() => Stream<List<int>>.value(_bytes);

  @override
  Future<void> commit() async {}

  @override
  Future<void> delete() async {}
}

final class _ThrowingIncomingFile implements IncomingFile {
  _ThrowingIncomingFile(this.offer);

  @override
  final OfferedFile offer;

  @override
  List<ReceivedRange> get receivedRanges => const <ReceivedRange>[];

  @override
  Future<void> write(int offset, Uint8List bytes) async {
    throw const FileSystemException('Disk write failed');
  }

  @override
  Stream<List<int>> read() async* {}

  @override
  Future<void> commit() async {}

  @override
  Future<void> delete() async {}
}

Future<
    ({
      RemoteLinkServer server,
      RemoteLinkClient client,
      ServerSession session,
      InMemoryTrustStore trustStore
    })> _createRealServerClientPair() async {
  final phoneIdentity = await DeviceIdentity.generate();
  final desktopIdentity = await DeviceIdentity.generate();
  final desktopTrust = InMemoryTrustStore();
  await desktopTrust.upsert(
    TrustedPeer(
      id: phoneIdentity.id,
      publicKey: phoneIdentity.publicKey,
      name: 'Pixel 8 Pro',
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

  unawaited(
    client.connect(
      ConnectionTarget(
        host: '127.0.0.1',
        port: server.boundPort,
        serverPublicKey: desktopIdentity.publicKey,
      ),
    ),
  );

  final session = await server.accepted.first;
  return (
    server: server,
    client: client,
    session: session,
    trustStore: desktopTrust
  );
}
