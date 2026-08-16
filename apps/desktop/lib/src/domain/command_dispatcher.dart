import 'package:rl_core/rl_core.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

/// Applies inbound protocol messages to the host.
///
/// This is the security boundary of the desktop app. Everything arriving here
/// came from a phone, and a phone is untrusted input no matter how it
/// authenticated: a paired device could be compromised, borrowed, or running a
/// modified client. Every message is therefore checked against the session's
/// permission tier *here*, on the receiving side, rather than relying on the
/// mobile UI to hide buttons. Hiding a button is a usability affordance; this
/// is the enforcement.
///
/// The dispatcher is deliberately synchronous and allocation-free on the input
/// path. It sits between the socket and the cursor, so any latency it adds is
/// latency the user sees.
final class CommandDispatcher {
  CommandDispatcher({
    required InputBackend input,
    required this.platform,
    required this.onPowerCommand,
    required this.onLaunchApplication,
    required this.onOpenUrl,
    required this.onRunCommand,
    required this.onClipboardUpdate,
    required this.onMediaCommand,
    required this.onVolumeCommand,
    required this.onDeviceRename,
    required this.onFileTransferMessage,
  }) : _input = input;

  final InputBackend _input;
  final PlatformKind platform;

  /// Handlers for actions that are not pure input. They are injected rather
  /// than implemented here because each one needs process spawning, OS service
  /// APIs, or user confirmation — none of which belong on the input hot path.
  final void Function(PowerCommand command) onPowerCommand;
  final void Function(LaunchApplication command) onLaunchApplication;
  final void Function(OpenUrl command) onOpenUrl;
  final void Function(RunCommand command) onRunCommand;
  final void Function(ClipboardUpdate update) onClipboardUpdate;
  final void Function(MediaCommand command) onMediaCommand;
  final void Function(VolumeCommand command) onVolumeCommand;
  final void Function(DeviceRename command) onDeviceRename;
  final void Function(Message message) onFileTransferMessage;

  final Log _log = Log.scoped('desktop.dispatcher');

  /// Statistics, surfaced in the desktop's diagnostics panel.
  int _applied = 0;
  int _denied = 0;
  int _unsupported = 0;

  int get appliedCount => _applied;
  int get deniedCount => _denied;
  int get unsupportedCount => _unsupported;

  /// Applies [message] if [tier] permits it.
  ///
  /// Returns `false` when the message was refused, so the caller can decide
  /// whether to inform the peer. Most refusals are answered with silence:
  /// telling a device precisely which permission it lacks helps an attacker
  /// enumerate the tier system, and a well-behaved client already knows its
  /// tier from the grant it received.
  bool dispatch(Message message, PermissionTier tier) {
    if (!tier.allows(message.type)) {
      _denied++;
      _log.debug(() => 'denied ${message.type.name} at tier ${tier.name}');
      return false;
    }

    switch (message) {
      case MouseMove():
        _input.moveCursorBy(message.deltaX, message.deltaY);

      case MouseMoveAbsolute():
        final bounds = _input.virtualBounds;
        _input.moveCursorTo(
          bounds.x + (message.x.clamp(0.0, 1.0) * bounds.width).round(),
          bounds.y + (message.y.clamp(0.0, 1.0) * bounds.height).round(),
        );

      case MouseButtonEvent():
        _applyMouseButton(message);

      case MouseScroll():
        _input.scroll(
          linesX: message.linesX,
          linesY: message.linesY,
          pixelsX: message.pixelsX,
          pixelsY: message.pixelsY,
          isMomentum: message.isMomentum,
        );

      case KeyEvent():
        // The modifier snapshot is applied first so that a chord arrives in the
        // right order even if an earlier modifier event was lost. Without this,
        // one dropped packet leaves the desktop with a phantom held Shift.
        _input
          ..setModifiers(message.modifiers)
          ..keyEvent(hidUsage: message.hidUsage, pressed: message.pressed);

      case TextInput():
        _input.typeText(message.text);

      case ModifierStateMessage():
        _input.setModifiers(message.modifiers);

      case NamedShortcutMessage():
        if (!_applyShortcut(message.shortcut)) {
          _unsupported++;
          return false;
        }

      case ClipboardUpdate():
        onClipboardUpdate(message);

      case MediaCommand():
        onMediaCommand(message);

      case VolumeCommand():
        onVolumeCommand(message);

      case PowerCommand():
        onPowerCommand(message);

      case LaunchApplication():
        onLaunchApplication(message);

      case OpenUrl():
        onOpenUrl(message);

      case RunCommand():
        onRunCommand(message);

      case DeviceRename():
        final sanitised = sanitiseDeviceName(message.name);
        if (sanitised == null) {
          _log.warn(
            'refusing invalid device rename',
            fields: <String, Object?>{'raw': message.name},
          );
          return false;
        }
        onDeviceRename(DeviceRename(sanitised));

      case FileOffer() ||
            FileAccept() ||
            FileChunk() ||
            FileComplete() ||
            FileAbort():
        onFileTransferMessage(message);

      default:
        _unsupported++;
        _log.debug(() => 'no handler for ${message.type.name}');
        return false;
    }

    _applied++;
    return true;
  }

  void _applyMouseButton(MouseButtonEvent event) {
    // macOS derives double-click from an explicit click-state field rather than
    // from timing, so the count the phone measured is passed through. Relying
    // on the OS to infer it would break every time network jitter stretched two
    // taps past the threshold.
    final input = _input;
    if (input is MacosInputBackend) {
      input.mouseButtonWithCount(
        event.button,
        pressed: event.pressed,
        clickCount: event.clickCount,
      );
      return;
    }

    if (event.pressed) {
      input.mouseDown(event.button);
    } else {
      input.mouseUp(event.button);
    }
  }

  bool _applyShortcut(NamedShortcut shortcut) {
    final resolved = KeyMap.resolveShortcut(shortcut, platform);
    if (resolved == null) return false;

    final (modifiers, usage) = resolved;

    // Press modifiers, tap the key, release modifiers. Sending the chord in
    // this order — rather than as a single key event carrying a modifier mask —
    // is what makes it look like a real key press to applications that watch
    // for modifier transitions.
    _input
      ..setModifiers(modifiers)
      ..keyEvent(hidUsage: usage, pressed: true)
      ..keyEvent(hidUsage: usage, pressed: false)
      ..setModifiers(Modifiers.none);
    return true;
  }

  /// Releases everything the peer was holding.
  ///
  /// Called when a session ends for any reason. Skipping it leaves the desktop
  /// with a stuck modifier or a held mouse button from a connection that no
  /// longer exists — a state the user cannot diagnose and can only fix by
  /// pressing the key locally.
  void onSessionEnded() => _input.releaseAll();
}
