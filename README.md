# RemoteLink

Control a Windows or macOS computer from an Android or iOS phone over local
Wi-Fi. No cloud, no account, no internet, no typing in IP addresses.

Install the desktop app once. After that the phone finds the computer,
connects, and reconnects on its own.

---

## Status: milestone 1

This repository contains a **complete, working vertical slice**, not a demo and
not a full product. What is finished is finished to production standard —
tested, documented, and free of placeholders. What is not started is marked as
such rather than stubbed.

### Done

| Area | State |
|---|---|
| Binary wire protocol | Complete: framing, codecs, versioning, compression, 60+ message types |
| Cryptography | Complete: X25519 handshake, ChaCha20-Poly1305 sessions, SAS pairing, trust store |
| Discovery | Complete: UDP multicast with per-interface binding and broadcast fallback |
| Transport | Complete: framed TCP, heartbeat, RTT, coalescing, reconnect with jittered backoff |
| Native input | Complete: Win32 `SendInput` and macOS `CGEvent` via `dart:ffi`, full HID keymaps |
| Native clipboard | Text complete on both platforms; images deferred |
| Desktop app | Service, dispatcher with permission enforcement, clipboard sync, tray, pairing UI |
| Mobile app | Discovery, pairing, touchpad with acceleration and multi-touch |

### Declared in the protocol, not yet implemented

Screen streaming · file transfer · presentation mode · gamepad · media session
integration · custom command registry · session resumption.

These have wire codes reserved and decode as opaque, so a future build can
speak to this one without a version bump.

---

## Getting started

Requires **Flutter 3.27+** (Dart 3.6+, for pub workspaces).

```bash
flutter pub get           # resolves the entire workspace — one lockfile
./tool/verify.sh          # format, analyze, test
```

There is no bootstrap step. The root `pubspec.yaml` declares a native pub
workspace, so one `pub get` resolves all seven packages together. Melos is
optional and installed globally if you want its script runner
(`dart pub global activate melos`); it is deliberately not a dev dependency, so
its transitive dependencies can never break the build.

The platform runner directories (`android/`, `ios/`, `macos/`, `windows/`) are
generated rather than committed, since they are almost entirely tool output.
Create them once per checkout:

```bash
cd apps/desktop && flutter create --platforms=windows,macos .
cd ../mobile    && flutter create --platforms=android,ios .
```

Then add the platform entitlements the apps need — macOS needs the
`com.apple.security.network.server` and `network.client` entitlements plus an
`NSLocalNetworkUsageDescription`; iOS needs `NSLocalNetworkUsageDescription`
and a `NSBonjourServices` entry; Android needs `INTERNET`,
`ACCESS_NETWORK_STATE`, and `CHANGE_WIFI_MULTICAST_STATE` (the last one is
required for multicast discovery to receive anything at all).

Run the desktop companion:

```bash
cd apps/desktop && flutter run -d macos    # or -d windows
```

Run the phone app on a device on the same network:

```bash
cd apps/mobile && flutter run
```

**macOS:** grant Accessibility permission when prompted. Without it every input
event is silently discarded — the app will tell you rather than appearing to
work.

---

## Layout

```text
apps/
  desktop/        Flutter desktop companion — the service
  mobile/         Flutter phone app — the remote
packages/
  rl_core/        Clock, Result, errors, logging, device identity types
  rl_protocol/    Wire format: bytes, frames, messages, codec       (pure Dart)
  rl_crypto/      Handshake, pairing, session encryption, trust     (pure Dart)
  rl_transport/   Discovery, framed TCP, sessions, reconnection     (dart:io)
  rl_native/      Win32 and Core Graphics bindings                  (dart:ffi)
docs/
  PROTOCOL.md     Normative wire specification
  SECURITY.md     Threat model, including what is *not* defended
  ROADMAP.md      Remaining milestones
  adr/            Decision records with the options that were rejected
```

The dependency direction is strict and one-way: `rl_core` ← `rl_protocol` ←
`rl_crypto` ← `rl_transport`, with `rl_native` alongside. Nothing below the app
layer imports Flutter, which is why every package has tests that run under
`dart test` with no engine.

---

## The three decisions worth knowing

**Raw TCP, not WebSocket.** The upgrade handshake costs a round trip on every
connect and RFC 6455 requires masking every client byte. A 22-byte cursor
update goes out as one segment with `TCP_NODELAY`. See
[ADR 0001](docs/adr/0001-discovery-and-transport.md).

**`dart:ffi`, not platform channels.** A `MethodChannel` hop costs 50–150 µs
and, worse, varies — and variable latency on the cursor path is visible as
stutter. See [ADR 0003](docs/adr/0003-native-bridge.md).

**Riverpod, not Bloc.** Nearly all the app-layer state is derived streams
rather than state machines, and the genuine state machines live outside the UI
layer as plain Dart. See [ADR 0002](docs/adr/0002-state-management.md).

---

## Security in three sentences

Every device holds a long-term X25519 key generated on first launch; its public
half hashes to the device ID shown in the UI. Connecting runs a simplified
Noise XX handshake that starts with an ephemeral exchange — giving forward
secrecy and immediate confidentiality — then authenticates both static keys
underneath that encryption, so neither is ever visible on the wire. The first
connection between two devices additionally requires the user to confirm a
six-digit string derived from the transcript, which a machine-in-the-middle
cannot make match on both screens.

[SECURITY.md](docs/SECURITY.md) documents the threat model and, more usefully,
the five known gaps.

---

## Testing

```bash
melos run test            # pure-Dart packages
melos run test:flutter    # widget tests
```

Coverage is concentrated where correctness is hard to eyeball: adversarial
protocol input, the full handshake driven end to end in memory, an explicit
machine-in-the-middle test asserting the two SAS values differ, the replay
window, and TCP framing under fragmented and coalesced reads.
