import 'package:meta/meta.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';

/// Tracks one session's progress towards "these two devices remember each
/// other".
///
/// Both ends ask their own user, both send a [bool] answer, and a device is
/// only remembered when two yeses are in hand — see `RememberConnection` for
/// why one is not enough. This holds the half of that which is state: which
/// answers have arrived, and whether the pair of them adds up to an agreement.
///
/// Deliberately a plain object with no transport, no storage and no clock. The
/// two apps that use it reach their trust stores very differently — a file on
/// a desktop, platform-protected storage on a phone — and the part worth
/// getting right is the same on both: that a missing answer is not a yes, and
/// that a settled disagreement is remembered as "asked" rather than left to
/// come back on the next connection.
final class RememberAgreement {
  RememberAgreement({required this.peerId, required this.peerName});

  final DeviceId peerId;

  /// What to call the peer in the question. The stored name, never a name the
  /// peer sent with this connection.
  final String peerName;

  bool? _mine;
  bool? _theirs;

  /// What the person on this device said, or null while the prompt is still up.
  bool? get mine => _mine;

  /// What the peer told us its user said, or null while it has not.
  bool? get theirs => _theirs;

  /// Whether both answers are in.
  bool get isSettled => _mine != null && _theirs != null;

  /// Whether both answers are yes.
  ///
  /// False while unsettled, which is the whole point: a peer that says nothing
  /// is a peer that has not agreed, and the timeout for that is the session.
  bool get isAgreed => _mine == true && _theirs == true;

  /// Records this device's answer. Returns false if it was already given, so a
  /// double tap cannot send two answers.
  bool recordMine({required bool agreed}) {
    if (_mine != null) return false;
    _mine = agreed;
    return true;
  }

  /// Records the peer's answer. Returns false if it had already sent one,
  /// which a peer has no legitimate reason to do.
  bool recordTheirs({required bool agreed}) {
    if (_theirs != null) return false;
    _theirs = agreed;
    return true;
  }

  /// How [peer] should be stored, given what is known so far.
  ///
  /// Written as soon as *this* device has answered, not only once the peer has.
  /// That is what stops the question coming back on every connection when the
  /// other end never answers it at all — an older build, or one whose user
  /// walked away — which would be a worse nag than the prompt this feature
  /// exists to remove. The promise itself still needs both yeses: an unsettled
  /// agreement records only that the question was put.
  ///
  /// `autoAdmit` is only ever *raised* here, never lowered: forgetting a device
  /// is something a person does in the device list, and a later session whose
  /// prompt was dismissed must not quietly undo an answer given earlier.
  TrustedPeer applyTo(TrustedPeer peer) => peer.copyWith(
        autoAdmit: isAgreed ? true : peer.autoAdmit,
        rememberAsked: true,
      );
}

/// Whether [peer] should be asked about on this connection.
///
/// Two devices that have already agreed are not asked again, and neither is a
/// device whose owner said no — see [TrustedPeer.rememberAsked]. Null means
/// the peer is not in the trust store at all, which is a session that has not
/// finished pairing and therefore has no name to put in the question yet.
@useResult
bool shouldAskToRemember(TrustedPeer? peer) =>
    peer != null && !peer.revoked && !peer.autoAdmit && !peer.rememberAsked;
