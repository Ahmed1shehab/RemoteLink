import 'dart:io';

import 'package:rl_native/rl_native.dart';
import 'package:test/test.dart';

void main() {
  group('ScreenCaptureBackend Unsupported', () {
    test(
        'UnsupportedScreenCaptureBackend returns null frame and reports reason',
        () async {
      const backend = UnsupportedScreenCaptureBackend('unsupported platform');
      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, 'unsupported platform');
      expect(backend.checkPermission(), isFalse);
      expect(backend.requestPermission(), isFalse);
      expect(await backend.captureFrame(), isNull);
      expect(() => backend.dispose(), returnsNormally);
    });
  });

  group('NativeBackends.createScreenCapture', () {
    test('creates backend for the current platform', () async {
      final backend = NativeBackends.createScreenCapture();
      if (Platform.isMacOS) {
        expect(backend, isA<MacosScreenCaptureBackend>());
        expect(() => backend.checkPermission(), returnsNormally);
      } else {
        expect(backend.isAvailable, isFalse);
        expect(backend.unavailableReason, isNotNull);
      }
      backend.dispose();
    });
  });
}
