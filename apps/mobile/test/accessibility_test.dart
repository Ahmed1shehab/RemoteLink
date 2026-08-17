import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/app/providers.dart';
import 'package:remotelink_mobile/src/features/input/touchpad_screen.dart';
import 'package:remotelink_mobile/src/features/keyboard/hardware_keyboard_view.dart';
import 'package:remotelink_mobile/src/features/media/media_screen.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart' as proto;
import 'package:rl_transport/rl_transport.dart';

import 'support/semantics.dart';

/// Every control on the touchpad, media, and keyboard screens was an
/// unlabelled icon or a one-word abbreviation before RL-703. These assert the
/// labels are there and say something a user could act on.
///
/// They are written against the semantics tree rather than against `Tooltip` or
/// `Semantics` widgets on purpose: the tree is what a screen reader consumes,
/// and it is the only place a label being *replaced* by a child's raw glyph
/// shows up.
void main() {
  /// Wraps [child] with the providers these screens read, and lets a test set
  /// the accessibility MediaQuery flags.
  ///
  /// The `builder` is where the MediaQuery override has to go: `MaterialApp`
  /// installs its own from the view, so one wrapped around the outside is
  /// discarded before any of this is built.
  Widget app(
    Widget child, {
    bool accessibleNavigation = false,
    ClientState state = ClientState.connected,
    List<Override> extraOverrides = const <Override>[],
  }) =>
      ProviderScope(
        overrides: <Override>[
          identityProvider.overrideWith(
            (ref) => DeviceIdentity.fromPrivateKey(Uint8List(32)),
          ),
          clientStateProvider.overrideWith(
            (ref) => Stream<ClientState>.value(state),
          ),
          ...extraOverrides,
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(accessibleNavigation: accessibleNavigation),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );

  group('the touchpad surface', () {
    testWidgets('announces itself and the gestures it accepts', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      // Before this, the surface produced no semantics node at all: a bare
      // `Listener` over a decorative icon.
      expect(find.bySemanticsLabel('Touchpad'), findsOneWidget);

      final node = tester.getSemantics(find.bySemanticsLabel('Touchpad'));
      expect(node.hint, contains('Drag to move the pointer'));
      expect(node.hint, contains('Directional controls'));

      handle.dispose();
    });

    testWidgets('offers tap, long press, and scroll as semantic actions',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      // A screen reader intercepts raw touches, so these actions are the only
      // route from a gesture to the cursor.
      final node = tester.getSemantics(find.bySemanticsLabel('Touchpad'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.scrollUp),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.scrollDown),
        isTrue,
      );

      handle.dispose();
    });

    testWidgets('drops the gesture actions when not connected', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(const TouchpadSurfaceView(), state: ClientState.idle),
      );
      await tester.pump();

      // Offering "double tap to click" while nothing is connected promises
      // something that cannot happen.
      final node = tester.getSemantics(find.bySemanticsLabel('Touchpad'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
      expect(node.hint, 'Not connected.');

      handle.dispose();
    });
  });

  group('the touchpad buttons', () {
    testWidgets('announce the action, not the direction', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      // Drawn 'Left', 'Mid', 'Right' — three words that on a screen whose job
      // is moving a pointer left and right read as directions.
      expect(find.text('Left'), findsOneWidget);
      expectAnnouncedAs(tester, 'Left click');
      expectAnnouncedAs(tester, 'Middle click');
      expectAnnouncedAs(tester, 'Right click');

      handle.dispose();
    });

    testWidgets('the pointer-controls toggle is labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      expectAnnouncedAs(tester, 'Show pointer controls');

      handle.dispose();
    });
  });

  group('the pointer controls', () {
    testWidgets('open by themselves when a screen reader is running',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(const TouchpadSurfaceView(), accessibleNavigation: true),
      );
      await tester.pump();

      // The whole point: a screen-reader user lands on the touchpad tab and
      // finds controls, rather than a surface that cannot be driven.
      expect(find.text('Pointer controls'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('stay closed for everyone else', (tester) async {
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      expect(find.text('Pointer controls'), findsNothing);
    });

    testWidgets('open on request, and label every direction with its distance',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      await tester.tap(find.byTooltip('Show pointer controls'));
      await tester.pump();

      // The distance is in the label because it is settable, and a direction
      // button whose step is invisible cannot be aimed.
      expectAnnouncedAs(tester, 'Move pointer up 40 pixels');
      expectAnnouncedAs(tester, 'Move pointer down 40 pixels');
      expectAnnouncedAs(tester, 'Move pointer left 40 pixels');
      expectAnnouncedAs(tester, 'Move pointer right 40 pixels');
      expectAnnouncedAs(tester, 'Scroll up');
      expectAnnouncedAs(tester, 'Scroll down');
      // Once on the pad, once on the button row below it.
      expectAnnouncedAs(tester, 'Right click', count: 2);

      handle.dispose();
    });

    testWidgets('the step control changes the distance the labels promise',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      await tester.tap(find.byTooltip('Show pointer controls'));
      await tester.pump();

      await tester.tap(find.text('Coarse'));
      await tester.pump();

      // A 1440p screen is twelve presses wide at this step. Without it the pad
      // is accessible in principle and unusable in practice.
      expectAnnouncedAs(tester, 'Move pointer right 160 pixels');
      expectAnnouncedAs(tester, 'Move pointer right 40 pixels', count: 0);

      handle.dispose();
    });

    testWidgets('driving the cursor does not throw', (tester) async {
      await tester.pumpWidget(app(const TouchpadSurfaceView()));
      await tester.pump();

      await tester.tap(find.byTooltip('Show pointer controls'));
      await tester.pump();

      for (final label in <String>[
        'Move pointer up 40 pixels',
        'Move pointer down 40 pixels',
        'Move pointer left 40 pixels',
        'Move pointer right 40 pixels',
        'Left click',
        'Right click',
        'Scroll up',
        'Scroll down',
      ]) {
        await tester.tap(find.byTooltip(label));
        await tester.pump();
      }

      expect(tester.takeException(), isNull);
    });
  });

  group('the media screen', () {
    testWidgets('labels the transport buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          const MediaScreen(),
          extraOverrides: <Override>[
            mediaStateProvider.overrideWith(
              (ref) => Stream<proto.MediaState?>.value(
                const proto.MediaState(
                  isPlaying: false,
                  title: 'Test Track',
                  artist: 'Test Artist',
                  album: 'Test Album',
                  positionSeconds: 0,
                  durationSeconds: 100,
                  volume: 0.42,
                  isMuted: false,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expectAnnouncedAs(tester, 'Previous track');
      expectAnnouncedAs(tester, 'Next track');
      // Names the action rather than the state: paused, so pressing it plays.
      expectAnnouncedAs(tester, 'Play');
      expectAnnouncedAs(tester, 'Pause', count: 0);
      expectAnnouncedAs(tester, 'Mute');

      handle.dispose();
    });

    testWidgets('the play button flips its label when playing', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          const MediaScreen(),
          extraOverrides: <Override>[
            mediaStateProvider.overrideWith(
              (ref) => Stream<proto.MediaState?>.value(
                const proto.MediaState(
                  isPlaying: true,
                  title: 'Test Track',
                  artist: '',
                  album: '',
                  positionSeconds: 0,
                  durationSeconds: 100,
                  volume: 0.42,
                  isMuted: true,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      expectAnnouncedAs(tester, 'Pause');
      expectAnnouncedAs(tester, 'Unmute');

      handle.dispose();
    });

    testWidgets('the volume slider reads as a percentage, not a fraction',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          const MediaScreen(),
          extraOverrides: <Override>[
            mediaStateProvider.overrideWith(
              (ref) => Stream<proto.MediaState?>.value(
                const proto.MediaState(
                  isPlaying: false,
                  title: '',
                  artist: '',
                  album: '',
                  positionSeconds: 0,
                  durationSeconds: 0,
                  volume: 0.42,
                  isMuted: false,
                ),
              ),
            ),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();

      // Left alone, a `Slider` announces its raw value: "0.42".
      expectValueAnnounced(tester, 'Volume 42 percent');

      handle.dispose();
    });
  });

  group('the rendered keyboard', () {
    Widget keyboard({
      proto.Modifiers modifiers = proto.Modifiers.none,
      bool capsLock = false,
      PlatformKind platform = PlatformKind.macos,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: HardwareKeyboardView(
              platform: platform,
              modifiers: modifiers,
              capsLock: capsLock,
              enabled: true,
              onKey: (_) {},
              onModifier: (_) {},
              onSwitchToText: () {},
            ),
          ),
        );

    testWidgets('names the keys that are printed as glyphs', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(keyboard());
      await tester.pump();

      // Each of these is drawn as a character whose Unicode name is not the
      // name of the key — '⌫' is "erase to the left", '⌘' is "place of
      // interest sign" — or is not announced at all.
      expect(find.bySemanticsLabel('Backspace'), findsOneWidget);
      expect(find.bySemanticsLabel('Command'), findsWidgets);
      expect(find.bySemanticsLabel('Option'), findsWidgets);
      expect(find.bySemanticsLabel('Control'), findsOneWidget);
      expect(find.bySemanticsLabel('Left arrow'), findsOneWidget);
      expect(find.bySemanticsLabel('Up arrow'), findsOneWidget);
      expect(find.bySemanticsLabel('Space'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Switch to the phone keyboard'),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('names the keys that are printed as abbreviations',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(keyboard());
      await tester.pump();

      expect(find.bySemanticsLabel('Escape'), findsOneWidget);
      expect(find.bySemanticsLabel('Caps lock'), findsOneWidget);
      expect(find.bySemanticsLabel('Return'), findsOneWidget);
      expect(find.bySemanticsLabel('Delete'), findsOneWidget);
      expect(find.bySemanticsLabel('Backslash'), findsOneWidget);
      expect(find.bySemanticsLabel('Semicolon'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('does not leak the raw glyph into the semantics tree',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(keyboard());
      await tester.pump();

      // The glyphs are still drawn — this is a keyboard, and it should look
      // like one.
      expect(find.text('⌫'), findsOneWidget);
      // But they must not be what is announced.
      expect(find.bySemanticsLabel('⌫'), findsNothing);
      expect(find.bySemanticsLabel('⌘'), findsNothing);
      expect(find.bySemanticsLabel('◀'), findsNothing);

      handle.dispose();
    });

    testWidgets('follows the connected computer, not the phone',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(keyboard(platform: PlatformKind.windows));
      await tester.pump();

      // A PC layout prints WIN and ALT GR, which are announced as words rather
      // than spelled or skipped.
      expect(find.bySemanticsLabel('Windows'), findsOneWidget);
      expect(find.bySemanticsLabel('Alt Gr'), findsOneWidget);

      handle.dispose();
    });

    testWidgets('announces a held modifier as toggled on', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        keyboard(
          modifiers: const proto.Modifiers(proto.Modifiers.leftShift),
        ),
      );
      await tester.pump();

      // Shift stuck on is invisible in its consequences until three keystrokes
      // later, and the only cue was a colour change.
      final shift = tester.getSemantics(find.bySemanticsLabel('Shift').first);
      expect(shift.getSemanticsData().hasFlag(SemanticsFlag.isToggled), isTrue);

      handle.dispose();
    });

    testWidgets('announces an unheld modifier as toggled off', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(keyboard());
      await tester.pump();

      final shift = tester.getSemantics(find.bySemanticsLabel('Shift').first);
      expect(shift.getSemanticsData().hasFlag(SemanticsFlag.hasToggledState),
          isTrue);
      expect(
          shift.getSemanticsData().hasFlag(SemanticsFlag.isToggled), isFalse);

      handle.dispose();
    });

    testWidgets('an ordinary key carries no toggle state at all',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(keyboard());
      await tester.pump();

      // 'Q' is not a state, and announcing it as "off" would be noise on every
      // one of sixty keys.
      final q = tester.getSemantics(find.bySemanticsLabel('Q'));
      expect(
        q.getSemanticsData().hasFlag(SemanticsFlag.hasToggledState),
        isFalse,
      );

      handle.dispose();
    });
  });
}
