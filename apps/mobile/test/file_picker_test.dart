import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/transfer/file_picker.dart';
import 'package:remotelink_mobile/src/features/transfer/mobile_transfer_store.dart';
import 'package:remotelink_mobile/src/features/transfer/transfer_controller.dart';
import 'package:remotelink_mobile/src/features/transfer/transfer_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// Returns whatever it was told to, and records that it was asked.
///
/// The real picker cannot run here at all: `file_selector` and `image_picker`
/// are platform channels with no Dart fallback, so calling them in a widget
/// test throws `MissingPluginException`. That is the reason [TransferFilePicker]
/// exists as an interface — without it there is no way to test the send flow
/// short of an integration test on a real device.
final class _FakePicker implements TransferFilePicker {
  _FakePicker({
    this.files = const <PickedFile>[],
    List<PickedFile>? media,
    List<PickedFile>? images,
  }) : media = media ?? images;

  final List<PickedFile> files;
  final List<PickedFile>? media;

  int fileCalls = 0;
  int mediaCalls = 0;

  @override
  Future<List<PickedFile>> pickFiles() async {
    fileCalls++;
    return files;
  }

  @override
  Future<List<PickedFile>> pickMedia() async {
    mediaCalls++;
    return media ?? files;
  }
}

/// Fails every call, the way a picker does when the OS refuses to open it.
final class _ThrowingPicker implements TransferFilePicker {
  @override
  Future<List<PickedFile>> pickFiles() async =>
      throw StateError('no activity to handle the intent');

  @override
  Future<List<PickedFile>> pickMedia() async =>
      throw StateError('no activity to handle the intent');
}

/// Captures what the screen passed to [sendFiles] instead of sending it.
///
/// The real method needs an established session and would throw before
/// recording anything, which would test the guard rather than the arguments.
final class _RecordingController extends MobileTransferController {
  _RecordingController(super.ref, {super.customTransferStore});

  List<File>? sentFiles;
  List<String>? sentNames;

  @override
  Future<String> sendFiles({
    required DeviceId targetPeerId,
    required String targetPeerName,
    required List<File> files,
    List<String>? fileNames,
  }) async {
    sentFiles = files;
    sentNames = fileNames;
    return 't-test';
  }
}

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('rl_picker_test'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// A real file on disk with [name] as the name the user would recognise.
  PickedFile makePicked(String name, {String contents = 'payload'}) {
    // A distinct on-disk name from the display name, because that is the case
    // that matters: Android hands back a cache copy called something else
    // entirely, and the desktop used to receive the cache name.
    final file = File('${tempDir.path}/cache_${name.hashCode}.tmp')
      ..writeAsStringSync(contents);
    return PickedFile(file: file, displayName: name);
  }

  Widget harness({
    required TransferFilePicker picker,
    required _RecordingController Function(Ref) controller,
  }) =>
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(ClientState.connected),
          ),
          trustedPeersProvider.overrideWith(
            (ref) async => <TrustedPeer>[
              TrustedPeer(
                id: const DeviceId('desktop-1'),
                publicKey: Uint8List(32),
                name: 'Work Mac',
                platform: PlatformKind.macos,
                pairedAt: DateTime.utc(2026),
                permissionTier: PermissionTier.extended.index,
              ),
            ],
          ),
          transferFilePickerProvider.overrideWithValue(picker),
          transferControllerProvider.overrideWith(controller),
        ],
        child: const MaterialApp(home: Scaffold(body: TransferScreen())),
      );

  /// Switches the send card to the File tab and lets the frame settle.
  Future<void> openFileTab(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
  }

  group('choosing files', () {
    testWidgets('the chosen files are listed by the name the user knows',
        (tester) async {
      final picker = _FakePicker(
        files: <PickedFile>[
          makePicked('Quarterly report.pdf'),
          makePicked('budget.xlsx'),
        ],
      );

      await tester.pumpWidget(
        harness(
          picker: picker,
          controller: (ref) => _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      expect(find.text('Choose files'), findsOneWidget);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();

      expect(picker.fileCalls, 1);
      expect(find.text('Quarterly report.pdf'), findsOneWidget);
      expect(find.text('budget.xlsx'), findsOneWidget);
      // Not the cache path the picker actually handed back.
      expect(find.textContaining('cache_'), findsNothing);
    });

    testWidgets('Send stays disabled until something is chosen',
        (tester) async {
      final picker = _FakePicker(files: <PickedFile>[makePicked('a.txt')]);

      await tester.pumpWidget(
        harness(
          picker: picker,
          controller: (ref) => _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      FilledButton sendButton() => tester.widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Send File'),
          );

      expect(sendButton().onPressed, isNull);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send 1 File'),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a second pick adds to the selection rather than replacing it',
        (tester) async {
      // Same instance returns the same file twice, which also covers the
      // duplicate guard: choosing one file twice must not offer it twice.
      final first = makePicked('first.txt');
      final second = makePicked('second.txt');
      var call = 0;
      final picker = _SequencePicker(() {
        call++;
        return call == 1 ? <PickedFile>[first] : <PickedFile>[first, second];
      });

      await tester.pumpWidget(
        harness(
          picker: picker,
          controller: (ref) => _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add more files'));
      await tester.pumpAndSettle();

      expect(find.text('first.txt'), findsOneWidget);
      expect(find.text('second.txt'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Send 2 Files'),
        findsOneWidget,
      );
    });

    testWidgets('cancelling leaves the selection and the button untouched',
        (tester) async {
      // An empty list is how every picker in this app reports a cancel.
      final picker = _FakePicker();

      await tester.pumpWidget(
        harness(
          picker: picker,
          controller: (ref) => _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();

      expect(picker.fileCalls, 1);
      expect(find.text('Choose files'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Send File'),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('a picker that fails says so instead of failing silently',
        (tester) async {
      await tester.pumpWidget(
        harness(
          picker: _ThrowingPicker(),
          controller: (ref) => _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not open the picker'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Media tab asks for media (photos and videos), not files',
        (tester) async {
      final picker = _FakePicker(
        media: <PickedFile>[
          makePicked('IMG_4021.HEIC'),
          makePicked('vacation_clip.mp4'),
        ],
      );

      await tester.pumpWidget(
        harness(
          picker: picker,
          controller: (ref) => _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Media'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose media'));
      await tester.pumpAndSettle();

      expect(picker.mediaCalls, 1);
      expect(picker.fileCalls, 0);
      expect(find.text('IMG_4021.HEIC'), findsOneWidget);
      expect(find.text('vacation_clip.mp4'), findsOneWidget);
    });
  });

  group('sending what was chosen', () {
    testWidgets('the picked files and their display names reach the controller',
        (tester) async {
      final picked = <PickedFile>[
        makePicked('Quarterly report.pdf'),
        makePicked('budget.xlsx'),
      ];
      late _RecordingController recorded;

      await tester.pumpWidget(
        harness(
          picker: _FakePicker(files: picked),
          controller: (ref) => recorded = _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send 2 Files'));
      await tester.pumpAndSettle();

      expect(
        recorded.sentFiles?.map((f) => f.path),
        <String>[picked[0].file.path, picked[1].file.path],
      );
      expect(
        recorded.sentNames,
        <String>['Quarterly report.pdf', 'budget.xlsx'],
      );
    });

    testWidgets(
        'choosing a video through the Media tab sends video to the controller',
        (tester) async {
      final video = makePicked('vacation_clip.mp4');
      final picker = _FakePicker(media: <PickedFile>[video]);
      late _RecordingController recorded;

      await tester.pumpWidget(
        harness(
          picker: picker,
          controller: (ref) => recorded = _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Media'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose media'));
      await tester.pumpAndSettle();

      expect(find.text('vacation_clip.mp4'), findsOneWidget);
      await tester.tap(find.text('Send 1 Item'));
      await tester.pumpAndSettle();

      expect(recorded.sentNames, <String>['vacation_clip.mp4']);
    });

    testWidgets('a file that vanished before Send is reported, not sent',
        (tester) async {
      // The Android case this exists for: the picker's cache copy is evicted
      // between choosing the file and pressing Send.
      final vanishing = makePicked('gone.txt');
      late _RecordingController recorded;

      await tester.pumpWidget(
        harness(
          picker: _FakePicker(files: <PickedFile>[vanishing]),
          controller: (ref) => recorded = _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();

      vanishing.file.deleteSync();

      await tester.tap(find.text('Send 1 File'));
      await tester.pumpAndSettle();

      expect(recorded.sentFiles, isNull);
      expect(find.textContaining('no longer available'), findsOneWidget);
    });

    testWidgets('the selection clears once it has been sent', (tester) async {
      await tester.pumpWidget(
        harness(
          picker: _FakePicker(files: <PickedFile>[makePicked('once.txt')]),
          controller: (ref) => _RecordingController(
            ref,
            customTransferStore: MobileTransferStore(tempDir),
          ),
        ),
      );
      await openFileTab(tester);

      await tester.tap(find.text('Choose files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send 1 File'));
      await tester.pumpAndSettle();

      expect(find.text('once.txt'), findsNothing);
      expect(find.text('Choose files'), findsOneWidget);
    });
  });

  group('naming what goes on the wire', () {
    test('the display name is preferred over the path', () {
      expect(
        safeOutgoingFileName(
          <String?>['Quarterly report.pdf', 'cache_9182.tmp'],
          fallback: 'file_1.dat',
        ),
        'Quarterly report.pdf',
      );
    });

    test('a rejected display name falls back to the path, not to failure', () {
      // A trailing space is refused outright by sanitiseFileName, because a
      // file named that way cannot be created on Windows. It is also something
      // a filesystem elsewhere will happily produce, and it must not cost the
      // user their transfer.
      expect(
        safeOutgoingFileName(
          <String?>['holiday photo.jpg ', 'IMG_4021.HEIC'],
          fallback: 'file_1.dat',
        ),
        'IMG_4021.HEIC',
      );
    });

    test('a traversal attempt in the display name is never used', () {
      expect(
        safeOutgoingFileName(
          <String?>['../../etc/passwd', 'safe.txt'],
          fallback: 'file_1.dat',
        ),
        'safe.txt',
      );
    });

    test('the fallback is reached when every candidate is refused', () {
      expect(
        safeOutgoingFileName(
          <String?>['../evil', 'C:\\Windows\\system32', 'NUL'],
          fallback: 'file_3.dat',
        ),
        'file_3.dat',
      );
    });

    test('a null candidate is skipped rather than treated as a name', () {
      expect(
        safeOutgoingFileName(
          <String?>[null, 'notes.txt'],
          fallback: 'file_1.dat',
        ),
        'notes.txt',
      );
    });
  });
}

/// Returns a different list on each call.
final class _SequencePicker implements TransferFilePicker {
  _SequencePicker(this._next);

  final List<PickedFile> Function() _next;

  @override
  Future<List<PickedFile>> pickFiles() async => _next();

  @override
  Future<List<PickedFile>> pickMedia() async => _next();
}
