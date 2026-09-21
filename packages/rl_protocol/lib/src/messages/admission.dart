import 'package:meta/meta.dart';

import '../bytes.dart';
import '../message_type.dart';
import 'message.dart';

/// How long a held connection waits for an answer before it is turned away.
///
/// A minute: long enough to walk to the other device, short enough that a phone
/// is never left spinning at a machine nobody is sitting at. Defined once, here
/// beside the message that carries it, because the two ends have to agree —
/// a listener that gives up sooner than the asker expects produces a refusal
/// nobody chose, and the other way round leaves a phone waiting past the point
/// where an answer could still arrive.
const Duration kConnectionApprovalWindow = Duration(seconds: 60);

/// Server → client. The connection is authenticated but held at the door.
///
/// Pairing answers "is this device allowed to know me"; this answers "is this
/// device allowed in *now*". They are different questions and a paired device
/// only ever asked the first one — after a pairing, every later connection
/// happened in silence, so a phone that was borrowed, stolen, or simply carried
/// into range reached the computer with nobody being told.
///
/// The message exists because the alternative is a phone that cannot tell being
/// held from being connected. A held session drops everything outside
/// subsystems 0x00 and 0x01, so without this the phone would show a touchpad
/// that moves nothing and a Send button whose files vanish — the exact
/// "looks connected, does nothing" state that is worse than a refusal.
///
/// Always followed by a [ConnectionDecision]: the peer either lets the session
/// through or says why it will not, and [timeoutSeconds] bounds the wait so a
/// computer nobody is sitting at cannot leave a phone spinning forever.
@immutable
final class ConnectionRequest extends Message {
  const ConnectionRequest({
    required this.deviceName,
    required this.timeoutSeconds,
  });

  /// What the *asking* end is called, so the phone can name who it is waiting
  /// for rather than saying "waiting for the other device".
  ///
  /// Peer-supplied, like every other name on the wire, and therefore passed
  /// through `sanitiseDeviceName` before it reaches a screen or a log.
  final String deviceName;

  /// How long the far end will keep asking before it gives up and declines.
  ///
  /// Carried rather than assumed so the two ends agree about when the wait is
  /// over. A phone counting down its own guess would either abandon a request
  /// the user was still reading or wait past the point where an answer could
  /// still arrive.
  final int timeoutSeconds;

  @override
  MessageType get type => MessageType.connectionRequest;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString(deviceName)
      ..writeVarUint(timeoutSeconds);
  }

  static ConnectionRequest readFrom(ByteReader reader) => ConnectionRequest(
        deviceName: reader.readString(maxLength: 128),
        timeoutSeconds: reader.readVarUint(),
      );
}

/// What a person, or the clock, decided about a held connection.
enum ConnectionAnswer {
  /// Let in. The session is unblocked and the usual grant follows.
  allowed(1),

  /// Someone pressed the equivalent of "Don't allow".
  declined(2),

  /// Nobody answered within the window the request advertised.
  ///
  /// Distinct from [declined] because it means something different to the
  /// person holding the phone: the computer is not refusing them, it is
  /// unattended. Collapsing the two would send someone looking for a setting
  /// they never changed.
  timedOut(3);

  const ConnectionAnswer(this.wireValue);

  final int wireValue;

  /// Unknown values read as [declined] rather than throwing.
  ///
  /// Fail-closed, and deliberately so: a future build that adds a reason must
  /// not have it read as consent by an older one.
  static ConnectionAnswer fromWire(int value) => values.firstWhere(
        (answer) => answer.wireValue == value,
        orElse: () => ConnectionAnswer.declined,
      );
}

/// Server → client. The answer to a [ConnectionRequest].
///
/// Sent in every case, including the ones where the session is about to close.
/// A connection that simply disappears is indistinguishable from a Wi-Fi drop,
/// and the reconnect supervisor treats those alike — so a phone that was turned
/// away would have dialled straight back in and put the question on the other
/// screen again, and again, until someone gave up and tapped Allow.
@immutable
final class ConnectionDecision extends Message {
  const ConnectionDecision(this.answer);

  final ConnectionAnswer answer;

  bool get isAllowed => answer == ConnectionAnswer.allowed;

  @override
  MessageType get type => MessageType.connectionDecision;

  @override
  void writeTo(ByteWriter writer) => writer.writeUint8(answer.wireValue);

  static ConnectionDecision readFrom(ByteReader reader) =>
      ConnectionDecision(ConnectionAnswer.fromWire(reader.readUint8()));
}

/// Either direction. One end's answer to "should we remember each other?".
///
/// ## Why both ends have to agree
///
/// Remembering is a promise each device makes about its own front door: "this
/// peer may come in without anyone being asked". One end cannot make that
/// promise on the other's behalf, and a single yes would let the *asking*
/// device decide it is no longer worth asking about — which is the one answer
/// it must not be allowed to give itself.
///
/// So both ends put the question to their own user, both send their answer,
/// and each side remembers the other only when it has two yeses in hand. A
/// peer that never answers — an older build, or a session that dropped while
/// the question was on screen — leaves the agreement unsettled, and an
/// unsettled agreement means nothing changes. Failing closed here costs a
/// prompt next time; failing open costs a door left unlocked.
///
/// Sent on an established session, after both ends are through whatever gate
/// they had. It is deliberately not part of pairing: pairing is where trust
/// begins and is busy asking people to compare digits, and a second question
/// stacked on that one is a question nobody reads.
@immutable
final class RememberConnection extends Message {
  const RememberConnection({required this.agreed});

  /// What the person on *this* end said.
  ///
  /// A no is sent rather than withheld. Silence is how a peer that cannot
  /// answer at all looks, and the other end has a prompt on screen waiting to
  /// be taken down — telling it the answer is what lets it stop waiting and
  /// say what happened.
  final bool agreed;

  @override
  MessageType get type => MessageType.rememberConnection;

  @override
  void writeTo(ByteWriter writer) => writer.writeBool(agreed);

  static RememberConnection readFrom(ByteReader reader) =>
      RememberConnection(agreed: reader.readBool());
}
