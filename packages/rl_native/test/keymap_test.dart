import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('HID to Windows virtual keys', () {
    test('letters map to their ASCII uppercase codes', () {
      expect(KeyMap.hidToVirtualKey[HidKey.keyA], 0x41);
      expect(KeyMap.hidToVirtualKey[HidKey.keyZ], 0x5A);
      expect(KeyMap.hidToVirtualKey[HidKey.keyC], 0x43);
    });

    test('digits map to their ASCII codes', () {
      expect(KeyMap.hidToVirtualKey[HidKey.digit0], 0x30);
      expect(KeyMap.hidToVirtualKey[HidKey.digit9], 0x39);
    });

    test('every modifier is mapped', () {
      // A missing modifier means a shortcut silently loses its Ctrl or Shift,
      // which is worse than the key not working at all.
      for (var usage = HidKey.controlLeft; usage <= HidKey.metaRight; usage++) {
        expect(
          KeyMap.hidToVirtualKey[usage],
          isNotNull,
          reason: 'HID 0x${usage.toRadixString(16)} has no VK mapping',
        );
      }
    });

    test('navigation keys are flagged as extended', () {
      // Without KEYEVENTF_EXTENDEDKEY, right Alt stops acting as AltGr and
      // Home/End get confused with their numpad twins.
      for (final usage in <int>[
        HidKey.arrowUp,
        HidKey.arrowDown,
        HidKey.arrowLeft,
        HidKey.arrowRight,
        HidKey.home,
        HidKey.end,
        HidKey.pageUp,
        HidKey.pageDown,
        HidKey.insert,
        HidKey.delete,
        HidKey.altRight,
        HidKey.controlRight,
      ]) {
        final virtualKey = KeyMap.hidToVirtualKey[usage]!;
        expect(
          KeyMap.windowsExtendedKeys.contains(virtualKey),
          isTrue,
          reason: 'VK 0x${virtualKey.toRadixString(16)} should be extended',
        );
      }
    });

    test('no two distinct usages collide except intentional aliases', () {
      // Enter and numpad Enter genuinely share VK_RETURN on Windows; that is
      // the only permitted collision.
      final seen = <int, int>{};
      final collisions = <String>[];
      KeyMap.hidToVirtualKey.forEach((usage, virtualKey) {
        final previous = seen[virtualKey];
        if (previous != null) {
          collisions.add('0x${previous.toRadixString(16)} vs '
              '0x${usage.toRadixString(16)} → 0x'
              '${virtualKey.toRadixString(16)}');
        }
        seen[virtualKey] = usage;
      });
      expect(collisions, hasLength(1), reason: collisions.join(', '));
    });
  });

  group('HID to macOS key codes', () {
    test('letters map to their documented ANSI codes', () {
      expect(KeyMap.hidToMacKeyCode[HidKey.keyA], 0x00);
      expect(KeyMap.hidToMacKeyCode[HidKey.keyC], 0x08);
      expect(KeyMap.hidToMacKeyCode[HidKey.keyV], 0x09);
      expect(KeyMap.hidToMacKeyCode[HidKey.keyZ], 0x06);
    });

    test('every letter and digit is mapped', () {
      for (var usage = HidKey.keyA; usage <= HidKey.digit0; usage++) {
        expect(
          KeyMap.hidToMacKeyCode[usage],
          isNotNull,
          reason: 'HID 0x${usage.toRadixString(16)} has no CGKeyCode',
        );
      }
    });

    test('every modifier is mapped and distinct', () {
      final codes = <int>{};
      for (var usage = HidKey.controlLeft; usage <= HidKey.metaRight; usage++) {
        final code = KeyMap.hidToMacKeyCode[usage];
        expect(code, isNotNull, reason: 'HID 0x${usage.toRadixString(16)}');
        expect(codes.add(code!), isTrue, reason: 'duplicate CGKeyCode $code');
      }
    });

    test('macOS keycodes are unique', () {
      final seen = <int>{};
      KeyMap.hidToMacKeyCode.forEach((usage, code) {
        expect(
          seen.add(code),
          isTrue,
          reason: 'CGKeyCode 0x${code.toRadixString(16)} used twice',
        );
      });
    });
  });

  group('modifier flags', () {
    test('map to CGEventFlags bits', () {
      const modifiers = Modifiers(
        Modifiers.leftControl | Modifiers.leftShift,
      );
      final flags = KeyMap.macFlagsFor(modifiers);
      expect(flags & KeyMap.macFlagControl, isNonZero);
      expect(flags & KeyMap.macFlagShift, isNonZero);
      expect(flags & KeyMap.macFlagCommand, 0);
    });

    test('empty modifiers produce no flags', () {
      expect(KeyMap.macFlagsFor(Modifiers.none), 0);
    });
  });

  group('named shortcut resolution', () {
    test('Copy uses Command on macOS and Control on Windows', () {
      final mac = KeyMap.resolveShortcut(
        NamedShortcut.copy,
        PlatformKind.macos,
      )!;
      expect(mac.$1.hasMeta, isTrue);
      expect(mac.$1.hasControl, isFalse);
      expect(mac.$2, HidKey.keyC);

      final windows = KeyMap.resolveShortcut(
        NamedShortcut.copy,
        PlatformKind.windows,
      )!;
      expect(windows.$1.hasControl, isTrue);
      expect(windows.$1.hasMeta, isFalse);
      expect(windows.$2, HidKey.keyC);
    });

    test('Redo differs between platforms', () {
      // Cmd+Shift+Z on macOS, Ctrl+Y on Windows. Encoding this on the desktop
      // is why the phone ships one Redo button instead of two.
      final mac =
          KeyMap.resolveShortcut(NamedShortcut.redo, PlatformKind.macos)!;
      expect(mac.$1.hasShift, isTrue);
      expect(mac.$2, HidKey.keyZ);

      final windows =
          KeyMap.resolveShortcut(NamedShortcut.redo, PlatformKind.windows)!;
      expect(windows.$1.hasShift, isFalse);
      expect(windows.$2, HidKey.keyY);
    });

    test('Task Manager has no macOS keyboard equivalent', () {
      expect(
        KeyMap.resolveShortcut(
          NamedShortcut.taskManager,
          PlatformKind.macos,
        ),
        isNull,
        reason: 'null routes this to the application launcher instead',
      );

      final windows = KeyMap.resolveShortcut(
        NamedShortcut.taskManager,
        PlatformKind.windows,
      )!;
      expect(windows.$1.hasControl, isTrue);
      expect(windows.$1.hasShift, isTrue);
      expect(windows.$2, HidKey.escape);
    });

    test('every shortcut resolves on at least one platform', () {
      for (final shortcut in NamedShortcut.values) {
        if (shortcut == NamedShortcut.unrecognised) continue;
        final mac = KeyMap.resolveShortcut(shortcut, PlatformKind.macos);
        final windows = KeyMap.resolveShortcut(shortcut, PlatformKind.windows);
        expect(
          mac != null || windows != null,
          isTrue,
          reason: '${shortcut.name} resolves nowhere',
        );
      }
    });

    test('an unrecognised shortcut resolves to nothing', () {
      expect(
        KeyMap.resolveShortcut(
          NamedShortcut.unrecognised,
          PlatformKind.windows,
        ),
        isNull,
      );
    });
  });

  group('unsupported backends are inert', () {
    test('input backend reports why and does nothing', () {
      const backend = UnsupportedInputBackend('no driver');
      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, 'no driver');

      // Must not throw: a null object here means the desktop runs on Linux with
      // input disabled rather than crashing on launch.
      expect(() {
        backend
          ..moveCursorBy(1, 1)
          ..mouseDown(MouseButton.left)
          ..keyEvent(hidUsage: HidKey.keyA, pressed: true)
          ..typeText('hello')
          ..releaseAll()
          ..dispose();
      }, returnsNormally);
      expect(backend.cursorPosition, (0, 0));
    });

    test('clipboard backend reports unavailable and does nothing', () {
      const backend = UnsupportedClipboardBackend();
      expect(backend.isAvailable, isFalse);
      expect(backend.readText(), isNull);
      expect(() => backend.writeText('x'), returnsNormally);
    });

    test('system info backend reports unavailable and returns empty metrics',
        () async {
      const backend = UnsupportedSystemInfoBackend('no driver');
      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, 'no driver');
      final metrics = await backend.metrics();
      expect(metrics.batteryPercent, isNull);
      expect(metrics.isCharging, isNull);
      expect(metrics.cpuPercent, isNull);
      expect(metrics.memoryPercent, isNull);
      expect(metrics.uptimeSeconds, isNull);
      expect(() => backend.dispose(), returnsNormally);
    });
  });
}
