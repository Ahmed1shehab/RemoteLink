/// RemoteLink cryptography: identity, handshake, pairing, session encryption.
///
/// ## Security model in one paragraph
///
/// Every device holds a long-term X25519 key pair generated on first launch;
/// its public half hashes to the device ID shown in the UI. Connecting runs a
/// simplified Noise XX handshake that starts with an ephemeral exchange (giving
/// forward secrecy and immediate confidentiality), then authenticates both
/// static keys under that encryption so neither is ever visible on the wire.
/// The first connection between two devices additionally requires the user to
/// confirm a six-digit string derived from the handshake transcript, or to scan
/// a QR code carrying the desktop's real key — either way defeating a
/// machine-in-the-middle, which cannot make both transcripts agree. After that
/// the pair is remembered and reconnects are silent. Session traffic is sealed
/// with ChaCha20-Poly1305 under per-direction keys and counter-derived nonces,
/// with the frame header bound in as associated data.
///
/// The full threat model, including what this does *not* defend against, is in
/// `docs/SECURITY.md`.
library;

export 'src/handshake.dart';
export 'src/identity.dart';
export 'src/pairing.dart';
export 'src/primitives.dart';
export 'src/session_cipher.dart';
export 'src/trust_store.dart';
