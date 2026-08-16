# Security model

A remote-control product is a deliberate, permanent hole in a machine's input
boundary. This document says exactly what that hole is bounded by, and — more
usefully — what it is **not**.

---

## 1. What is being protected

A paired phone can move the cursor, type, read and write the clipboard, and
depending on tier launch applications and power down the machine. Anyone who
can impersonate a paired phone has, for practical purposes, physical access to
the computer. Every design decision below follows from that.

---

## 2. Threat model

### Defended against

| Threat | Mechanism |
|---|---|
| Passive eavesdropping on the LAN | ChaCha20-Poly1305 over an ephemeral X25519 exchange |
| Retroactive decryption after key theft | Fresh ephemerals per connection give forward secrecy |
| Active machine-in-the-middle during pairing | Six-digit SAS compared by the user, or QR carrying the real key |
| Server impersonation after pairing | Stored static key is enforced; a mismatch is rejected, not re-paired |
| Unpaired device connecting | Handshake completes but the session refuses all application traffic |
| Revoked device reconnecting | Trust store answers definitively; live sessions are closed on revocation |
| Message tampering or truncation | Poly1305 over every record; a failed tag closes the connection |
| Replay of captured input | Counter-derived nonces; a repeat cannot decrypt |
| Frame-type substitution | The header is *inside* the AEAD, not merely authenticated alongside it |
| Brute-forcing the six-digit code | Three attempts, then a fifteen-minute per-peer lockout |
| Pre-auth memory exhaustion | 17 MiB record cap and 8 concurrent-handshake cap, both enforced before allocation |
| Pre-auth CPU exhaustion | Handshake slots capped; a 10 s timeout releases half-open connections |
| Device fingerprinting on a public network | Static keys are sent encrypted; the hellos carry only ephemerals |
| Compromised phone exceeding its remit | Permission tiers enforced on the desktop, per message, per session |
| Copied passwords leaking to a phone | `ConcealedType` / `ExcludeClipboardContentFromMonitorProcessing` honoured |
| Arbitrary code execution via `runCommand` | Command text never crosses the wire; only pre-registered IDs do |
| `openUrl` used as a general launcher | Scheme allow-list: `http`, `https`, `mailto` |

### Explicitly not defended against

Stating these plainly is more useful than a longer list above.

- **A compromised desktop.** If the machine running the service is owned, this
  protocol is not the relevant problem.
- **A user who approves a pairing without reading the digits.** The SAS is the
  only defence against an active machine-in-the-middle, and it works only if it
  is actually compared. This is why the pairing UI makes the number the largest
  element on screen and labels the button "The numbers match" rather than "OK".
- **A malicious app on an unlocked, already-paired phone.** It inherits that
  phone's trust. Tiers limit the blast radius; they do not eliminate it.
- **Traffic analysis.** Sizes and timings are visible. An observer can tell
  that input is happening, roughly how fast, and when it stops. Padding was
  considered and rejected: it would add latency to the one path where latency is
  the product.
- **Denial of service by an attacker on the same LAN.** They can flood the
  discovery port or exhaust handshake slots. Mitigations bound the damage;
  nothing prevents it.
- **Physical extraction of the desktop private key.** See §4 — this is the
  largest known gap.

---

## 3. Why the six-digit code is not weak

The instinct is that six digits means one-in-a-million, which sounds thin.
The reasoning is different from a password's:

The SAS is a hash of **both** ephemeral public keys and the full transcript. An
attacker relaying the connection necessarily runs two separate key agreements
and therefore produces two different transcripts. They cannot choose the digits
either side displays — the value is determined by key material committed to
before either screen lights up. So a MITM does not need to *guess* the code;
they need to *collide* a hash they cannot influence.

The residual risk is a blind guess in a one-shot game, which is exactly what
the rate limiter addresses: three attempts, then a fifteen-minute lockout per
peer, which reduces an attacker to roughly twelve guesses an hour against a
10⁶ space. Lockouts are per-peer rather than global, so one hostile device on
the network cannot lock a user out of pairing their own phone.

QR pairing removes even that. The phone learns the desktop's real static key
over an optical channel no network attacker can reach, *before* the handshake,
so there is no window to attack — the handshake either authenticates against
the scanned key or fails.

---

## 4. Known gaps, ranked

1. **Desktop private key at rest.** It is stored in a file with owner-only
   permissions. It belongs in DPAPI-backed storage on Windows and the Keychain
   on macOS. The mobile app already uses the platform keystore. This is the
   first hardening task after milestone 1. *Mitigating context: an attacker
   with read access to the user's profile already has better options than
   impersonating a remote-control server.*

2. **No UDP channel yet, so no anti-replay window in use.** `ReplayWindow` is
   implemented and tested but currently redundant, because TCP delivers in
   order. It must be wired in before the unreliable input channel ships, or
   captured datagrams become replayable.

3. **Trust-store integrity on mobile.** Contents are only public keys, so
   confidentiality is not the issue — integrity is. An attacker who could
   rewrite that store could substitute their own key for a trusted computer's
   and the phone would connect with no prompt. Secure storage mitigates this;
   a MAC over the store would close it.

4. **No session resumption implementation.** The messages and the derived
   secret exist; the server-side ticket sealing does not. Until it does, every
   reconnect is a full handshake — correct, just slower than the design allows.

5. ~~**A revoked device reconnects forever.**~~ **Closed.** The server now sends
   an `error` frame carrying `ProtocolErrorCode.revoked` over the established,
   encrypted session before closing, and the client stops on any non-retryable
   code rather than backing off and retrying indefinitely.

   One consequence is worth stating plainly, because it is a real trade rather
   than a free win. Making the rejection *encrypted* requires session keys,
   and session keys require a completed handshake — so the server defers the
   revocation check until immediately after authentication, and a revoked
   device now completes a full handshake (four X25519 operations) before being
   turned away, where previously its lookup failed earlier.

   That is a small amplification available to a revoked peer specifically. It is
   bounded by the same eight-slot concurrent-handshake cap and ten-second
   timeout that bound every other pre-authentication cost, and it buys an
   unambiguous rejection the client can act on. The alternative — refusing at
   handshake time — can only produce a *plaintext* failure, which would announce
   "this device is revoked" to anyone watching the network and undo the reason
   static keys are encrypted in the first place.

6. ~~**`GetClipboardSequenceNumber` polling has a race.**~~ **Closed.**
   Authorship of a clipboard change is no longer inferred from timing. The
   desktop records the content hash of each write it performs and treats an
   observed change as its own only when the content matches. Three hashes are
   retained, because a rapid remote-then-local sequence produces two of our own
   writes before the watcher next ticks, and each expires after two seconds so
   that deliberately re-copying the same text still syncs.

---

## 5. Cryptographic choices

| Choice | Alternative considered | Why |
|---|---|---|
| X25519 | P-256, X448 | No invalid-curve pitfalls, no parameter validation, constant-time by construction. 128-bit security is the right target; X448's extra latency would be visible on a phone's first connect. |
| ChaCha20-Poly1305 | AES-256-GCM | Fast and constant-time without hardware support. A software AES-GCM fallback on a low-end Android device is slower *and* cache-timing vulnerable. |
| HKDF-SHA256 | Direct hashing | Domain-separated labels keep the send key, receive key, confirmation tokens, and SAS cryptographically independent despite one shared input secret. |
| Counter nonces | Random nonces | Removes birthday-collision risk entirely and makes the safety property checkable by inspection. |
| Derived device IDs | Random UUIDs | A peer cannot claim an ID it lacks the private key for, so the trust store needs no separate binding step. |
| Truncated SHA-256 for clipboard hashes | Full digest | It is a change-detection fingerprint, not a security control. 128 bits makes accidental collision impossible and halves the wire cost. |

---

## 6. Implementation notes that are load-bearing

- **All MAC and key comparisons use `Primitives.constantTimeEquals`.** A `==`
  on lists exits at the first differing byte, and that timing difference is
  enough to forge a MAC one byte at a time given enough attempts.
- **AEAD failures report one opaque code.** Distinguishing "wrong key" from
  "tampered frame" to anything that can observe the failure is an oracle.
- **`MessageType.allowedUnauthenticated` is an explicit list, not a rule.**
  Inferring it from the subsystem would mean a future message could silently
  widen the pre-auth attack surface.
- **`PermissionTier.allows` denies by default.** Adding a message type forces
  an explicit decision about which tier may send it.
- **Permission checks live on the desktop, per message.** Hiding a button on
  the phone is a usability affordance. The phone is untrusted input; the
  desktop is the boundary.
- **Trust records are built from handshake results, never from peer claims.**
  A device cannot register a public key it does not hold.
- **The beacon fingerprint is never a trust key.** It is 8 bytes and exists
  only to pre-filter the device list; using it for trust would accept anything
  able to produce a matching 64-bit prefix.

---

## 7. Reporting a vulnerability

**Do not open a public issue.** This project is a deliberate hole in a machine's
input boundary; a public report is a working exploit announcement for everyone
running it who has not yet updated.

### How to report

Use **GitHub's private vulnerability reporting** on this repository — the
Security tab, "Report a vulnerability". It creates a private thread visible only
to maintainers and needs no address to be published or maintained, which is why
it is preferred here over an email alias.

> **Maintainer action still required:** private reporting must be switched on in
> the repository settings (Settings → Code security → Private vulnerability
> reporting), and a security contact chosen for the case where a reporter cannot
> use GitHub. Until both are done, this section describes an intent rather than a
> working channel — which is a gap, and is recorded as one.

### What to include

- What an attacker gains, concretely. "A paired phone can read the clipboard" and
  "an unpaired device on the same Wi-Fi can read the clipboard" are different
  reports with different urgency.
- The position the attack requires: same LAN, an already-paired device, physical
  access to an unlocked machine, or a compromised desktop. §2 lists what is
  already accepted as out of scope, and a report that assumes one of those is
  not a vulnerability — though a report showing a *stated* mitigation does not
  actually hold very much is.
- Reproduction steps, and the commit or version you tested.

### What to expect

- Acknowledgement that the report was received and understood.
- An assessment against the threat model in §2, stated plainly — including
  "this is already accepted as out of scope, and here is why", where that is the
  honest answer.
- Credit in the release notes if you want it, and none if you do not.

### Scope

In scope: anything in this repository — the protocol, the cryptography, the
desktop service, the phone app, and the native input and clipboard paths.

Explicitly not vulnerabilities, because they are documented design decisions in
§2 and §4: a compromised desktop, a malicious app on an unlocked paired phone,
traffic analysis of packet sizes and timing, and denial of service from an
attacker already on the same LAN. Argue that one of those *decisions* is wrong
by all means — that is a design discussion rather than a disclosure.

The ranked gaps in §4 are known and published. A report that one of them exists
tells us nothing; a report that one is worse than described tells us a great
deal.
