import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rl_native/rl_native.dart';
import 'package:rl_protocol/rl_protocol.dart';

import 'support/fakes.dart';

/// A payload for wire types the desktop intentionally does not handle.
///
/// It still advertises the actual type, so the receiving boundary runs its
/// permission check before the unsupported branch. UnknownMessage advertises
/// only `unknown` and would hide a newly permissive tier decision here.
final class _UnimplementedMessage extends Message {
  const _UnimplementedMessage(this.type);

  @override
  final MessageType type;

  @override
  void writeTo(ByteWriter writer) {}
}

void main() {
  // These are independent expectations, deliberately spelled out by wire
  // type. A new enum value must be classified here before the suite passes.
  const minimumTier = <MessageType, PermissionTier>{
    MessageType.clientHello: PermissionTier.readOnly,
    MessageType.serverHello: PermissionTier.readOnly,
    MessageType.handshakeFinish: PermissionTier.readOnly,
    MessageType.ping: PermissionTier.readOnly,
    MessageType.pong: PermissionTier.readOnly,
    MessageType.ack: PermissionTier.readOnly,
    MessageType.error: PermissionTier.readOnly,
    MessageType.close: PermissionTier.readOnly,
    MessageType.resumptionTicket: PermissionTier.readOnly,
    MessageType.resumeSession: PermissionTier.readOnly,
    MessageType.pairRequest: PermissionTier.readOnly,
    MessageType.pairChallenge: PermissionTier.readOnly,
    MessageType.pairConfirm: PermissionTier.readOnly,
    MessageType.pairComplete: PermissionTier.readOnly,
    MessageType.pairReject: PermissionTier.readOnly,
    MessageType.unpair: PermissionTier.readOnly,
    MessageType.connectionRequest: PermissionTier.readOnly,
    MessageType.connectionDecision: PermissionTier.readOnly,
    MessageType.rememberConnection: PermissionTier.readOnly,
    MessageType.mouseMove: PermissionTier.standard,
    MessageType.mouseMoveAbsolute: PermissionTier.standard,
    MessageType.mouseButton: PermissionTier.standard,
    MessageType.mouseScroll: PermissionTier.standard,
    MessageType.gestureZoom: PermissionTier.standard,
    MessageType.gestureRotate: PermissionTier.standard,
    MessageType.gestureSwipe: PermissionTier.standard,
    MessageType.penInput: PermissionTier.standard,
    MessageType.keyEvent: PermissionTier.standard,
    MessageType.textInput: PermissionTier.standard,
    MessageType.namedShortcut: PermissionTier.standard,
    MessageType.modifierState: PermissionTier.standard,
    MessageType.clipboardUpdate: PermissionTier.standard,
    MessageType.clipboardRequest: PermissionTier.standard,
    MessageType.clipboardSyncToggle: PermissionTier.standard,
    MessageType.mediaCommand: PermissionTier.readOnly,
    MessageType.volumeCommand: PermissionTier.readOnly,
    MessageType.mediaState: PermissionTier.readOnly,
    MessageType.brightnessCommand: PermissionTier.readOnly,
    MessageType.screenStreamStart: PermissionTier.standard,
    MessageType.screenStreamStop: PermissionTier.standard,
    MessageType.screenFrame: PermissionTier.standard,
    MessageType.screenConfigure: PermissionTier.standard,
    MessageType.screenTopology: PermissionTier.readOnly,
    MessageType.screenCursor: PermissionTier.standard,
    MessageType.fileOffer: PermissionTier.standard,
    MessageType.fileAccept: PermissionTier.standard,
    MessageType.fileChunk: PermissionTier.standard,
    MessageType.fileComplete: PermissionTier.standard,
    MessageType.fileAbort: PermissionTier.standard,
    MessageType.powerCommand: PermissionTier.admin,
    MessageType.launchApplication: PermissionTier.extended,
    MessageType.openUrl: PermissionTier.extended,
    MessageType.runCommand: PermissionTier.extended,
    MessageType.systemStatus: PermissionTier.readOnly,
    MessageType.deviceInfo: PermissionTier.readOnly,
    MessageType.deviceRename: PermissionTier.readOnly,
    MessageType.permissionGrant: PermissionTier.readOnly,
    MessageType.permissionRequest: PermissionTier.readOnly,
    MessageType.slideCommand: PermissionTier.readOnly,
    MessageType.laserPointer: PermissionTier.readOnly,
    MessageType.presentationBlank: PermissionTier.readOnly,
    MessageType.gamepadState: PermissionTier.standard,
    MessageType.motionState: PermissionTier.standard,
    MessageType.phoneControlStart: PermissionTier.standard,
    MessageType.phoneControlStop: PermissionTier.standard,
    MessageType.phoneControlFrame: PermissionTier.standard,
    MessageType.phoneControlPointer: PermissionTier.standard,
    MessageType.phoneControlScroll: PermissionTier.standard,
    MessageType.phoneControlNavigation: PermissionTier.standard,
    MessageType.phoneControlTextInput: PermissionTier.standard,
  };

  test('every wire type has an explicit tier decision', () {
    expect(
      minimumTier.keys.toSet(),
      MessageType.values.toSet().difference(<MessageType>{MessageType.unknown}),
    );
    expect(PermissionTier.values, hasLength(4));
  });

  for (final type in MessageType.values) {
    for (final tier in PermissionTier.values) {
      test('${type.name} at ${tier.name}', () {
        final minimum = minimumTier[type];
        if (type != MessageType.unknown) {
          expect(minimum, isNotNull, reason: 'classify every new MessageType');
        }
        final message = _sample(type);
        final dispatcher = createTestDispatcher(
          input: const UnsupportedInputBackend('test'),
        );
        final allowed = minimum != null && tier.wireValue >= minimum.wireValue;
        final applied = allowed && message is! _UnimplementedMessage;

        expect(dispatcher.dispatch(message, tier), applied);
        expect(dispatcher.appliedCount, applied ? 1 : 0);
        expect(dispatcher.deniedCount, allowed ? 0 : 1);
        expect(dispatcher.unsupportedCount, allowed && !applied ? 1 : 0);
      });
    }
  }
}

Message _sample(MessageType type) => switch (type) {
      MessageType.mouseMove => const MouseMove(deltaX: 1, deltaY: 1),
      MessageType.mouseMoveAbsolute => const MouseMoveAbsolute(x: 0.5, y: 0.5),
      MessageType.mouseButton =>
        const MouseButtonEvent(button: MouseButton.left, pressed: true),
      MessageType.mouseScroll =>
        const MouseScroll(linesX: 0, linesY: 1, pixelsX: 0, pixelsY: 10),
      MessageType.gestureZoom =>
        const GestureZoom(magnificationDelta: 0.1, phase: GesturePhase.changed),
      MessageType.gestureRotate =>
        const GestureRotate(degreesDelta: 1, phase: GesturePhase.changed),
      MessageType.gestureSwipe =>
        const GestureSwipe(fingerCount: 3, direction: SwipeDirection.up),
      MessageType.keyEvent =>
        const KeyEvent(hidUsage: 4, pressed: true, modifiers: Modifiers.none),
      MessageType.textInput => const TextInput('a'),
      MessageType.namedShortcut =>
        const NamedShortcutMessage(NamedShortcut.copy),
      MessageType.modifierState => const ModifierStateMessage(Modifiers.none),
      MessageType.clipboardUpdate => ClipboardUpdate(
          items: const <ClipboardItem>[],
          contentHash: Uint8List(16),
          originDeviceId: 'phone',
          originSequence: 1),
      MessageType.clipboardSyncToggle => const ClipboardSyncToggle(
          enabled: true, allowImages: false, allowFiles: false),
      MessageType.mediaCommand =>
        const MediaCommand(action: MediaAction.playPause),
      MessageType.volumeCommand =>
        const VolumeCommand(mode: VolumeMode.absolute, value: 0.5),
      MessageType.brightnessCommand =>
        const BrightnessCommand(relative: false, value: 0.5),
      MessageType.powerCommand => const PowerCommand(action: PowerAction.lock),
      MessageType.launchApplication =>
        const LaunchApplication(identifier: 'test.app'),
      MessageType.openUrl => const OpenUrl('https://example.com'),
      MessageType.runCommand => const RunCommand(commandId: 'test'),
      MessageType.deviceRename => const DeviceRename('Test phone'),
      MessageType.permissionRequest =>
        const PermissionRequest(tier: PermissionTier.extended),
      MessageType.fileOffer =>
        FileOffer(transferId: 'test', files: const <OfferedFile>[]),
      MessageType.fileAccept => const FileAccept(
          transferId: 'test',
          sessionId: 'session',
          fileTokens: <String, String>{}),
      MessageType.fileChunk => FileChunk(
          transferId: 'test',
          sessionId: 'session',
          fileId: 'file',
          token: 'token',
          offset: 0,
          bytes: Uint8List(0)),
      MessageType.fileComplete =>
        FileComplete(transferId: 'test', fileId: 'file', sha256: Uint8List(32)),
      MessageType.fileAbort =>
        const FileAbort(transferId: 'test', reason: FileAbortReason.cancelled),
      MessageType.screenStreamStart =>
        const ScreenStreamStart(codec: ScreenCodec.jpeg),
      MessageType.screenStreamStop => const ScreenStreamStop(),
      MessageType.screenConfigure => const ScreenConfigure(),
      _ => _UnimplementedMessage(type),
    };
