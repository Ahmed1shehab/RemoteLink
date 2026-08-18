import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the native side of "the close button must not stop the service".
///
/// ## Why a test that reads Swift
///
/// This is not a unit test and does not pretend to be one. The behaviour it
/// protects cannot be reached from Dart at all, and the bug it protects against
/// is the worst kind: the desktop companion quit outright when its window was
/// closed — the socket, the discovery beacon and every paired phone went with
/// it — and it did so *silently*, and only when the click actually landed, so
/// it read as a flaky disconnect rather than as the app exiting.
///
/// The cause was one line of the `flutter create` template. Dart intercepts the
/// close and calls `hide()`, which is `NSWindow.orderOut`; AppKit counts an
/// ordered-out window as gone, finds no windows left, and honours
/// `applicationShouldTerminateAfterLastWindowClosed` — which the template
/// returns `true` from. Every part of that is invisible from the Dart side.
///
/// Anyone regenerating the macOS runner gets the template's answer back, and
/// nothing else in this repository would notice. So the file is read.
void main() {
  group('macOS runner', () {
    late String appDelegate;

    setUpAll(() {
      appDelegate = File('macos/Runner/AppDelegate.swift').readAsStringSync();
    });

    test('does not terminate when the last window goes away', () {
      final body = _bodyOf(
        appDelegate,
        'applicationShouldTerminateAfterLastWindowClosed',
      );
      expect(
        body,
        isNotNull,
        reason: 'the override is missing, so the template default — quit — '
            'applies and closing the window kills the service',
      );
      expect(body, contains('return false'));
      expect(body, isNot(contains('return true')));
    });

    test('brings the window back when the Dock icon is clicked', () {
      // The other half of the same decision. `orderOut` leaves AppKit with
      // nothing to restore, so without this the Dock icon does nothing at all
      // once the window has been closed once — and the window is the only place
      // pairing happens.
      expect(
        _bodyOf(appDelegate, 'applicationShouldHandleReopen'),
        isNotNull,
      );
      expect(appDelegate, contains('makeKeyAndOrderFront'));
    });
  });

  group('the window is titled with the product name', () {
    test('macOS names the bundle "Remote Link"', () {
      final config =
          File('macos/Runner/Configs/AppInfo.xcconfig').readAsStringSync();
      expect(config, contains('PRODUCT_NAME = Remote Link'));
    });

    test('Windows describes the binary as "Remote Link"', () {
      final resources = File('windows/runner/Runner.rc').readAsStringSync();
      expect(resources, contains('VALUE "ProductName", "Remote Link"'));
      expect(resources, contains('VALUE "FileDescription", "Remote Link"'));
    });
  });
}

/// The text of one Swift function, from its signature to its closing brace.
String? _bodyOf(String source, String name) {
  final start = source.indexOf(name);
  if (start < 0) return null;
  final open = source.indexOf('{', start);
  if (open < 0) return null;

  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(open, i + 1);
    }
  }
  return null;
}
