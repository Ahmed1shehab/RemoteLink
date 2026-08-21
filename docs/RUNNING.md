# Running and testing Remote Link

Read the first section before you spend time on simulators. The order matters.

---

## 0. Run the tests first

The packages beneath the apps carry the hard parts — the wire format, the
handshake, the reconnect logic — and their tests need **no simulator, no
entitlements, no permissions, and no platform runners**.

**Run from the repository root.** The paths below are relative to it, and a
stray `cd apps/desktop` from an earlier step is the usual reason this reports
`Does not exist`.

```bash
cd "$(git rev-parse --show-toplevel)"
flutter pub get
dart test packages/rl_core packages/rl_protocol packages/rl_crypto packages/rl_native
dart test packages/rl_transport      # opens real loopback sockets
dart test tool/latency_harness
```

The two Flutter apps have widget tests of their own:

```bash
cd apps/desktop && flutter test
cd apps/mobile  && flutter test
```

Or avoid the question — `tool/verify.sh` resolves its own location, so it works
from any directory:

```bash
./tool/verify.sh
```

**`verify.sh` does not currently pass end to end**, for reasons that predate any
particular change: `dart format` rewrites a large number of files under the
tall-style formatter that shipped in Dart 3.7, and two `close_sinks` errors
remain in `rl_transport`. Every test suite above passes. Until that is resolved,
run the suites directly rather than concluding the tree is broken.

This is the highest-signal, lowest-setup check available, and it exercises:

- adversarial protocol input (truncated frames, hostile lengths, bad UTF-8)
- the full handshake driven end to end in memory
- an explicit machine-in-the-middle test asserting the two SAS values differ
- the AEAD, the replay window, and TCP framing under split and coalesced reads
- a real client and server talking over loopback

Fix anything that fails here before touching Xcode. A compile error in
`rl_crypto` surfaced by `dart test` takes seconds to diagnose; the same error
surfaced by a failed iOS build takes minutes.

---

## 1. Generate the platform runners

The `macos/`, `ios/`, and `android/` directories are `flutter create` output
and are not committed. Generate them and apply the required permissions:

```bash
./tool/bootstrap_platforms.sh
```

This is not optional boilerplate. It sets four things the app cannot work
without, each of which fails **silently** if missing:

| Setting | Platform | What breaks without it |
|---|---|---|
| `com.apple.security.network.server` | macOS | The desktop starts fine and never accepts a connection. `network.client` alone is not enough — that only permits outbound. |
| `NSLocalNetworkUsageDescription` | macOS, iOS | The OS never shows the local-network prompt, so discovery finds nothing and reports no error. |
| `NSBonjourServices` | iOS | Local-network access stays denied even with the description present. |
| `CHANGE_WIFI_MULTICAST_STATE` | Android | Multicast packets are dropped below the app. Discovery is dead with no diagnostic. |

---

## 2. Run the desktop companion

```bash
cd apps/desktop && flutter run -d macos
```

**Grant Accessibility permission when prompted.** Without it, every
`CGEventPost` silently does nothing — no error, no exception, just a cursor
that will not move. The app checks `AXIsProcessTrusted` at startup and shows a
banner rather than letting you discover this the hard way.

System Settings → Privacy & Security → Accessibility → enable the entry.

One annoyance worth knowing in advance: macOS keys that permission to the
binary, and `flutter run` rewrites the binary on each build. You will
occasionally have to remove and re-add the entry after a rebuild. This is
macOS being correct, not a bug in the app.

---

## 3. Run the client

### Option A — as a macOS window (recommended first)

```bash
cd apps/mobile && flutter run -d macos
```

Fastest path by a wide margin: no simulator boot, no permission prompts, no
entitlement review, and both processes on loopback. Trackpad drag drives the
touchpad surface, so mouse move, click, drag, and two-finger scroll are all
testable. Use this to confirm the stack works end to end before adding
platform variables.

### Option B — iOS Simulator

```bash
open -a Simulator
cd apps/mobile && flutter run
```

This generally works, because the Simulator shares the Mac's network stack —
so `127.0.0.1` inside it is the Mac's loopback, and the multicast entitlement
Apple requires on real hardware is not enforced.

Two things to watch:

- **Accept the local-network prompt.** If you dismiss it, discovery returns an
  empty list forever and iOS gives no signal. Reset with
  `xcrun simctl privacy booted reset all`.
- **Both apps bind UDP 47810 on one host.** They use `SO_REUSEPORT`, so
  multicast reaches both, but a *unicast* query reply may be delivered to only
  one of them. The practical effect is that the "Search again" button can look
  unreliable while the periodic announcement still finds the computer within
  about two seconds. On separate machines this does not arise.

### Option C — a real iPhone

Works over Wi-Fi. The multicast caveat that used to make this the hard path
still exists, but it is **no longer the whole story**: there are now two
discovery routes, and only one of them is gated.

**iOS 14+ requires the `com.apple.developer.networking.multicast` entitlement
for multicast on real hardware, and Apple grants it by application.** Until it
is approved, a real device will not receive the UDP beacons.

**Bonjour / DNS-SD is explicitly exempt from that entitlement**, and the desktop
now advertises over both. `BonjourAdvertiser` on the desktop and
`BonjourDiscoveryBackend` on the phone run *in addition to* the UDP beacon, not
instead of it, and a device found either way produces the same `Beacon` — so
nothing downstream knows or cares which route found it. A real iPhone therefore
discovers the computer without the entitlement.

Keep the entitlement in mind anyway: some networks filter mDNS while permitting
directed UDP, which is exactly why both routes exist. A physical Android device
on the same Wi-Fi has no gate on either route and remains the simplest
real-hardware test.

---

## 3b. Running from Xcode instead of the CLI

Useful for reading native crash logs, adjusting signing, or attaching
Instruments. Two rules:

- **Open the `.xcworkspace`, never the `.xcodeproj`.** The project alone does
  not include the Flutter build phases or the CocoaPods targets.
- **Run `flutter build ios --config-only` (or `flutter run` once) first.**
  Xcode reads `ios/Flutter/Generated.xcconfig`, which Flutter writes. Opening a
  fresh checkout in Xcode before that produces a build failure about a missing
  file that looks unrelated to the real cause.

```bash
cd apps/mobile  && flutter build ios --config-only && open ios/Runner.xcworkspace
cd apps/desktop && open macos/Runner.xcworkspace
```

### With a paid Apple Developer account

An organization account changes one thing that matters here: you can **request
the multicast entitlement**, which is what otherwise blocks discovery on a real
iPhone. Apply for `com.apple.developer.networking.multicast` at
<https://developer.apple.com/contact/request/networking-multicast>. Approval is
manual and not instant.

Once granted, add it to `apps/mobile/ios/Runner/Runner.entitlements` and select
the matching provisioning profile. Until then, a real device will pair only if
you reach it another way — the Simulator and Android have no such gate.

Everything else (free or paid) is unaffected: signing for local development
works with the automatically managed "Apple Development" certificate Flutter
already picked up.

---

## 4. What to expect on a first successful run

1. The desktop window shows "Discoverable on this network" with its device ID.
2. The client lists the computer within about two seconds.
3. Tapping it connects, and both screens show the **same six digits**.
4. Confirming on both sides pairs them; the desktop lists the device.
5. Dragging on the touchpad moves the real cursor.
6. Copying text on either side appears on the other within ~100 ms, with no
   button pressed.

If step 2 fails, it is discovery — check the entitlements from step 1 and that
both devices are on the same subnet (guest Wi-Fi networks isolate clients).
If step 3 shows different digits, stop: that is what a
machine-in-the-middle looks like, and it is exactly what the check is for.

---

## Troubleshooting

**"Not accepting new devices"** — the tray menu's "Allow new devices to pair"
is off.

**Digits never appear** — the handshake completed but pairing did not start.
Check the desktop logs for `security.` codes; `peer_revoked` and
`server_key_mismatch` are refusals by design, not faults.

**A removed device says "This computer removed your access"** — working as
intended. A revoked peer is now told so over the encrypted session and stops,
rather than reconnecting on the backoff curve forever. Pairing it again from
the phone clears the stored key and starts a fresh exchange.

**Cursor does not move but everything else works** — Accessibility permission.
See step 2.

**Nothing copied on the phone reaches the computer while the phone app is in
the background** — working as intended, and not fixable from user space.
Android has refused clipboard reads to apps without focus since Android 10, and
iOS puts a permission alert in front of them. The phone watches for changes and
sends them while it is on screen, and catches up on whatever it missed the
moment it is opened again.

**Clipboard syncs one way only** — likely the concealed-content flag. Content
copied from a password manager is deliberately not mirrored.

**Windows: cannot type into an elevated window** — User Interface Privilege
Isolation blocks synthetic input from an unelevated process into an elevated
one. This is Windows working correctly and cannot be worked around from user
space.

---

## Regenerating the icons

Every app icon, the menu-bar and notification-area icons, the Android and iOS
launch screens, and the logo bundled into both apps are generated from one file:
`assets/brand/logo.png`.

```bash
dart run tool/brand/bin/brand.dart
```

That writes forty-four files across four platforms. Do not edit any of them by
hand — replace the master artwork and run the generator, or the next person to
run it silently reverts your change.

The rules the generator applies, and why, are in
[`tool/brand/bin/brand.dart`](../tool/brand/bin/brand.dart): iOS and Android get
a full-bleed crop because they mask their own corners, macOS keeps the tile's
shape and its Dock margin, and the macOS menu bar gets an alpha mask because a
template image ignores colour entirely.

To check the menu-bar mask without a Mac, print it as text:

```bash
dart run tool/brand/tool/preview_tray.dart
```
