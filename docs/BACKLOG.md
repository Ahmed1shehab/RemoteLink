# RemoteLink — missing features and implementation backlog

This document is the gap inventory: everything the product is *supposed* to do
and does not yet do, written as executable tasks rather than aspirations.

It complements [ROADMAP.md](ROADMAP.md), which says *what order* the milestones
come in and *why*. This document says *what exactly to build*, *which files to
touch*, and *how you know it is done*. Where the two disagree, the roadmap owns
sequencing and this document owns detail.

Findings are derived from reading the code, not only the documentation. Several
gaps below are **not** listed in `README.md` or `ROADMAP.md` because they were
found by inspection — those are marked **(undocumented)**.

---

## 0. Conventions

Every task uses the same shape:

| Field | Meaning |
|---|---|
| **ID** | Stable identifier. Never reused, even if a task is dropped. |
| **Priority** | P0 broken now · P1 hardening · P2–P4 features · P5 expansion |
| **Size** | S ≤ 1 day · M ≤ 3 days · L ≤ 2 weeks · XL > 2 weeks |
| **Blocks / Blocked by** | Task IDs. Determines the order in §12. |
| **Files** | Where the work lands. Paths are repo-relative. |
| **Spec** | What to build, concretely enough to implement without further design. |
| **Acceptance** | Observable conditions. Each is checkable, not a judgement call. |
| **Tests** | The specific tests that must exist and pass. |
| **Risks** | What is likely to go wrong, and what was already decided against. |

Two standing rules inherited from the existing codebase and not restated per
task:

1. **Nothing below `apps/` imports Flutter.** Every package must stay runnable
   under `dart test` with no engine. A task that needs a plugin puts the plugin
   binding in `apps/` and the pure logic in `packages/`.
2. **Wire codes are append-only.** No task may reuse or renumber an existing
   `MessageType` code. New fields are appended to payloads; decoders ignore
   trailing bytes (`docs/PROTOCOL.md` §5).

---

## 1. Gap inventory at a glance

### 1.1 Declared on the wire, decodes as opaque

`packages/rl_protocol/lib/src/codec.dart:182–197` routes fifteen message types
to `UnknownMessage`. They have reserved codes and no payload classes:

| Subsystem | Types | Task |
|---|---|---|
| `0x06xx` screen streaming | `screenStreamStart`, `screenStreamStop`, `screenFrame`, `screenConfigure`, `screenTopology` | RL-300 |
| `0x07xx` file transfer | `fileOffer`, `fileAccept`, `fileChunk`, `fileComplete`, `fileAbort` | RL-400 |
| `0x0Axx` presentation | `slideCommand`, `laserPointer`, `presentationBlank` | RL-500 |
| `0x0Bxx` gamepad | `gamepadState`, `motionState` | RL-510 |

### 1.2 Payload class exists, decodes fine, nothing handles it **(undocumented)**

These are the sharper gap: the codec produces a real typed message, the
permission tier permits it, and then `CommandDispatcher.dispatch` falls through
to `default:` and increments `_unsupported`. A phone that sent one would see
silence and no error.

| Message | Decoded at | Handler | Task |
|---|---|---|---|
| `GestureZoom` | `codec.dart:144` | none | RL-200 |
| `GestureRotate` | `codec.dart:145` | none | RL-200 |
| `GestureSwipe` | `codec.dart:146` | none | RL-200 |
| `PenInput` | `codec.dart:147` | none | RL-201 |
| `BrightnessCommand` | `codec.dart:164` | none | RL-202 |
| `ClipboardSyncToggle` | `codec.dart:158` | none | RL-203 |
| `DeviceRename` | `codec.dart:175` | none | RL-204 |
| `PermissionRequest` | `codec.dart:177` | none | RL-205 |
| `SystemStatus` | `codec.dart:171` | never *produced* | RL-206 |
| `RunCommand` | `codec.dart:170` | refuses — no registry | RL-207 |
| `ResumptionTicket` / `ResumeSession` | `codec.dart:128–129` | never produced | RL-102 |

### 1.3 Security gaps

Ranked in `SECURITY.md` §4 and reproduced here with task IDs:

| # | Gap | Task |
|---|---|---|
| 1 | Desktop private key sits in a plain file, not Keychain/DPAPI | RL-100 |
| 2 | `ReplayWindow` implemented but unused — no UDP channel | RL-103 |
| 3 | Mobile trust store has no integrity MAC | RL-101 |
| 4 | No session resumption | RL-102 |
| 5 | Revoked device reconnects forever on the backoff curve | RL-104 |
| 6 | `GetClipboardSequenceNumber` echo-suppression race | RL-105 |

### 1.4 Native backend gaps

| Capability | macOS | Windows | Linux | Task |
|---|---|---|---|---|
| Input injection | done | done | missing | RL-600 |
| Clipboard text | done | done | missing | RL-600 |
| Clipboard images | deferred (`macos_clipboard.dart:255`) | deferred (`win32_clipboard.dart:141`) | missing | RL-410 |
| Media transport | done | missing (WinRT) | missing | RL-520 |
| Now-playing metadata | partial (Music/Spotify only) | missing | missing | RL-520 |
| Screen capture | missing | missing | missing | RL-301 |
| Multi-monitor enumeration | missing (single `virtualBounds`) | missing | missing | RL-302 |
| Brightness | missing | missing | missing | RL-202 |

### 1.5 Application and delivery gaps **(mostly undocumented)**

| Gap | Task |
|---|---|
| Both `widget_test.dart` files are stale `flutter create` scaffolding referencing a nonexistent `MyApp` — `flutter test` does not compile in either app | RL-000 |
| No CI. No `.github/` directory exists | RL-001 |
| QR pairing UI: protocol done, display widget and scanner missing | RL-106 |
| No mobile settings screen (rename device, forget computer, tier request, sync toggles) | RL-700 |
| No desktop diagnostics panel; `CommandDispatcher` already counts applied/denied/unsupported and nothing reads them | RL-701 |
| No custom-command registry storage or editor UI | RL-207 |
| No latency measurement harness | RL-107 |
| No packaging, code signing, notarisation, installer, or update channel | RL-002 |
| No localisation; every string is a hard-coded English literal | RL-702 |
| No accessibility pass on either app | RL-703 |
| Wake-on-LAN | RL-530 |
| Notification mirroring | RL-540 |
| No structured crash/error reporting or log export | RL-704 |

---

## 2. P0 — broken now

These are not features. They are things that are currently wrong.

---

### RL-000 — Replace the stale scaffolding widget tests

**Priority** P0 · **Size** S · **Blocks** RL-001

**Files**
- `apps/desktop/test/widget_test.dart`
- `apps/mobile/test/widget_test.dart`

**Why.** Both files are the untouched `flutter create` counter test. Each calls
`tester.pumpWidget(const MyApp())`, and `MyApp` does not exist in either app —
the desktop entry point exports `RemoteLinkDesktopApp` and the mobile one its
own root widget. `flutter test` therefore fails to *compile* in both apps.
`README.md` advertises `melos run test:flutter` as part of the workflow, so the
documented command is currently broken.

**Spec.**
1. Delete both counter tests.
2. Desktop: add a widget test that pumps `RemoteLinkDesktopApp` inside a
   `ProviderScope` with `desktopServiceProvider` overridden by a fake, and
   asserts the status card renders the "not running" state without throwing.
3. Mobile: add the equivalent against the device-list screen with
   `discoveryProvider` and `trustStoreProvider` overridden, asserting the empty
   state renders and that the discovery-unavailable explanation appears when
   `discoveryOperationalProvider` yields `false`.
4. Extract the provider overrides into `test/support/fakes.dart` in each app so
   later UI tasks (RL-106, RL-700, RL-701) reuse them rather than each inventing
   its own fake service.

**Acceptance.**
- `flutter test` exits zero in `apps/desktop` and `apps/mobile`.
- `./tool/verify.sh` runs the Flutter tests, not only the pure-Dart ones.
- No test references `MyApp`.

**Tests.** The two tests above are themselves the deliverable.

**Risks.** `DesktopService` constructs native backends in its field
initialisers, so a fake must be injected at the provider boundary — do not try
to construct the real service in a test. If `desktopServiceProvider` is not
currently overridable in a way that permits this, widening it is in scope.

---

### RL-001 — Continuous integration

**Priority** P0 · **Size** M · **Blocked by** RL-000

**Files**
- `.github/workflows/ci.yml` (new)
- `tool/verify.sh` (extend)

**Why.** There is no CI at all. Every guarantee in `README.md` — formatting,
analysis, the adversarial protocol tests, the machine-in-the-middle test — is
enforced only by whoever remembers to run `./tool/verify.sh`. A repository that
positions itself on tested correctness needs the tests to be gating.

**Spec.**
1. Matrix over `macos-latest` and `windows-latest`. Ubuntu is added by RL-600.
2. Job steps: `flutter pub get` at the workspace root · `dart format --output
   none --set-exit-if-changed .` · `dart analyze --fatal-infos` · `dart test`
   for the five pure-Dart packages · `flutter test` for both apps.
3. Separate job that runs `./tool/bootstrap_platforms.sh` then
   `flutter build macos --debug` (macOS) and `flutter build windows --debug`
   (Windows), proving the platform runners still generate and compile. Do not
   commit the generated runner directories — the README is explicit that they
   are not tracked.
4. Coverage: `dart test --coverage`, upload as an artifact. Do not gate on a
   percentage — gate on the specific suites in RL-108 instead.
5. Cache `~/.pub-cache` keyed on `pubspec.lock`.

**Acceptance.**
- A pull request that breaks formatting, analysis, or any test is marked failed.
- A green run on a clean checkout takes under ten minutes.
- The macOS build job proves `bootstrap_platforms.sh` still works, since it is
  the documented first step and nothing else exercises it.

**Risks.** `flutter build windows` needs the Visual Studio C++ workload; use the
`windows-latest` image's preinstalled toolchain rather than installing one.
FFI-dependent tests must be skipped by platform, not by hope — tag them.

---

### RL-104 — Tell a revoked device it was revoked

**Priority** P0 · **Size** S · **Security gap 5**

**Files**
- `packages/rl_transport/lib/src/transport/server.dart`
- `packages/rl_transport/lib/src/transport/client.dart`
- `packages/rl_transport/test/transport_test.dart`

**Why.** `SECURITY.md` §4.5 documents this and rates the fix as available and
cheap. The server closes the socket on `security.peer_revoked`; the client reads
a generic `transport.handshake_closed`, which `isRetryable` treats as
retryable, so it reconnects forever. Observed in the loopback test run: six
attempts in the first two seconds, then the backoff curve indefinitely. Nothing
leaks, but it drains the phone's battery and lets a removed device keep a server
slot churning.

**Spec.**
1. Revocation is checked *after* the peer is authenticated, so the server holds
   established session keys at that point. Before closing, send a frame of type
   `error` carrying `ProtocolErrorCode.revoked`.
2. Send it over the established session so the payload is encrypted; the peer is
   authenticated by then and there is no reason to leak the reason in plaintext.
3. Client: on receiving an `error` whose code returns `false` from
   `isRetryable`, stop the reconnect supervisor, transition `ClientState` to a
   new terminal `rejected` state carrying the code, and do not schedule another
   attempt.
4. Mobile UI: the device list shows "This computer removed your access" against
   that entry with a "Pair again" action, which clears the local trust record
   and starts a fresh pairing.
5. Same treatment for the other non-retryable codes so the mechanism is general,
   not a special case for revocation.

**Acceptance.**
- After revocation, the client makes exactly one further connection attempt and
  then stops. Verified by counting `connect` calls in the loopback test.
- The mobile device list explains why, and offers re-pairing.
- The server's session count returns to zero and stays there.

**Tests.**
- `transport_test.dart`: revoke a paired peer mid-session, assert the client
  reaches `rejected` and that no further connection attempt occurs within 10 s
  of fake-clock time.
- Assert the error frame is encrypted — a plaintext `revoked` on the wire is a
  regression.

**Risks.** The handshake framing changes slightly, which is why `SECURITY.md`
deferred this to the milestone-2 transport work. Land it before RL-102 so that
resumption is designed against the final framing rather than being reworked.

---

## 3. P1 — Milestone 2 hardening

Nothing in this section adds a button. It is what makes milestone 1 trustworthy.

---

### RL-100 — Private key into the OS keystore

**Priority** P1 · **Size** M · **Security gap 1**

**Files**
- `packages/rl_crypto/lib/src/identity.dart` (no change — it already exposes
  `extractPrivateKey` with the storage contract documented)
- `apps/desktop/lib/src/app/providers.dart`
- `apps/desktop/lib/src/domain/secret_store.dart` (new)
- `apps/desktop/macos/Runner/*.entitlements`
- `apps/mobile/lib/src/app/providers.dart` (`FileIdentityStore` fallback)

**Why.** The single largest documented gap. The desktop identity — the key every
trust relationship on the network is rooted in — is a base64 blob in a file with
`chmod 600`. The mobile app already does this correctly via
`KeystoreIdentityStore`.

**Spec.**

*Interface.* Define `SecretStore` with `read(String key)`, `write(String key,
String value)`, `delete(String key)`, and a `bool get isHardwareBacked`. Mirror
the shape of the mobile `IdentityStore` so the two can converge later.

*macOS.* Keychain via `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate`
through `dart:ffi` against `Security.framework`, consistent with ADR 0003's
preference for FFI over channels. Attributes: `kSecClassGenericPassword`,
service `com.remotelink.desktop`, account `identity.private`, accessibility
`kSecAttrAccessibleAfterFirstUnlock` so the service survives a reboot into a
locked screen — which is the normal state for a machine acting as a server.

The blocker recorded in `apps/mobile/lib/src/app/providers.dart:36-42` is real
and must be handled rather than rediscovered: reaching the Keychain from a
sandboxed app needs a `keychain-access-groups` entitlement whose
`$(AppIdentifierPrefix)` resolves from a provisioning profile, and requiring one
breaks `flutter run` under ad-hoc signing. Resolution: use the entitlement in
`Release.entitlements` only; `DebugProfile.entitlements` keeps the file store.
Selection is made at run time from `isHardwareBacked`, and the desktop UI shows
which store is in use so a developer build is never mistaken for a shipping one.

*Windows.* DPAPI via `CryptProtectData` / `CryptUnprotectData` (`crypt32.dll`)
with `CRYPTPROTECT_LOCAL_MACHINE` **unset** — user scope, so another account on
the same machine cannot unprotect it. Ciphertext goes to
`%LOCALAPPDATA%\RemoteLink\identity.bin`. Add an entropy parameter derived from
a constant application salt so a stolen blob is not decryptable by another
DPAPI-using process running as the same user.

*Migration.* On first launch after upgrade: if the legacy file exists and the
keystore entry does not, read the file, write the keystore, verify by reading
back and comparing the derived `DeviceId`, and only then delete the file. If any
step fails, keep the file and log a warning — a failed migration must never
destroy the identity, because losing it means every paired phone must re-pair.

**Acceptance.**
- On macOS release builds the key appears in `security dump-keychain` under the
  service name and no plaintext key file remains.
- On Windows the file is DPAPI ciphertext; copying it to another user account
  and starting the app there produces a *new* identity rather than a decrypt.
- Migration from a milestone-1 install preserves the `DeviceId`, so already-
  paired phones reconnect with no prompt.
- `flutter run` still works on a machine with no provisioning profile.
- `SECURITY.md` §4 gap 1 is rewritten to describe what now happens.

**Tests.**
- Round-trip test per platform, tagged so it is skipped elsewhere.
- Migration test: seed a legacy file, run the resolver, assert the `DeviceId` is
  unchanged and the file is gone.
- Failure-path test: keystore write throws → the legacy file survives and the
  identity still loads.

**Risks.** Keychain prompts. An unsigned or re-signed binary changes the ACL
owner and macOS will prompt on read, which for a login-item service means a
dialog nobody is present to answer. Test explicitly across a rebuild-and-relaunch
cycle, not only a fresh install.

---

### RL-101 — Integrity MAC over the mobile trust store

**Priority** P1 · **Size** S · **Security gap 3** · **Blocked by** RL-100

**Files**
- `apps/mobile/lib/src/app/providers.dart` (`persistTrustStore`, `trustStoreProvider`)
- `packages/rl_crypto/lib/src/trust_store.dart`

**Why.** The stored contents are only public keys, so confidentiality is
incidental — integrity is the whole issue. An attacker able to rewrite that JSON
could substitute their own public key for a trusted computer's, and the phone
would connect to them with **no prompt at all**, because the trust store is
exactly what suppresses the pairing flow.

**Spec.**
1. Derive a store key from the device identity, not a new secret:
   `k_store = HKDF(ikm = identity_private, salt = "rl1 trust store", info =
   "mac v1", 32)`. This keeps the number of things that must be protected at
   one — RL-100's keystore already protects the identity.
2. Persist `{"v":1,"peers":[…],"mac":"<base64>"}` where the MAC is
   HMAC-SHA256 over the exact serialised `peers` array bytes, computed before
   the envelope is assembled so verification does not depend on JSON key order.
3. On load: verify with `Primitives.constantTimeEquals`. On mismatch, **do not
   silently discard and do not silently accept**. Load zero peers, set a
   `trustStoreTampered` flag, and have the UI state that saved computers could
   not be verified and must be paired again. Silent discard trains the user to
   re-pair on demand, which is the exact behaviour an attacker wants.
4. Version the envelope so a future format change is a migration rather than a
   tamper alarm. A file with no `v` field is a milestone-1 store: accept it once,
   rewrite it with a MAC, and log the upgrade.

**Acceptance.**
- Flipping one byte in the persisted store produces the tamper state, not a
  connection.
- A legitimate upgrade from an unMACed store keeps every paired computer.
- The MAC key never leaves `rl_crypto`.

**Tests.**
- Round-trip, tamper-detection, and legacy-upgrade tests in
  `packages/rl_crypto/test/trust_store_test.dart` (new file — there is currently
  no test for the trust store at all).

**Risks.** Reinstalling the app regenerates the identity and therefore the MAC
key, so the store fails verification. That is correct — a new identity means
every peer must re-pair anyway — but the message must say so rather than
implying an attack.

---

### RL-102 — Session resumption

**Priority** P1 · **Size** M · **Security gap 4** · **Blocked by** RL-104

**Files**
- `packages/rl_crypto/lib/src/handshake.dart`
- `packages/rl_crypto/lib/src/session_cipher.dart` (`resumptionSecret` exists)
- `packages/rl_transport/lib/src/transport/handshake_driver.dart`
- `packages/rl_transport/lib/src/transport/server.dart`, `client.dart`
- `docs/PROTOCOL.md` (new §6.1)

**Why.** `ResumptionTicket` and `ResumeSession` have wire codes and decoders;
`SessionKeys.resumptionSecret` is derived by the key schedule
(`PROTOCOL.md` §6). Nothing seals or presents a ticket, so every reconnect —
including every Wi-Fi handoff and every screen unlock — is a full five-record,
four-X25519 handshake.

**Spec.**

*Ticket key.* The server holds a rotating symmetric ticket key, generated at
startup, kept **in memory only**, rotated hourly with the previous generation
retained for one further hour. Never persisted: a resumption ticket that
survives a service restart is a long-lived bearer credential, and the cost of
losing them on restart is one full handshake.

*Ticket contents*, sealed with ChaCha20-Poly1305 under the ticket key:
peer static public key · granted `PermissionTier` · issue time · the
`resumptionSecret` · a random 16-byte ticket ID. Associated data is the ticket
key generation number, so a stale generation fails the tag rather than
decrypting into a wrong-key state.

*Issue.* After a successful handshake and after pairing completes, the server
sends `ResumptionTicket`. Issue a fresh one on each successful resumption too,
so a client that reconnects often never runs out and no single ticket is
long-lived.

*Present.* The client sends `ResumeSession` in place of `ClientHello`, carrying
the ticket, a fresh client ephemeral, and a random nonce. The server unseals,
checks age against a 24-hour cap, checks the peer is still trusted and not
revoked (RL-104 must already be in place, or a revoked peer resumes around the
check), and derives new directional keys as
`HKDF(ikm = resumptionSecret ‖ X25519(e_c, e_s), salt = transcript,
info = "rl1 resume …")`.

The ephemeral exchange is **not** optional. Deriving purely from the
`resumptionSecret` would give a resumed session no forward secrecy, which is
precisely the property the full handshake was designed around.

*Fallback.* Any failure — unknown generation, bad tag, expired, revoked — is
answered with an ordinary `ServerHello`, and the client continues into the full
handshake. A failed resumption must cost one round trip, never a dropped
connection.

*Anti-replay.* One ticket, one use: the server keeps the ticket IDs consumed
within the current and previous generation and rejects repeats.

**Acceptance.**
- Reconnect completes in one round trip and under 10 ms on loopback, versus the
  measured full-handshake baseline.
- A replayed ticket is rejected and falls back to the full handshake.
- A revoked peer cannot resume.
- Killing and restarting the server invalidates all tickets, and every client
  recovers via full handshake with no user-visible failure.
- `PROTOCOL.md` gains a normative §6.1 with the resumption key schedule.

**Tests.**
- `handshake_test.dart`: resume path end to end in memory; assert the derived
  keys differ from the original session's.
- Replay test; expiry test using the injectable `Clock`; generation-rotation
  test; forward-secrecy test asserting that compromising the `resumptionSecret`
  alone does not yield the resumed session keys without the ephemeral.

**Risks.** This is the task most likely to introduce a subtle key-schedule
mismatch. Follow the discipline `PROTOCOL.md` §6 already calls out: freeze the
salt at a single defined transcript point on both sides, and add a test that
fails loudly if the two sides derive different keys rather than surfacing as an
authentication error two messages later.

---

### RL-103 — UDP side-channel for lossy input

**Priority** P1 · **Size** L · **Security gap 2** · **Blocked by** RL-102

**Files**
- `packages/rl_transport/lib/src/transport/datagram_channel.dart` (new)
- `packages/rl_transport/lib/src/transport/session.dart`
- `packages/rl_crypto/lib/src/session_cipher.dart` (`ReplayWindow` — already
  implemented and tested, currently unused)
- `docs/PROTOCOL.md` (new §10)

**Why.** Two reasons, and the second is the load-bearing one. Latency: a large
clipboard payload or, later, a video frame occupies the TCP stream and every
cursor delta queues behind it — head-of-line blocking that the user sees as
stutter. Security: `ReplayWindow` exists precisely for this channel, and
`SECURITY.md` §4.2 warns that shipping the datagram path without wiring it in
makes captured input replayable.

**Spec.**
1. `MessageType.isLossy` already identifies the eligible set: `mouseMove`,
   `mouseMoveAbsolute`, `gestureZoom`, `gestureRotate`, `penInput`,
   `screenFrame`, `gamepadState`, `motionState`, `laserPointer`. Route exactly
   that set to the datagram channel and nothing else.
2. Same session keys, **different HKDF labels** — `"rl1 dgram c2s"` /
   `"rl1 dgram s2c"` — so a datagram can never be replayed into the TCP stream
   or vice versa.
3. The nonce counter is **explicit** on this channel: 8 bytes on the wire before
   the ciphertext. The TCP channel's implicit counter works only because TCP
   delivers in order; UDP does not, so the receiver must be told which counter
   to use. This is the one place the design deliberately departs from
   `PROTOCOL.md` §7 and the reason must be documented there.
4. Receiver: `ReplayWindow` (64 entries, already implemented) rejects repeats
   and anything below the window. Rejections are counted, not logged per packet
   — a flood must not become a log-write amplification attack.
5. Channel establishment: after the TCP session is established, both sides bind
   an ephemeral UDP port and exchange it over the encrypted TCP channel. Never
   over discovery, and never a fixed port.
6. Path validation before use: send a `ping` over UDP, require a `pong` within
   500 ms, retry twice, then mark the datagram path unavailable and keep
   everything on TCP. Networks that block UDP between wireless clients are
   common and must degrade silently.
7. Continuous liveness: if no datagram is acknowledged for 3 s while traffic is
   flowing, fall back to TCP and re-probe every 30 s.
8. MTU: cap the datagram payload at 1200 bytes so nothing fragments on a typical
   1500-byte path. A lossy message exceeding it goes over TCP instead — with the
   `screenFrame` case explicitly deferred to RL-300, which needs its own
   fragmentation scheme.

**Acceptance.**
- Cursor latency under a concurrent 5 MB clipboard transfer stays within 20% of
  its idle value. Measured with RL-107, which is why that task should land
  first even though it is listed after.
- A captured datagram replayed later is dropped, and the drop is counted.
- On a network that blocks UDP the session works identically over TCP, with the
  fallback visible in diagnostics.
- Sequence-number wrap closes the connection rather than repeating a nonce, as
  `PROTOCOL.md` §7 requires of the TCP channel.

**Tests.**
- `transport_test.dart`: reordered delivery, duplicate delivery, delivery of a
  datagram older than the window, and a mid-session UDP blackhole that must
  trigger fallback within 3 s of fake-clock time.
- A test asserting a datagram sealed with the datagram key is rejected when fed
  into the TCP channel.

**Risks.** NAT and firewall behaviour on real networks is the hard part, not the
crypto. Every path here must degrade to TCP rather than fail. Do not let the
datagram channel become required for correctness — it is an optimisation, and
any code that assumes it exists is a bug.

---

### RL-105 — Close the clipboard echo-suppression race

**Priority** P1 · **Size** S · **Security gap 6**

**Files**
- `apps/desktop/lib/src/domain/clipboard_sync.dart`
- `packages/rl_native/lib/src/windows/win32_clipboard.dart`

**Why.** Echo suppression compares `GetClipboardSequenceNumber` before and after
our own write. A genuine clipboard change landing inside that window is
misattributed as our echo and dropped. Sub-millisecond and the failure is a
missed sync rather than a wrong one — but it is real, and it is the kind of bug
that surfaces as "sometimes it just doesn't sync" with no reproduction.

**Spec.**
1. Stop inferring authorship from the counter. Track the content hash we wrote,
   and treat an observed change as ours only when the sequence number advanced
   *and* the current content hashes to the value we wrote.
2. Keep the last three self-written hashes, not one: a rapid remote-then-local
   sequence can produce two of our own writes before the watcher next ticks.
3. Expire self-write records after 2 s so a hash we wrote long ago cannot
   suppress a genuine re-copy of the same text — copying the same string twice
   is normal and must still sync.
4. Apply the same treatment to the macOS `changeCount` path, which has the
   identical structure.

**Acceptance.**
- A local copy performed within 1 ms of an applied remote update is still
  detected and broadcast.
- Copying identical text twice in a row syncs both times.
- No sync loop under a script that alternates local and remote writes 100 times.

**Tests.**
- A fake `ClipboardBackend` driving the race deterministically in
  `apps/desktop/test/clipboard_sync_test.dart` (new — none exists today).

---

### RL-106 — QR pairing UI

**Priority** P1 · **Size** M

**Files**
- `apps/desktop/lib/src/ui/pairing_qr.dart` (new)
- `apps/desktop/lib/src/ui/home_screen.dart`
- `apps/mobile/lib/src/features/pairing/qr_scanner_screen.dart` (new)
- `apps/mobile/lib/src/features/pairing/pairing_screen.dart`
- `apps/mobile/pubspec.yaml`, `apps/mobile/ios/Runner/Info.plist`,
  `apps/mobile/android/app/src/main/AndroidManifest.xml`

**Why.** The protocol half is finished and tested: `PairingPayload` round-trips
through its URI form and `DesktopService.pairingPayload` builds it with the full
static public key. What is missing is a widget that renders it and a scanner
that reads it. `SECURITY.md` §3 explains why this matters — QR pairing removes
the machine-in-the-middle window entirely rather than merely making it visible,
because the phone learns the real static key over an optical channel before the
handshake starts.

Milestone 1 deliberately shipped numeric comparison alone rather than a QR the
phone could not read, on the principle that half a security flow is worse than
none. This task closes it.

**Spec.**

*Desktop.* A "Pair a phone" button opens a sheet rendering
`pairingPayload(host: …).toUri()` as a QR code, using `localAddresses.first` as
the host with a dropdown when more than one address exists — a Docker or VPN
adapter can sort first and be unreachable from the phone. Below the code: the
six-digit fallback path and the host and port as selectable text. The QR
refreshes if the bound port or address changes.

*Mobile.* A camera button on the pairing screen opens the scanner. On a decoded
`remotelink://` URI: parse, reject anything malformed without connecting, and
connect directly to the embedded host and port with `expectedServerKey` set to
the scanned public key — the parameter already exists on
`HandshakeDriver.runClient` and is the entire point of the flow.

*The security-critical part.* When `expectedServerKey` is supplied, a mismatch
is a **hard failure with no fallback to numeric comparison**. Silently degrading
would reintroduce exactly the attack QR pairing exists to prevent. The message
must say the computer presented a different identity than the code, and offer
only "Cancel".

*Permissions.* `NSCameraUsageDescription` on iOS and `android.permission.CAMERA`
on Android, both worded for what the camera is used for. Denial falls back to
the numeric flow with an explanation, never a dead button.

**Acceptance.**
- Scanning pairs with no digits typed on either device.
- A QR whose key does not match the server's actual static key fails closed.
- A malformed or non-RemoteLink QR is rejected without a connection attempt.
- Camera denial still leaves numeric pairing reachable.
- Works on a network where discovery is blocked, since the URI carries the
  address — this is the flow's second reason to exist.

**Tests.**
- `PairingPayload` URI parsing: valid, truncated, wrong scheme, oversized,
  wrong-length key. Adversarial input, consistent with the existing protocol
  test style.
- A widget test for the mismatch dialog asserting no "continue anyway" affordance
  is present.

**Risks.** Choose one maintained QR package for each direction and pin it.
Camera plugins are a common source of Android build breakage; the CI build job
from RL-001 is what catches that.

---

### RL-107 — Latency measurement harness

**Priority** P1 · **Size** M

**Files**
- `tool/latency_harness/` (new Dart package, workspace member)
- `docs/PERFORMANCE.md` (new)

**Why.** The roadmap's milestone-2 exit criterion is "p99 cursor latency under
10 ms on a quiet 5 GHz network, and reconnect under 2 s after a Wi-Fi handoff".
Neither number can currently be produced. Every latency claim in the repository
is reasoned rather than measured, and RL-103's acceptance depends on a
before-and-after comparison that needs this to exist first.

**Spec.**
1. A headless harness that acts as a client, connects to a running desktop
   service, and drives synthetic input.
2. **End-to-end mode.** Send `mouseMoveAbsolute` to a known coordinate, then
   read the cursor position back through the platform API, timestamping both.
   This measures what the user feels — network, dispatch, and injection — rather
   than only the round trip.
3. **Transport mode.** `ping`/`pong` RTT, isolating the network from injection.
4. Report p50, p95, p99, p999 and max over ≥ 10,000 samples at 120 Hz. Percentiles
   only; a mean hides exactly the tail that is visible as stutter.
5. Load profiles: idle · concurrent 5 MB clipboard transfer · concurrent file
   transfer once RL-400 lands · concurrent screen stream once RL-300 lands.
6. Reconnect timing: kill the TCP connection, measure to the next established
   session. Report full-handshake and resumed figures separately after RL-102.
7. JSON output, and a `--compare baseline.json` mode that fails on a regression
   beyond a stated threshold so CI can gate on it later.

**Acceptance.**
- Produces the two milestone-2 exit numbers.
- Reproducible within 10% across runs on the same network.
- `docs/PERFORMANCE.md` records a baseline with the hardware and network stated
  — a latency figure without its conditions is not a measurement.

**Risks.** Reading the cursor position has its own cost, which must be
characterised and subtracted, or the harness measures itself. Calibrate by
timing the read against a local no-op move first.

---

### RL-108 — Test coverage for the untested surface

**Priority** P1 · **Size** M · **Blocked by** RL-000

**Files**
- `packages/rl_crypto/test/trust_store_test.dart` (new)
- `packages/rl_crypto/test/pairing_test.dart` (new)
- `packages/rl_transport/test/discovery_test.dart` (new)
- `apps/desktop/test/dispatcher_test.dart` (new)
- `apps/desktop/test/clipboard_sync_test.dart` (new)

**Why.** Coverage today is concentrated in `rl_protocol` and `rl_crypto`'s
handshake and cipher, which is the right instinct — that is where correctness is
hardest to eyeball. But several security-relevant components have no test at
all. `TrustStore` decides whether pairing is required. `PairingCoordinator` owns
the three-attempt, fifteen-minute rate limit that `SECURITY.md` cites as the
defence against blind SAS guessing. `CommandDispatcher` is described in its own
header as "the security boundary of the desktop app" and has no test asserting
that the boundary holds.

**Spec.**

*Trust store.* Upsert, lookup by ID and by public key, revocation semantics,
`activePeers` excluding revoked entries, and persistence round-trip.

*Pairing coordinator.* Three failures then lockout; lockout expiry on the
injectable `Clock`; **lockouts are per-peer, not global** — `SECURITY.md` §3
states one hostile device must not be able to lock the user out of pairing their
own phone, and nothing currently proves it.

*Discovery.* Beacon encode/decode round-trip; the `RLNK` magic rejecting foreign
datagrams in one comparison; truncated and oversized datagrams; `goodbye`
removing an entry immediately; a `query` answered unicast to the asker rather
than to the group.

*Dispatcher.* A table-driven test over the full `MessageType` × `PermissionTier`
matrix asserting `dispatch` returns the expected allow/deny for every
combination. This is the highest-value test in the list: it turns
`PermissionTier.allows` from a switch someone must remember to update into a
contract with a failing test when they do not.

*Clipboard sync.* The race from RL-105, plus concealed-content handling, plus
the deterministic conflict resolution in `remoteWins`.

**Acceptance.**
- Every security-relevant decision point has a test that fails when the decision
  is inverted. Verify by mutation: flip the condition, confirm red.
- Adding a `MessageType` without updating `PermissionTier.allows` fails the
  dispatcher matrix test.

---

## 4. P2 — unhandled messages that already decode

Small tasks, grouped because each is the same shape: a typed message arrives,
`CommandDispatcher` has no case, and it is silently counted as unsupported.

---

### RL-200 — Gesture messages: zoom, rotate, swipe

**Priority** P2 · **Size** M

**Files**
- `packages/rl_native/lib/src/input_backend.dart` (extend the interface)
- `packages/rl_native/lib/src/macos/macos_input.dart`
- `packages/rl_native/lib/src/windows/win32_input.dart`
- `apps/desktop/lib/src/domain/command_dispatcher.dart`
- `apps/mobile/lib/src/features/input/touchpad_screen.dart`

**Spec.**
1. Add `magnify(double delta)`, `rotate(double degrees)`, and
   `swipe(int fingerCount, SwipeDirection direction)` to `InputBackend`, with
   no-op defaults on `UnsupportedInputBackend`.
2. macOS: `CGEventCreate` with `kCGEventTypeMagnify` / `kCGEventTypeRotate`, and
   `NSEventTypeSwipe` for three- and four-finger swipes so Mission Control and
   Spaces respond. Requires extending `coregraphics_ffi.dart`.
3. Windows: there is no direct synthetic-gesture path. Map to the shortcut a
   user would press — pinch to `Ctrl` + wheel, three-finger swipe to `Win`+`Tab`
   / `Win`+`Ctrl`+arrow. Document the mapping as a deliberate approximation
   rather than presenting it as native gesture injection.
4. Dispatcher: add the three cases and route them.
5. Mobile: wire the existing touchpad's scale and rotation gesture recognisers,
   which currently produce nothing. Send at most 120 Hz; these are already
   `isLossy` and therefore coalesced and datagram-eligible under RL-103.
6. Advertise a `Capabilities.gestures` bit so a phone does not offer pinch-zoom
   against a desktop that will approximate it badly.

**Acceptance.** Pinching on the phone zooms in Preview and Photos on macOS and
in a browser on Windows; three-finger swipe opens Mission Control / Task View;
rotation turns an image in Preview.

**Risks.** macOS gesture events are less documented than mouse and keyboard
events and behave differently across applications. Test against at least three
apps per platform before claiming support.

---

### RL-201 — Pen and stylus input

**Priority** P2 · **Size** M · **Blocked by** RL-200

**Spec.** Extend `InputBackend` with `penEvent({double x, double y, double
pressure, double tiltX, double tiltY, bool inContact})`. Windows: the Pointer
Injection API (`InitializeTouchInjection` / `InjectSyntheticPointerInput`) —
`SendInput` cannot express pressure. macOS: `CGEventCreateMouseEvent` with the
tablet-pressure fields set. Mobile: expose a pen mode on the touchpad that reads
`PointerEvent.pressure` and stylus tilt where the platform provides it.

**Acceptance.** Pressure variation produces visible stroke-width variation in a
drawing application on each platform.

**Risks.** Lowest user demand of anything in this section. Sequence it last
within P2 unless a concrete use case appears.

---

### RL-202 — Display brightness

**Priority** P2 · **Size** M

**Spec.** `BrightnessCommand` decodes and nothing handles it. Add
`BrightnessBackend` alongside `MediaBackend` — the mechanisms have nothing in
common with input, the same reasoning that already keeps media separate.
macOS: `DisplayServices` private symbols work but are private; prefer
synthesised brightness media keys via `CGEvent`, consistent with how
`macos_media.dart` already handles transport control, and fall back to
`osascript` key codes 144/145. Windows: `SetMonitorBrightness` from `dxva2.dll`
for DDC/CI-capable external monitors, and WMI `WmiSetBrightness` for laptop
panels — a single machine may need both. Advertise `Capabilities.brightness`
only when a working path is detected, so the phone does not show a dead slider.

**Acceptance.** The slider changes brightness on a MacBook panel, a Windows
laptop panel, and a DDC/CI external monitor. Where none is available the control
is absent, not inert.

---

### RL-203 — Clipboard sync toggle

**Priority** P2 · **Size** S

**Spec.** `ClipboardSyncToggle` decodes and is dropped. Route it to
`ClipboardSyncService`, per session rather than globally — one phone disabling
sync must not disable it for another. Persist the choice against the trust
record so it survives a reconnect, and surface it as a switch in the mobile
clipboard tab and in the desktop's per-device row.

**Acceptance.** Toggling off stops both directions for that device only, and
survives a reconnect.

---

### RL-204 — Device rename

**Priority** P2 · **Size** S

**Spec.** `DeviceRename` decodes and is dropped. Handle it by updating the
`TrustedPeer` name, persisting, and reflecting it in the device list. Cap at 64
characters, reject control characters and anything that renders as empty after
trimming — this string is displayed in the desktop UI and must not be able to
spoof another device's row or inject terminal escapes into logs. Expose rename
in both apps' device lists.

**Acceptance.** Renaming from either side updates both and persists. A name of
1,000 characters, a name of only zero-width spaces, and a name containing ANSI
escapes are all rejected.

---

### RL-205 — Permission elevation flow

**Priority** P2 · **Size** M

**Spec.** `PermissionRequest` decodes and is dropped; the phone has no way to
ask for a higher tier. Handle it by raising a desktop prompt naming the device,
the requested tier, and the justification string — with the justification clearly
attributed as text *from the phone*, since it is untrusted input rendered in a
security dialog. On approval, persist the new tier and send `PermissionGrant`.
Deny by default on timeout; never auto-approve.

Also implement `PermissionGrant.expiresInSeconds`, which is defined on the wire
and ignored: on expiry, drop the session to `readOnly` and send a fresh grant.
Rate-limit requests to one per device per minute so a compromised phone cannot
produce a prompt storm — the same reasoning as the pairing rate limit.

**Acceptance.** A phone can request `extended`, the desktop prompts, approval
takes effect immediately, denial leaves the tier unchanged, and a temporary
grant expires on schedule.

---

### RL-206 — System status telemetry

**Priority** P2 · **Size** S

**Spec.** `SystemStatus` has a payload class and is never produced. Emit it —
battery percentage and charging state, CPU load, memory pressure, output volume,
uptime — every 5 s while a phone is connected and never otherwise, matching the
existing media-watch discipline in `DesktopService._startMediaWatch`, which
polls only when someone is watching precisely so an idle laptop pays nothing.
macOS: `pmset -g batt`, `sysctl`, `host_statistics64`. Windows:
`GetSystemPowerStatus`, `GlobalMemoryStatusEx`, performance counters. Display it
as a compact status strip on the mobile control screen.

**Acceptance.** Values match Activity Monitor / Task Manager within one sample
interval. Zero polling with no device connected — verify with `powermetrics`.

---

### RL-207 — Custom command registry

**Priority** P2 · **Size** M

**Files**
- `apps/desktop/lib/src/domain/command_registry.dart` (new)
- `apps/desktop/lib/src/ui/command_editor.dart` (new)
- `apps/desktop/lib/src/domain/desktop_service.dart` (`_onRunCommand`)

**Why.** `_onRunCommand` currently logs a warning and refuses, which is the
correct default — an unresolved command ID must never fall through to a shell.
The registry it needs does not exist.

**Spec.**
1. Persist registered commands as JSON under the application support directory,
   with the same integrity MAC treatment as RL-101. This file is a list of
   things the machine will execute on request from the network; its integrity is
   not optional.
2. Record shape: stable ID · display name · executable path · argument list ·
   declared placeholders · working directory · minimum `PermissionTier`
   (default `extended`).
3. **Command text never crosses the wire** — `SECURITY.md` already states this
   and it is the property that makes the feature safe. Only the registered ID
   and placeholder *values* travel.
4. Placeholder substitution: values are always passed as separate `argv` entries
   and never concatenated into a shell string, matching the care already taken
   in `_runLaunch`. Reject any value containing a null byte. Cap value length at
   1 KB and the count at the declared placeholders — no extras.
5. Never invoke through a shell. `Process.run` with `runInShell: false`.
6. Desktop editor UI to add, edit, test-run, and remove commands. A newly added
   command is disabled until the user explicitly enables it, so a UI mistake
   does not immediately create a network-reachable executable.
7. Mobile shows the registered commands as a quick-actions grid, populated from
   a list the desktop sends after `PermissionGrant`.

**Acceptance.** A registered command runs from the phone. An unregistered ID is
refused and logged. A placeholder value of `; rm -rf ~` is passed as a literal
argument and executes nothing. A command requiring `extended` is refused for a
`standard` device.

**Risks.** This is the largest deliberate attack surface in the product. The
allow-list design is what bounds it; do not add a "run arbitrary command" escape
hatch for convenience, and do not accept a command definition over the network.

---

## 5. P3 — screen sharing (Milestone 3)

The largest single feature, and per the roadmap the one most likely to reveal
that the transport needs QUIC.

---

### RL-300 — Screen streaming protocol messages

**Priority** P3 · **Size** M · **Blocked by** RL-103

**Spec.** Replace the opaque decode for the five `0x06xx` types with real
payload classes.

- `ScreenStreamStart` — monitor ID, target width/height, max FPS, target
  bitrate, codec preference list.
- `ScreenStreamStop` — reason.
- `ScreenFrame` — monitor ID, frame sequence, capture timestamp, keyframe flag,
  fragment index and count, codec, encoded bytes.
- `ScreenConfigure` — mid-stream bitrate, FPS, and scale changes.
- `ScreenTopology` — per monitor: ID, bounds, scale factor, primary flag, name.

Fragmentation is the part to get right. `PROTOCOL.md` §3 already reserves
`fragment` and `lastFragment` flags and nothing uses them; a video frame is the
first payload that exceeds a datagram. Define the reassembly rule normatively:
fragments of one frame share a sequence, arrive within a bounded window, and a
frame missing any fragment when the next keyframe arrives is discarded whole
rather than decoded partially.

**Acceptance.** Round-trip codec tests for all five types, including
adversarial input consistent with the existing test style: declared fragment
counts that do not match, oversized dimensions, negative bitrates. `PROTOCOL.md`
gains a normative §11.

---

### RL-301 — Screen capture and encode

**Priority** P3 · **Size** XL · **Blocked by** RL-300

**Spec.** Split into two passes. The original spec here named ScreenCaptureKit
and VideoToolbox and dismissed the older APIs outright, which was written
without reconciling it against ADR 0003: this repository reaches the OS through
`dart:ffi` alone, with no compiled native shim, and **both of those APIs deliver
their output by invoking an Objective-C block on a dispatch queue.** `dart:ffi`
cannot construct a block, so neither is reachable from here today. The same is
true of Windows Graphics Capture, which is WinRT and needs a projection.

*Pass one — reachable now, synchronous only.* macOS: `CGDisplayCreateImage`
polled on a timer, encoded to JPEG through ImageIO's `CGImageDestination`. Both
are plain C, both return their result, and both are bindable with the
`lookupFunction` style already in `coregraphics_ffi.dart`. `ScreenCodec.jpeg`
exists on the wire for exactly this. Bandwidth-hungry and not the destination,
but it puts a real picture of the desk on the phone.

*Pass two — the destination, and it needs a decision first.* ScreenCaptureKit
plus hardware H.264 through VideoToolbox, and Media Foundation on Windows. All
of them require a native shim — a small compiled Swift/C++ target that owns the
callback and hands frames back across a port — which is a change to how this
project talks to the OS and therefore wants its own ADR, not an afternoon.
VP8 was considered and rejected on hardware support.

Adaptive bitrate driven by the RTT and loss the session already measures —
`ConnectionQuality` exists and is currently only displayed. Ladder from 500 kbps
to 8 Mbps; drop resolution before frame rate, since a smooth low-resolution
stream reads better than a sharp stuttering one.

Permissions: Screen Recording on macOS is a separate grant from Accessibility
and fails silently in the same way. Extend the existing permission-watch
mechanism in `DesktopService._startPermissionWatch` rather than adding a second
one, and surface a banner with a direct link to the settings pane, matching
`openAccessibilitySettings`.

Capability gating: advertise `Capabilities.screenCapture` only when capture is
actually available, consistent with how media control is already gated. Note
that a macOS app without the Screen Recording grant does not get an error — it
gets an image of the wallpaper with every window missing — so "available" here
means the TCC preflight passed, not that the call returned something.

**Acceptance.** *Pass two:* 1080p30 at under 3 Mbps with visually acceptable
quality; under 150 ms glass-to-glass on a quiet 5 GHz network; graceful
degradation to 5 fps under a constrained link rather than a stall. *Pass one*
will not meet the bitrate target and is not expected to — JPEG per frame is
roughly an order of magnitude off. What pass one must meet: no capture when no
client is watching, a bounded frame queue under a slow link (skip, never
enqueue), and no leaked `CGImage` or `CFData` — Core Foundation is manually
reference counted and a leaked frame buffer is tens of megabytes a minute.

**Risks.** This is where TCP head-of-line blocking stops being theoretical. If
RL-103's datagram channel proves insufficient, the QUIC decision the roadmap
anticipates lands here and needs its own ADR before any code is written.

`ScreenFrame` copies its payload twice on decode: `readLengthPrefixedBytes`
returns a copy, and the constructor copies again. That is the same shape
`FileChunk` already has, so it is a pre-existing pattern rather than something
RL-300 introduced — but a file chunk is capped at 1 MiB and a frame at 16, and
frames arrive at up to 240 a second. Worth measuring here, where it will
actually show up, and fixing for both types together if it does. Do not fix it
for one and not the other; two types with different ownership rules is worse
than one slow rule.

---

### RL-302 — Multi-monitor enumeration

**Priority** P3 · **Size** M

**Spec.** `InputBackend` exposes a single `virtualBounds` rectangle. Add
`List<MonitorInfo> get monitors` with per-monitor bounds, scale factor, primary
flag, and name. macOS: `CGGetActiveDisplayList` plus `CGDisplayBounds`. Windows:
`EnumDisplayMonitors` plus `GetMonitorInfo` and `GetDpiForMonitor`. Send it as
`ScreenTopology` after connect and on change. Make `mouseMoveAbsolute`
monitor-aware: normalised coordinates currently map across the whole virtual
desktop, which on a two-monitor setup means the phone's touchpad addresses both
screens at once and neither precisely.

**Acceptance.** A three-monitor setup with mixed DPI reports correct bounds and
scale for each; absolute positioning lands within 2 px of the target on any of
them.

---

### RL-303 — Touch-to-click mapping on the streamed view

**Priority** P3 · **Size** M · **Blocked by** RL-301, RL-302

**Spec.** Tapping the streamed image positions the cursor there via
`mouseMoveAbsolute`, which already carries normalised coordinates for exactly
this purpose. Handle the aspect-ratio letterboxing so a tap in a black bar does
nothing rather than clamping to an edge. Pinch to zoom the *view* rather than
the remote desktop, with panning while zoomed, and a mode switch between direct
positioning and relative trackpad behaviour — direct is better for pointing,
relative for precision.

---

## 6. P4 — file transfer and clipboard images (Milestone 4)

---

### RL-400 — File transfer protocol messages

**Priority** P4 · **Size** M

**Spec.** Real payload classes for the five `0x07xx` types.

- `FileOffer` — transfer ID, name, size, MIME type, SHA-256 of the whole file,
  modification time.
- `FileAccept` — transfer ID, resume offset, chosen chunk size.
- `FileChunk` — transfer ID, offset, bytes, per-chunk CRC-32C.
- `FileComplete` — transfer ID, final hash for verification.
- `FileAbort` — transfer ID, reason.

**Filename handling is security-critical.** The name arrives from an untrusted
peer. Strip every path separator, reject `..` in any form including encoded
variants, reject absolute paths, reject Windows reserved device names (`CON`,
`PRN`, `AUX`, `NUL`, `COM1`–`COM9`, `LPT1`–`LPT9`, with or without an
extension), reject trailing dots and spaces, reject control characters, cap at
255 bytes, and normalise Unicode to NFC to prevent two names that render
identically from resolving to different files. Never write outside the
designated download directory, and verify that with a realpath check after
resolution rather than by string inspection alone.

**Acceptance.** Round-trip tests for all five types. A dedicated adversarial
filename test covering every case above — this is the highest-risk decoder in
the protocol and deserves the same treatment the existing tests give hostile
frames.

---

### RL-401 — File transfer implementation

**Priority** P4 · **Size** L · **Blocked by** RL-400

**Spec.**
1. Chunked with resume: 256 KB chunks by default, negotiated in `FileAccept`.
2. Per-transfer content keys derived from the session exporter secret —
   `HKDF(exporter, info: "rl1 file " ‖ transferID)` — so a long transfer does
   not consume the session's nonce space and a compromised transfer key does not
   expose the session.
3. Resume across reconnects: persist the partial file plus a manifest of
   received offsets; on reconnect, offer the transfer ID and resume from the
   first gap.
4. Verify the whole-file SHA-256 on completion and delete on mismatch. A
   corrupt file delivered silently is worse than a failed transfer.
5. Flow control: never queue more than 4 MB of unacknowledged chunks, so a
   transfer cannot starve the input path. This is the same head-of-line concern
   RL-103 addresses from the other side.
6. Destination: the platform downloads directory by default, user-configurable,
   with the desktop prompting before the first transfer from each device.
7. UI: transfer list with progress, speed, cancel, and retry on both sides.
   Mobile also needs a share-sheet target so files can be sent from other apps.
8. Tier: `extended` and above only, which `PermissionTier.canTransferFiles`
   already expresses.

**Acceptance.** A 1 GB file transfers with verified integrity; killing Wi-Fi
mid-transfer and restoring it resumes rather than restarts; cursor latency stays
within 20% of idle during a transfer, measured with RL-107; a transfer whose
hash does not match is deleted and reported.

---

### RL-410 — Clipboard images

**Priority** P4 · **Size** M

**Files**
- `packages/rl_native/lib/src/macos/macos_clipboard.dart:255`
- `packages/rl_native/lib/src/windows/win32_clipboard.dart:141`
- `apps/desktop/lib/src/domain/clipboard_sync.dart:201`

**Spec.** `readImagePng` and `writeImagePng` are declared on `ClipboardBackend`
and return null / do nothing on both platforms, with comments recording that a
lossy conversion was rejected in favour of deferring. `ClipboardContentType`
already reserves `imagePng`, and `applyRemote` logs that image flavours are not
applied.

macOS: `NSPasteboardTypePNG` directly where present; otherwise `NSImage` →
`NSBitmapImageRep` → `representationUsingType:NSBitmapImageFileTypePNG`.
Windows: `CF_DIB` / `CF_DIBV5` requires a DIB↔PNG codec. Prefer WIC
(`IWICImagingFactory`) over hand-rolling one — alpha and colour-profile handling
is exactly what a half-conversion mangles, which is why this was deferred rather
than approximated. Preserve the alpha channel through `CF_DIBV5`; `CF_DIB` loses
it.

Size cap: 10 MB after encoding. Larger images are offered as a file transfer
instead (RL-401), not silently dropped. Do not send images automatically on the
metered path — require an explicit action for anything over 1 MB.

**Acceptance.** Copying a screenshot on the desktop makes it pasteable on the
phone and vice versa, on both platforms, with transparency preserved.

---

### RL-420 — LocalSend protocol compatibility mode

**Priority** P4 · **Size** L · **Blocked by** RL-400, RL-401, RL-801

**Why this is separate from RL-401.** RL-400/401 give RemoteLink file transfer over its *own*
encrypted session, between two RemoteLink devices. This task makes RemoteLink interoperable with
[LocalSend](https://github.com/localsend/localsend) itself — so a user can send to any Android, iOS,
macOS, Windows, or Linux device running LocalSend, without RemoteLink on both ends. That is a
different and larger product claim, and it needs its own decision.

**What the reference gives us.** LocalSend is Apache-2.0 and, usefully, also Flutter/Dart. Its
protocol v2.2 is published as a spec:

- Discovery: multicast UDP announce on `224.0.0.167:53317` carrying alias, device type, fingerprint,
  port, and protocol; plus an HTTP fallback (`POST /api/localsend/v2/register` across local IPs) for
  networks that filter multicast — the same failure mode this repo's own discovery already plans for.
- Transfer: `POST /api/localsend/v2/prepare-upload` returns a `sessionId` and a per-file token map;
  the body of `POST /api/localsend/v2/upload?sessionId=&fileId=&token=` is the raw bytes. A declined
  file is simply absent from the token map.
- Integrity: optional per-file SHA-256, answered with HTTP 422 on mismatch.
- Identity: fingerprint is the SHA-256 of the on-the-fly self-signed TLS certificate.
- Authorisation: an optional PIN as a query parameter.

**The security posture differs, and that is the whole risk.** LocalSend is trust-on-first-use over a
self-signed certificate with an optional PIN. RemoteLink's native path is an X25519 handshake with a
user-verified SAS. These are not equivalent, and running both means the product has two postures at
once. Therefore:

- Compatibility mode is **off by default** and opt-in per session.
- The UI must say plainly that the peer is **not paired**.
- A LocalSend peer gets **file receipt only** — never input, clipboard, power, or any other
  subsystem, regardless of tier. The permission model must enforce that on the receiving side, not
  by hiding UI.
- `SECURITY.md` gains a section describing this before any code is written.

**Licensing.** Implement from the published spec, which is freely implementable. Do **not** vendor
LocalSend source: Apache-2.0 carries attribution and NOTICE obligations, and this repository
currently has no licence at all (RL-801), so copying their code in before that is settled creates a
real problem rather than a theoretical one.

---

### RL-421 — File send/receive UI and OS share integration

**Priority** P4 · **Size** M · **Blocked by** RL-401

The user-facing half, kept separate from the wire work. LocalSend's flow is the proven UX here and
worth following rather than reinventing.

- **Mobile:** a Send tab — pick files, photos, or text; choose a target from the discovered and
  paired list; per-file progress with speed and ETA; cancel. Register as an **OS share target**
  (Android `ACTION_SEND`/`SEND_MULTIPLE` intent filter, iOS Share Extension). That entry point is
  what makes the feature actually get used — a transfer tool you must open first mostly goes unused.
- **Desktop:** drag-and-drop onto the window to send; an incoming-transfer prompt naming the sender
  and listing files with sizes, with Accept and Decline; a transfers list with progress, speed,
  cancel, and retry.
- **Text as well as files.** LocalSend supports sending a bare string, and it is genuinely useful —
  a URL or snippet to the other machine without disturbing the clipboard.
- Respect the destination-directory setting, and prompt before the first transfer from each device.

**Postmortem.** This shipped once without working. The brief carried a blanket "do not add
third-party dependencies" constraint, and Flutter has no built-in file picker — so the requirement
was impossible as written, and what got built was a text field for an absolute path next to a button
that filled in a hard-coded sample. It passed review. The user found it.

Two lessons worth keeping:

- A blanket dependency ban is right for `rl_protocol` and wrong for an app whose job is to talk to
  the OS. State the constraint where it applies, not everywhere.
- Every brief since says: if a requirement cannot be met under the stated constraints, say so
  instead of building something that looks like it works. That sentence is cheap and this was not.

**Still open from this item:** the OS share-target entry points. Android's `ACTION_SEND` /
`ACTION_SEND_MULTIPLE` intent filter was never added, and the iOS Share Extension is RL-006. Picking
a file from inside the app works; sharing *to* RemoteLink from another app does not.

---

### RL-411 — Clipboard history

**Priority** P4 · **Size** M · **Blocked by** RL-410

**Spec.** Ring buffer of the last 25 items on each side. **Concealed content is
never recorded** — `ConcealedType` on macOS and
`ExcludeClipboardContentFromMonitorProcessing` on Windows are already honoured
by the sync path and must be honoured here too; a password manager's clipboard
entry must not become a persisted history row. History is memory-only by
default; persistence is opt-in, and when enabled it is encrypted with a key from
the platform keystore (RL-100). Pin, delete, and clear-all in both UIs.

---

## 7. P5 — the long tail (Milestone 5)

---

### RL-500 — Presentation mode

**Priority** P5 · **Size** M

**Spec.** Real payloads for `slideCommand`, `laserPointer`, and
`presentationBlank`. Slide commands resolve to the shortcut the presenting app
expects, following the `namedShortcut` precedent — intent travels, the desktop
resolves it. Laser pointer: a click-through always-on-top overlay window
following normalised coordinates; `laserPointer` is already marked `isLossy` and
so is datagram-eligible. Blank: an opaque overlay on the presentation display
only. Mobile: a presenter screen with large previous/next targets, an elapsed
timer, and speaker notes where the app exposes them.

**Acceptance.** Works with Keynote, PowerPoint, and Google Slides in a browser.
The laser overlay does not intercept clicks. Blanking covers only the
presentation display.

---

### RL-510 — Gamepad and motion control

**Priority** P5 · **Size** L

**Spec.** Real payloads for `gamepadState` and `motionState`. Windows: a virtual
Xbox 360 or DualShock pad, which needs a driver — ViGEmBus is the practical
option and requires the user to install it, so the flow must detect its absence
and explain rather than failing silently. macOS: there is no supported virtual
HID path without a kernel extension or DriverKit entitlement; scope macOS to
mapping gamepad input onto keyboard and mouse events and say so plainly rather
than shipping a control that silently does nothing. Mobile: on-screen sticks and
buttons plus gyroscope aiming at 60 Hz, both `isLossy` and datagram-eligible.

**Risks.** The macOS limitation is a product decision, not an implementation
detail. Decide whether a keyboard-mapped gamepad is worth shipping before
building it.

---

### RL-520 — Windows media control

**Priority** P5 · **Size** L

**Spec.** `GlobalSystemMediaTransportControls` is a WinRT interface, not a flat
C export, so `DynamicLibrary.lookupFunction` cannot reach it — this is why
Windows currently gets `UnsupportedMediaBackend`. Two viable routes:

*Route A (preferred).* A small C++ shim DLL exposing a flat C ABI over
`GlobalSystemMediaTransportControlsSessionManager`, built with the app and
loaded by FFI. Keeps the FFI-not-channels discipline of ADR 0003 and yields full
metadata plus per-session control.

*Route B (fallback).* Synthesise `VK_MEDIA_PLAY_PAUSE` and friends through
`SendInput` for transport control, and `IAudioEndpointVolume` (a COM interface,
also needing a shim) for volume. Gives control without metadata.

Ship Route B first if Route A slips; the capability system already handles a
desktop that has `mediaControl` without `mediaMetadata`.

**Acceptance.** Play/pause, next, previous, and volume work against Spotify,
Groove, and a browser tab. Now-playing metadata appears on the phone for
Route A. `buildCapabilities` advertises media on Windows only when it works.

---

### RL-530 — Wake-on-LAN

**Priority** P5 · **Size** S

**Spec.** When a paired desktop is unreachable, the phone sends a magic packet
to its stored MAC address. Requires the desktop to report its MAC during
pairing — add it to `DeviceInfo` as an appended field, which is non-breaking per
`PROTOCOL.md` §5. Broadcast to `255.255.255.255:9` and to the subnet directed
broadcast, since access points differ in which they forward — the same
belt-and-braces reasoning the discovery layer already uses for multicast. Show
the setup requirements honestly: WoL must be enabled in firmware and the NIC
driver, and it does not work over Wi-Fi on most hardware.

---

### RL-540 — Notification mirroring

**Priority** P5 · **Size** L

**Spec.** Desktop notifications forwarded to the phone. macOS: reading other
apps' notifications requires either the private `NSUserNotificationCenter`
database or an Accessibility-based observer — both fragile across OS versions
and the latter needs the grant the app already holds. Windows:
`UserNotificationListener` needs a WinRT shim like RL-520's. Needs a new
subsystem — `0x0Cxx`, the next free range, allocated append-only.

**This is a privacy decision before it is a feature.** Notification content
includes messages, two-factor codes, and email previews; forwarding it to a
phone means it crosses the network and is rendered on a second device. Requires
explicit per-application opt-in with a default of nothing enabled, and its own
section in `SECURITY.md` before any code is written.

---

## 8. P5 — platform expansion (Milestone 6)

---

### RL-600 — Linux desktop

**Priority** P5 · **Size** XL

**Spec.** `InputBackend` already anticipates this — the interface is
platform-neutral and `NativeBackends.currentPlatform` already returns
`PlatformKind.linux`. Input: `libei` for Wayland, XTEST for X11, selected at run
time from `XDG_SESSION_TYPE`. Clipboard: `wl-clipboard` protocol on Wayland,
`XFixes` selection notifications on X11. Capture (with RL-301): PipeWire through
the xdg-desktop-portal, which also supplies the permission prompt. Media: MPRIS
over D-Bus, which is better than either Windows or macOS offers. Autostart: an
XDG desktop entry in `~/.config/autostart`. Packaging: Flatpak first, since the
portal permission model is what capture needs anyway.

**Acceptance.** Works on GNOME Wayland, KDE Wayland, and X11. Added to the CI
matrix from RL-001.

---

### RL-601 — Browser client

**Priority** P5 · **Size** XL

**Spec.** Requires the WebSocket transport ADR 0001 deliberately did not build.
`FramedConnection` is the seam — its interface is what makes this possible
without touching the session or crypto layers. Needs: a WebSocket
`FramedConnection` implementation, TLS on the desktop listener with a locally
generated certificate (a browser will not open an insecure WebSocket from an
HTTPS page), a Web Crypto implementation of the handshake, and a decision about
discovery, which a browser cannot do at all — likely a QR-scanned URL from
RL-106.

**Risks.** The TLS certificate problem is the real one, not the transport. A
self-signed certificate for a LAN IP produces a browser warning that no amount
of UI can make acceptable. Solve that before starting, or scope the client to a
manually trusted certificate and say so.

---

### RL-602 — Wear OS and watchOS

**Priority** P5 · **Size** L

**Spec.** Media and presentation control only. No touchpad, no keyboard. Pairing
piggybacks on the phone's trust store rather than being independent — a watch
that must pair separately is a watch nobody sets up.

---

## 9. Cross-cutting

---

### RL-002 — Packaging, signing, and updates

**Priority** P1 · **Size** L · **Blocked by** RL-001

**Why.** There is no path from this repository to something a user can install.
The desktop app already registers itself as a login item via `AutoStart`, which
means distribution is not optional — an unsigned binary that adds itself to
startup is exactly what security tooling flags.

**Spec.**
- macOS: Developer ID signing, hardened runtime, notarisation, stapling, `.dmg`.
  The Accessibility grant is tied to the code signature, so an unsigned or
  re-signed build **loses the permission the product depends on** — this is the
  single most user-visible consequence of getting signing wrong.
- Windows: Authenticode signing and an MSIX or Inno Setup installer. Firewall
  rules for the service port must be created by the installer, not requested at
  first launch.
- Version display and an update check. Given the local-only posture, a check
  that phones home needs a deliberate decision and its own note in
  `SECURITY.md`; a manual "check for updates" is the conservative default.
- Release automation from a tag in the CI workflow.

**Acceptance.** A downloaded build installs and runs on a clean machine with no
Gatekeeper or SmartScreen warning, and the macOS Accessibility grant persists
across an update.

---

### RL-700 — Mobile settings screen

**Priority** P2 · **Size** M

**Spec.** There is no settings screen at all. Needed: rename this phone · view
this device's ID and public-key fingerprint · manage paired computers (rename,
forget, request a higher tier) · touchpad sensitivity, natural-scroll toggle,
tap-to-click · clipboard auto-sync toggles per direction · haptics · theme ·
diagnostics (connection state, RTT, discovery method in use, log export) · about
and licences. Persist through the existing storage layer; do not introduce a
second preferences mechanism.

---

### RL-701 — Desktop diagnostics panel

**Priority** P2 · **Size** S

**Spec.** `CommandDispatcher` already tracks `appliedCount`, `deniedCount`, and
`unsupportedCount`, and `MemoryLogSink` is already installed in `main.dart`.
Nothing displays either. Add a diagnostics panel: those three counters, per-
session RTT and quality, bound port and addresses, discovery beacon state,
input/clipboard/media backend availability with the reason when unavailable, and
a scrollable filtered log view with copy-to-clipboard. This is what turns a
support conversation from guesswork into a paste.

---

### RL-702 — Localisation

**Priority** P3 · **Size** M

**Spec.** Every user-visible string is a hard-coded English literal in both
apps. Introduce `flutter_localizations` with ARB files, extract all strings,
and handle RTL layout. Pluralisation matters immediately — `main.dart:225`
already hand-rolls `'$count device${count == 1 ? '' : 's'}'`, which does not
translate.

---

### RL-703 — Accessibility pass

**Priority** P2 · **Size** M

**Spec.** Neither app has been through an accessibility review. Required:
semantic labels on every icon button — the touchpad, media, and keyboard screens
are almost entirely unlabelled icons · a screen-reader-usable alternative to the
touchpad, which is a bare gesture surface with no semantics · verified contrast
in both themes · dynamic type without clipping, particularly on the rendered
keyboard · focus order and full keyboard navigation on desktop · reduced-motion
support. The pairing dialog needs particular care: it is a security decision and
the six digits must be announced clearly, not read as one large number.

---

### RL-704 — Error reporting and log export

**Priority** P2 · **Size** S

**Spec.** `MemoryLogSink` exists and is unread. Add: a `FileLogSink` with size-
capped rotation, an export action in both apps, and a crash handler that records
the last N log lines alongside the stack trace. **Redaction is required before
anything is exported** — device IDs, public keys, IP addresses, clipboard
contents, and file names must not appear in an exported log by default. Local
export only, no automatic upload, consistent with the product's no-cloud posture.

---

## 10. Documentation debt

| Item | Task |
|---|---|
| `SECURITY.md` §7 is a placeholder admitting there is no reporting channel | RL-800 |
| `PROTOCOL.md` needs normative sections for resumption (§6.1), datagrams (§10), screen streaming (§11), and file transfer (§12) | RL-102, RL-103, RL-300, RL-400 |
| No ADR for the QUIC decision the roadmap anticipates at milestone 3 | RL-301 |
| No ADR for cloud relay, which `ROADMAP.md` explicitly says needs one before it is considered | deferred by design |
| No `CONTRIBUTING.md`, no issue templates, no `LICENSE` | RL-801 |
| `docs/RUNNING.md` predates Bonjour discovery; verify it still matches | RL-802 |

**RL-800** — Establish a security contact and disclosure policy. Add
`SECURITY.md` §7 content and a `.github/SECURITY.md`. This is cheap and is
currently an admitted gap in a document whose whole purpose is not having any.

**RL-801** — Add a `LICENSE`. There is none, which means the code is
all-rights-reserved by default regardless of intent. Add `CONTRIBUTING.md`
covering the workspace layout, the strict one-way dependency direction, the
append-only wire-code rule, and the requirement that packages stay Flutter-free.

**RL-802** — Re-verify `docs/RUNNING.md` against the current code, particularly
the four silently-failing permissions and the iOS multicast entitlement note,
now that Bonjour discovery exists as a second route.

---

## 11. Explicitly not planned

Carried from `ROADMAP.md` and restated so no one treats their absence as an
oversight:

- **Cloud relay and remote internet access.** Technically straightforward and a
  completely different security posture — it turns "a thing on your LAN" into "a
  service that can reach your desktop from anywhere". Needs its own ADR and a
  deliberate decision, not an increment.
- **AI assistant and voice commands.** No identified user problem. Building them
  first produces a feature nobody asked for and a permission prompt everyone
  resents.

---

## 12. Suggested order

Dependencies first, then value. The first row is not negotiable — the repository
currently ships a test suite that does not compile.

| Wave | Tasks | Rationale |
|---|---|---|
| 0 | RL-000, RL-001 | The tests must run before anything else is trusted. |
| 1 | RL-104, RL-105, RL-108 | Fix what is broken; test the security boundary. |
| 2 | RL-100, RL-101 | Close the two ranked key-storage gaps. |
| 3 | RL-107, RL-102 | Measure, then make reconnects cheap against a baseline. |
| 4 | RL-103 | The datagram channel, validated by RL-107's numbers. |
| 5 | RL-106, RL-203, RL-204, RL-205, RL-206 | Complete the pairing story and the unhandled-message gaps. |
| 6 | RL-701, RL-700, RL-703, RL-704 | The support and usability surface. |
| 7 | RL-002 | Ship it. |
| 8 | RL-200, RL-202, RL-207, RL-520 | Feature depth on the existing architecture. |
| 9 | RL-400, RL-401, RL-421, RL-410, RL-411, RL-420 | File transfer and clipboard images. RL-421 (the send UI and share-sheet target) lands right after the wire work, because a transfer feature with no OS entry point mostly goes unused. RL-420 (LocalSend interop) comes last in the wave — it is the only item here that adds a second security posture, so it should follow a working native path rather than lead it. |
| 10 | RL-300, RL-302, RL-301, RL-303 | Screen sharing, protocol first. |
| 11 | RL-500, RL-510, RL-530, RL-540, RL-600+ | The long tail and platform expansion. |

Waves 0–2 are strictly ordered. Everything from wave 5 onward can be reordered
by product priority, subject to the stated blockers.
