import 'dart:io';

import 'package:rl_native/rl_native.dart';
import 'package:test/test.dart';

void main() {
  group('BrightnessBackend Unsupported', () {
    test(
        'UnsupportedBrightnessBackend returns default level and reports reason',
        () async {
      const backend = UnsupportedBrightnessBackend('unsupported platform');
      expect(backend.isAvailable, isFalse);
      expect(backend.unavailableReason, 'unsupported platform');
      expect(await backend.level(), 0.0);
      expect(() async => backend.setLevel(0.7), returnsNormally);
      expect(() => backend.dispose(), returnsNormally);
    });
  });

  group('NativeBackends.createBrightness', () {
    test('creates backend for the current platform', () async {
      final backend = NativeBackends.createBrightness();
      if (Platform.isMacOS || Platform.isWindows) {
        expect(backend.isAvailable, isTrue);
        expect(backend.unavailableReason, isNull);
        final level = await backend.level();
        expect(level, inInclusiveRange(0.0, 1.0));
      } else {
        expect(backend.isAvailable, isFalse);
        expect(backend.unavailableReason, isNotNull);
      }
      backend.dispose();
    });
  });
}
