import 'package:rl_native/src/windows/win32_media.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('transport actions map to Windows media virtual keys', () {
    expect(windowsMediaVirtualKey(MediaAction.playPause), 0xb3);
    expect(windowsMediaVirtualKey(MediaAction.play), 0xb3);
    expect(windowsMediaVirtualKey(MediaAction.pause), 0xb3);
    expect(windowsMediaVirtualKey(MediaAction.next), 0xb0);
    expect(windowsMediaVirtualKey(MediaAction.previous), 0xb1);
    expect(windowsMediaVirtualKey(MediaAction.stop), 0xb2);
  });

  test('actions without global keys do not trigger a different command', () {
    for (final action in <MediaAction>[
      MediaAction.seekForward,
      MediaAction.seekBackward,
      MediaAction.fastForward,
      MediaAction.rewind,
      MediaAction.shuffleToggle,
      MediaAction.repeatToggle,
    ]) {
      expect(windowsMediaVirtualKey(action), isNull);
    }
  });
}
