import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/transfer_model.dart';
import 'package:remotelink_desktop/src/ui/home_screen.dart';
import 'package:rl_core/rl_core.dart';

import 'support/fakes.dart';
import 'support/semantics.dart';

void main() {
  group('Display Path Formatting', () {
    test('replaces home directory with ~ on macOS and Linux', () {
      final formatted = formatDisplayPath(
        '/Users/alice/Downloads/RemoteLink/photo.jpg',
        homeDir: '/Users/alice',
        isWindows: false,
      );
      expect(formatted, '~/Downloads/RemoteLink/photo.jpg');
    });

    test('handles trailing slashes on home directory gracefully', () {
      final formatted = formatDisplayPath(
        '/home/bob/Downloads/RemoteLink/document.pdf',
        homeDir: '/home/bob/',
        isWindows: false,
      );
      expect(formatted, '~/Downloads/RemoteLink/document.pdf');
    });

    test('preserves real path verbatim on Windows without tilde replacement',
        () {
      const winPath = r'C:\Users\carol\Downloads\RemoteLink\archive.zip';
      final formatted = formatDisplayPath(
        winPath,
        homeDir: r'C:\Users\carol',
        isWindows: true,
      );
      expect(formatted, winPath);
    });

    test('leaves non-home paths intact on Unix platforms', () {
      final formatted = formatDisplayPath(
        '/var/tmp/shared/file.txt',
        homeDir: '/Users/alice',
        isWindows: false,
      );
      expect(formatted, '/var/tmp/shared/file.txt');
    });

    test(
        'elides middle directories for very long paths so folder and file remain clear',
        () {
      const longPath =
          '~/Documents/projects/unified_link/nested/subfolder/deep/folder/photo.jpg';
      final formatted = formatDisplayPath(
        longPath,
        homeDir: '/Users/alice',
        isWindows: false,
        maxPathLength: 45,
      );

      // The root and the leaf directory/file are preserved, middle replaced with ellipsis.
      expect(formatted.contains('...'), isTrue);
      expect(formatted.startsWith('~/Documents/'), isTrue);
      expect(formatted.endsWith('folder/photo.jpg'), isTrue);
      expect(formatted.length, lessThanOrEqualTo(45));
    });
  });

  group('SavedFileInfo Widget', () {
    testWidgets('renders file name and formatted path', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedFileInfo(
              fileName: 'photo.jpg',
              path: '/Users/test/Downloads/RemoteLink/photo.jpg',
              homeDirForTesting: '/Users/test',
              isWindowsForTesting: false,
              onOpenFile: (p) async => true,
              onRevealFile: (p) async => true,
            ),
          ),
        ),
      );

      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('~/Downloads/RemoteLink/photo.jpg'), findsOneWidget);
    });

    testWidgets('tapping file name calls onOpenFile', (tester) async {
      String? openedPath;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedFileInfo(
              fileName: 'report.pdf',
              path: '/Users/test/Downloads/RemoteLink/report.pdf',
              homeDirForTesting: '/Users/test',
              isWindowsForTesting: false,
              onOpenFile: (p) async {
                openedPath = p;
                return true;
              },
              onRevealFile: (p) async => true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('report.pdf'));
      await tester.pump();

      expect(openedPath, '/Users/test/Downloads/RemoteLink/report.pdf');
    });

    testWidgets('tapping saved path calls onRevealFile', (tester) async {
      String? revealedPath;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedFileInfo(
              fileName: 'data.csv',
              path: '/Users/test/Downloads/RemoteLink/data.csv',
              homeDirForTesting: '/Users/test',
              isWindowsForTesting: false,
              onOpenFile: (p) async => true,
              onRevealFile: (p) async {
                revealedPath = p;
                return true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('~/Downloads/RemoteLink/data.csv'));
      await tester.pump();

      expect(revealedPath, '/Users/test/Downloads/RemoteLink/data.csv');
    });

    testWidgets('shows SnackBar when opening missing file fails',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedFileInfo(
              fileName: 'deleted.txt',
              path: '/Users/test/Downloads/RemoteLink/deleted.txt',
              homeDirForTesting: '/Users/test',
              isWindowsForTesting: false,
              onOpenFile: (p) async => false,
              onRevealFile: (p) async => true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('deleted.txt'));
      await tester.pumpAndSettle();

      expect(find.text('File was moved or deleted'), findsOneWidget);
    });

    testWidgets('shows SnackBar when revealing missing file fails',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedFileInfo(
              fileName: 'moved.png',
              path: '/Users/test/Downloads/RemoteLink/moved.png',
              homeDirForTesting: '/Users/test',
              isWindowsForTesting: false,
              onOpenFile: (p) async => true,
              onRevealFile: (p) async => false,
            ),
          ),
        ),
      );

      await tester.tap(find.text('~/Downloads/RemoteLink/moved.png'));
      await tester.pumpAndSettle();

      expect(find.text('File was moved or deleted'), findsOneWidget);
    });

    testWidgets('provides click mouse cursor on both links', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedFileInfo(
              fileName: 'clip.mp4',
              path: '/Users/test/Downloads/RemoteLink/clip.mp4',
              homeDirForTesting: '/Users/test',
              isWindowsForTesting: false,
              onOpenFile: (p) async => true,
              onRevealFile: (p) async => true,
            ),
          ),
        ),
      );

      final inkWells =
          tester.widgetList<InkWell>(find.byType(InkWell)).toList();
      expect(inkWells.length, 2);
      for (final inkWell in inkWells) {
        expect(inkWell.mouseCursor, SystemMouseCursors.click);
      }
    });

    testWidgets('provides accessibility semantics labels on both links',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SavedFileInfo(
                fileName: 'notes.txt',
                path: '/Users/test/Downloads/RemoteLink/notes.txt',
                homeDirForTesting: '/Users/test',
                isWindowsForTesting: false,
                isMacForTesting: true,
                onOpenFile: (p) async => true,
                onRevealFile: (p) async => true,
              ),
            ),
          ),
        );

        expectAnnouncedAs(tester, 'Open notes.txt');
        expectAnnouncedAs(tester, 'Show notes.txt in Finder');
      } finally {
        handle.dispose();
      }
    });

    testWidgets('announces reveal as folder on non-macOS platforms',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SavedFileInfo(
                fileName: 'notes.txt',
                path: r'C:\Users\test\Downloads\RemoteLink\notes.txt',
                homeDirForTesting: r'C:\Users\test',
                isWindowsForTesting: true,
                isMacForTesting: false,
                onOpenFile: (p) async => true,
                onRevealFile: (p) async => true,
              ),
            ),
          ),
        );

        expectAnnouncedAs(tester, 'Open notes.txt');
        expectAnnouncedAs(tester, 'Show notes.txt in folder');
      } finally {
        handle.dispose();
      }
    });

    testWidgets('both links are keyboard focusable and activatable',
        (tester) async {
      var openCalled = false;
      var revealCalled = false;

      final focusNode = FocusNode();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                TextField(focusNode: focusNode, autofocus: true),
                SavedFileInfo(
                  fileName: 'script.sh',
                  path: '/Users/test/Downloads/RemoteLink/script.sh',
                  homeDirForTesting: '/Users/test',
                  isWindowsForTesting: false,
                  onOpenFile: (p) async {
                    openCalled = true;
                    return true;
                  },
                  onRevealFile: (p) async {
                    revealCalled = true;
                    return true;
                  },
                ),
              ],
            ),
          ),
        ),
      );

      await tester.pump();

      // Tab to the first link (file name).
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(openCalled, isTrue);

      // Tab to the second link (path).
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(revealCalled, isTrue);

      focusNode.dispose();
    });

    testWidgets('tooltip contains full raw path on saved path link',
        (tester) async {
      const fullPath = '/Users/test/Downloads/RemoteLink/photo.jpg';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedFileInfo(
              fileName: 'photo.jpg',
              path: fullPath,
              homeDirForTesting: '/Users/test',
              isWindowsForTesting: false,
              onOpenFile: (p) async => true,
              onRevealFile: (p) async => true,
            ),
          ),
        ),
      );

      final tooltips =
          tester.widgetList<Tooltip>(find.byType(Tooltip)).toList();
      final pathTooltip = tooltips.firstWhere((t) => t.message == fullPath);
      expect(pathTooltip.message, fullPath);
    });
  });

  group('Transfer Card Received File Integration', () {
    testWidgets('shows path text only when savedPath is not null',
        (tester) async {
      fakeFileLauncher.reset();

      final inProgressRecord = TransferRecord(
        transferId: 't-incoming-in-progress',
        peerId: const DeviceId('phone-1'),
        peerName: 'Pixel 8 Pro',
        direction: TransferDirection.incoming,
        status: TransferStatus.inProgress,
        files: const <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'f-1',
            fileName: 'arriving.jpg',
            totalBytes: 2048,
            transferredBytes: 1024,
            savedPath: null,
          ),
        ],
        totalBytes: 2048,
        transferredBytes: 1024,
        createdAt: DateTime.now(),
      );

      final completedRecord = TransferRecord(
        transferId: 't-incoming-completed',
        peerId: const DeviceId('phone-1'),
        peerName: 'Pixel 8 Pro',
        direction: TransferDirection.incoming,
        status: TransferStatus.completed,
        files: const <TransferFileProgress>[
          TransferFileProgress(
            fileId: 'f-2',
            fileName: 'landed.png',
            totalBytes: 4096,
            transferredBytes: 4096,
            isComplete: true,
            savedPath: '/Users/test/Downloads/RemoteLink/landed.png',
          ),
        ],
        totalBytes: 4096,
        transferredBytes: 4096,
        createdAt: DateTime.now(),
      );

      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...desktopHomeOverrides,
            transfersProvider.overrideWith(
              (ref) => Stream<List<TransferRecord>>.value(<TransferRecord>[
                inProgressRecord,
                completedRecord,
              ]),
            ),
          ],
          child: const MaterialApp(home: HomeScreen()),
        ),
      );

      await tester.pump();
      await tester.pump();

      // In-progress file has no saved path shown.
      expect(find.text('arriving.jpg'), findsOneWidget);
      // Completed file has its name and saved path shown.
      expect(find.text('landed.png'), findsOneWidget);
      expect(find.byType(SavedFileInfo), findsOneWidget);

      // Tapping the completed file name opens the file via injected launcher.
      await tester.tap(find.text('landed.png'));
      await tester.pump();
      expect(
        fakeFileLauncher.opened,
        contains('/Users/test/Downloads/RemoteLink/landed.png'),
      );

      // Tapping the path reveals the file via injected launcher.
      final savedInfoFinder = find.byType(SavedFileInfo);
      final pathTextFinder = find
          .descendant(
            of: savedInfoFinder,
            matching: find.byType(Text),
          )
          .at(1);
      await tester.tap(pathTextFinder);
      await tester.pump();
      expect(
        fakeFileLauncher.revealed,
        contains('/Users/test/Downloads/RemoteLink/landed.png'),
      );

      // Verify no duplicate folder IconButton exists for the file row.
      expect(find.byIcon(Icons.folder), findsNothing);
      expect(find.byTooltip('Show in Finder'), findsNothing);
      expect(find.byTooltip('Show in folder'), findsNothing);
    });
  });
}
