# Brief: make the Apple Watch a first-class Remote Link client

You are implementing a new feature in the **Remote Link** repository
(`/Users/ahmed/Documents/projects/UnifiedLInk`). Read this whole brief before
writing code. Phase 0 is a go/no-go gate and must not be skipped.

---

## 1. The problem, measured

Remote Link controls a Mac or Windows PC from a phone over local Wi-Fi. There is
a watchOS app (`apps/mobile/ios/RemoteLinkWatch/`) that acts as a trackpad.

Today the watch does **not** speak the Remote Link protocol. It sends packed
input intents to the iPhone over `WCSession.sendMessageData`, and the iPhone
puts them on the session it already holds to the computer. That design is
recorded in [ADR 0004](adr/0004-apple-watch-relays-through-the-phone.md).

**The relay has been measured at ~200 ms round trip**, on-device, with:

- one message in flight at a time (no queueing — verified by narrowing the
  window from 3 to 1 and watching the figure *rise*, which ruled out queueing)
- a 12-byte packed binary payload, not a property list
- release builds on both ends
- Low Power Mode off

200 ms is roughly five pointer updates a second. The cursor is usable for
coarse pointing and nothing else. Every optimisation available inside the relay
design has already been applied.

## 2. The proposal

Give the watch its own Remote Link client: its own identity, its own pairing,
its own TCP session to the computer over Wi-Fi. Remove the iPhone from the
control path entirely.

---

## 3. Phase 0 — the go/no-go spike (do this first, do not skip)

**There is a real chance this whole approach does not help, and it is cheap to
find out.**

watchOS routes network traffic through the paired iPhone over Bluetooth whenever
that phone is reachable, because it is far more power-efficient than using the
watch's own Wi-Fi radio. There is no public API to force the watch onto its own
Wi-Fi. If that routing applies here, a direct TCP socket from the watch takes
*the same Bluetooth hop* the relay already takes, and the latency will not
improve.

**Build the smallest thing that answers this:**

1. A throwaway TCP echo server on the Mac (a 20-line Dart or Swift script is
   fine; do not add it to the shipping desktop app).
2. In the existing `RemoteLinkWatch` target, a temporary screen that opens an
   `NWConnection` to that server, sends 12 bytes, waits for 12 back, and
   displays a smoothed round-trip figure in milliseconds — the same way
   `WatchLink.roundTripMillis` is displayed today.
3. Measure under four conditions and write the numbers into this file:
   - iPhone nearby, its app in the foreground
   - iPhone nearby, its app backgrounded / screen off
   - iPhone in aeroplane mode (forces the watch onto its own Wi-Fi)
   - iPhone powered off

**Gate:** proceed to Phase 1 only if the direct TCP round trip with the iPhone
nearby is **under ~60 ms**. If it lands near 200 ms in the nearby cases and only
drops when the phone is off, then the watch is being proxied through the phone,
this design cannot fix the problem, and you should stop and report that — do not
implement Phases 1–6. Delete the spike either way.

---

## 4. What to build, if the gate passes

A Swift client in `apps/mobile/ios/RemoteLinkWatch/` that speaks the wire
protocol directly. **`docs/PROTOCOL.md` is normative**; where this brief and
that document disagree, the document wins. The Dart implementation under
`packages/` is the reference for anything the document leaves ambiguous, and it
must be treated as byte-exact truth.

### 4.1 Discovery — `Discovery.swift`

Use **Bonjour via `NWBrowser`**, service type `_remotelink._tcp`. The desktop
already advertises over Bonjour *in addition to* UDP multicast
(`apps/desktop` — `BonjourAdvertiser`).

Do **not** implement the UDP multicast beacon (`docs/PROTOCOL.md` §8). iOS and
watchOS require `com.apple.developer.networking.multicast` for multicast on real
hardware and Apple grants it by application; Bonjour is explicitly exempt. This
is the same reason the phone app has both routes — see `docs/RUNNING.md` §3
Option C.

Resolve to host and port, and surface the `deviceId` and name from the TXT
record if present; otherwise take them from the handshake.

### 4.2 Transport — `Connection.swift`

- `NWConnection` over TCP. Set `noDelay = true`. Nagle on a 22-byte cursor
  update is exactly the latency this feature exists to remove.
- Record framing: `u32 big-endian length` then that many bytes
  (`docs/PROTOCOL.md` §2). Enforce the 17 MiB cap **before allocating**.
- Frame header: fixed 20 bytes, layout in `docs/PROTOCOL.md` §3. Reference:
  `packages/rl_protocol/lib/src/frame.dart`.
- A byte stream is not a message channel. One read can carry three frames or
  half of one. Reference: `packages/rl_transport/lib/src/transport/framed_connection.dart`.

### 4.3 Crypto — `Handshake.swift`, `SessionCipher.swift`

Everything needed is in **CryptoKit** and available on watchOS:
`Curve25519.KeyAgreement`, `ChaChaPoly`, `HKDF<SHA256>`, `SHA256`.

Implement the simplified Noise XX handshake exactly as specified in
`docs/PROTOCOL.md` §6, including:

- the running transcript hash `h₀…h₃`
- **the HKDF salt frozen at `h₃` on both sides** — the document calls this out
  as the easy thing to get wrong, and the failure mode is an authentication
  error two messages later that looks nothing like the cause
- all four DH terms `ee ‖ es ‖ se ‖ ss` in that order
- the six-digit SAS from `sas_seed` (§6, *Short authentication string*)

Record encryption per §7: ChaCha20-Poly1305, RFC 8439, with the nonce counter
and replay window as the Dart side enforces them.

Reference, in order of authority: `docs/PROTOCOL.md`, then
`packages/rl_crypto/lib/src/handshake.dart`,
`packages/rl_crypto/lib/src/session_cipher.dart`,
`packages/rl_crypto/lib/src/primitives.dart`.

### 4.4 Pairing and trust — `TrustStore.swift`, pairing UI

**The watch pairs on its own.** The previous objection in ADR 0004 was that
pairing needs a six-digit SAS compared across two screens and one of them is
45 mm — but six digits is perfectly legible on a watch, and that objection was
overstated. Do not build a delegated-pairing scheme, and do not copy the
phone's private key onto the watch: the watch gets its **own** X25519 identity
and appears in the desktop's trust store as its own device.

- Identity private key and trusted peers live in the **watch Keychain**
  (`kSecAttrAccessibleAfterFirstUnlock`), mirroring `KeystoreIdentityStore` in
  `apps/mobile/lib/src/app/providers.dart`.
- Pairing UI: show the six digits large and centred, with confirm and cancel.
  This is the one screen allowed to have controls — see §5.

### 4.5 Messages — `Messages.swift`

Implement **only** what a trackpad needs. Do not port the other fifty message
types.

| Message | Code |
|---|---|
| `clientHello` | `0x0001` |
| `serverHello` | `0x0002` |
| `handshakeFinish` | `0x0003` |
| `ping` / `pong` | `0x0004` / `0x0005` |
| `mouseMove` | `0x0201` |
| `mouseButton` | `0x0203` |
| `mouseScroll` | `0x0204` |
| `deviceInfo` | `0x0901` |

Plus whatever pairing messages `0x01xx` the handshake requires — read
`packages/rl_protocol/lib/src/message_type.dart`.

Advertise **`Capabilities.mouse` only**. Read the doc comment on
`kMobileCapabilities` in `apps/mobile/lib/src/app/providers.dart` first: a
capability means "I take part in this feature", the handshake keeps the
intersection, and a bit you forget is a feature that silently never works.

Unknown message types must decode as opaque and be ignored, not crash — §5 of
the protocol document.

### 4.6 Reconnection

Jittered exponential backoff, and reconnect on wake. Reference:
`packages/rl_transport/lib/src/transport/reconnect.dart`. A watch app is
suspended constantly; assume every session is short-lived.

---

## 5. Constraints that are not negotiable

- **The UI does not change.** The trackpad screen is a full-screen dot field
  with no buttons, no icons and no status row — that is a deliberate product
  decision, not an oversight. Read `TrackpadView.swift` and preserve it. The
  gestures stay exactly as they are: drag to move, tap to click, double tap for
  a double click, hold 450 ms to press and hold for dragging or selecting text.
  Text may appear **only** when there is nothing to control, and the pairing
  screen is the sole exception.
- **The `ms` readout currently on the trackpad screen is temporary
  instrumentation.** Delete it when the work is done.
- **`packages/` may not import Flutter** (CONTRIBUTING §1) and you should not
  need to touch `packages/` at all. If you believe you do, stop and say why.
- **The phone app keeps working unchanged.** Do not regress it.
- **Do not delete the WatchConnectivity relay.** Demote it to a fallback for
  when the watch cannot reach the computer directly (off Wi-Fi, away from
  home). `WatchBridge.swift` on the phone and the Dart side in
  `apps/mobile/lib/src/features/watch/watch_bridge.dart` stay as they are; the
  watch chooses the direct path when it has one. If Phase 0 showed the relay is
  the only viable path in some conditions, this fallback is the whole reason
  those users still have a working app.
- **Signing:** the watch target's settings are written by
  `apps/mobile/ios/tool/add_watch_target.rb`, including its `TargetAttributes`
  entry. If you change target configuration, change it there too — a hand-edited
  `project.pbxproj` does not survive the next `pod install`.

---

## 6. Verification

The repository's standard is that behaviour is tested where it can be, and this
work is mostly testable without a device.

- **Swift unit tests** for the pure parts, run on the watchOS simulator: frame
  encode/decode round trips, the framing reader against split and coalesced
  reads, the key schedule, and the SAS.
- **A cross-implementation vector test is the highest-value thing you can
  write.** Generate handshake transcripts and encrypted records from the Dart
  side, check them in as fixtures, and assert the Swift implementation produces
  identical bytes. Two independent implementations of a handshake that are
  "probably compatible" is the exact shape of bug that costs days.
- **End to end:** watch simulator against the real desktop app on the same Mac.
  Pair, move the cursor, click, double click, hold and drag.
- Do not break `cd apps/mobile && flutter test`. It currently reports **12
  pre-existing failures** in `test/accessibility_test.dart`, caused by an
  unrelated uncommitted change to `test/support/semantics.dart`
  (`pipelineOwner` → `rootPipelineOwner`, which returns a null `semanticsOwner`).
  Leave those alone; do not add to them.

## 7. Deliverables

1. The Phase 0 numbers, written into this file, and a clear go/no-go.
2. The implementation, if the gate passed.
3. **A rewrite of `docs/adr/0004-apple-watch-relays-through-the-phone.md`** —
   or a superseding ADR 0005 — recording the measurement that overturned it,
   what the direct client costs, and what the fallback is for. Follow the house
   style: state the options that were rejected and why, and be specific about
   what the decision costs rather than only what it buys.
4. An update to `docs/RUNNING.md` §3c covering how to pair the watch.
