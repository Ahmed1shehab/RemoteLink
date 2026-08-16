import 'package:latency_harness/latency_harness.dart';
import 'package:test/test.dart';

void main() {
  group('LoadProfiles', () {
    test('available returns registered profile names', () {
      final available = LoadProfiles.available;
      expect(available, contains('idle'));
      expect(available, contains('clipboard'));
    });

    test('creates IdleLoadProfile by name case-insensitively', () {
      final profile = LoadProfiles.create('IDLE');
      expect(profile, isA<IdleLoadProfile>());
      expect(profile.name, 'idle');
    });

    test('creates ClipboardLoadProfile by name case-insensitively', () {
      final profile = LoadProfiles.create('ClipBoard');
      expect(profile, isA<ClipboardLoadProfile>());
      expect(profile.name, 'clipboard');
      final clip = profile as ClipboardLoadProfile;
      expect(clip.payloadSizeBytes, 5 * 1024 * 1024);
    });

    test('throws ArgumentError for unknown profile', () {
      expect(
        () => LoadProfiles.create('unknown_workload'),
        throwsArgumentError,
      );
    });

    test('IdleLoadProfile start and stop are safe no-ops', () async {
      const profile = IdleLoadProfile();
      await profile.stop();
    });

    test('ClipboardLoadProfile stop cancels running timer', () async {
      final profile = ClipboardLoadProfile();
      await profile.stop();
    });
  });
}
