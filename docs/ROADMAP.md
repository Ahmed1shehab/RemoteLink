# Roadmap

Milestone 1 is in the repository. Everything below is not, and is ordered so
that each milestone leaves the product shippable.

---

## Milestone 2 — hardening and latency

The point of this milestone is that nothing new appears in the UI. It is the
work that makes milestone 1 trustworthy.

1. **Private key into the OS keystore.** DPAPI on Windows, Keychain on macOS.
   The largest known gap in `SECURITY.md`.
2. **Session resumption.** The messages and derived secret exist; the
   server-side ticket sealing does not. Turns a reconnect from a full handshake
   into one round trip.
3. **UDP side-channel for lossy input.** Same session keys, `ReplayWindow`
   finally load-bearing. Removes head-of-line blocking so a clipboard image
   cannot delay the cursor.
4. **Trust-store MAC on mobile.** Closes gap 3.
5. **QR pairing UI.** The protocol side is done and tested — `PairingPayload`
   round-trips through its URI form, and `DesktopService.pairingPayload` builds
   it. What is missing is the display widget on the desktop and the scanner on
   the phone. Milestone 1 shipped numeric comparison only rather than a QR code
   the phone could not read, because half a security flow is worse than none:
   it invites the user to trust a mechanism that is not actually running.
6. **Latency measurement harness.** Numbers rather than impressions: finger-to-
   cursor at the 50th and 99th percentile, under an idle network and under load.

Exit criterion: p99 cursor latency under 10 ms on a quiet 5 GHz network, and
reconnect under 2 s after a Wi-Fi handoff.

---

## Milestone 3 — screen sharing

**Not in the current release.** Capture (macOS) and the phone's viewer are
written and work well enough to demonstrate, which is the state a half-finished
feature gets shipped from. Both sit behind `kScreenSharingShipped` in
`apps/desktop/lib/src/domain/desktop_service.dart`, switched off: the desktop
withholds the capability bit, the phone's button disappears with it, and an
explicit stream request is refused. Everything below is what turning it on is
waiting for.

The largest single feature and the one most likely to reveal that the transport
needs QUIC.

- Capture: Windows Graphics Capture on Windows, ScreenCaptureKit on macOS.
  Both are the modern APIs; Desktop Duplication and `CGDisplayStream` are the
  deprecated predecessors and are not worth starting on.
- Encoding: hardware H.264 via Media Foundation and VideoToolbox, with a
  software fallback. VP8 was considered; hardware support is worse.
- Adaptive bitrate driven by the RTT and loss the session already measures.
- Touch-to-click mapping using the normalised coordinates `mouseMoveAbsolute`
  already carries.

Risk: this is where TCP's head-of-line blocking stops being theoretical.

---

## Milestone 4 — file transfer and clipboard images

- Chunked transfer with resume, using the `fileOffer`/`fileChunk` messages
  already reserved.
- Per-transfer content keys derived from the session exporter secret.
- Clipboard images: DIB↔PNG on Windows, `NSPasteboardTypePNG` on macOS.
- Clipboard history with the concealed-content rules already honoured.

---

## Milestone 5 — the long tail of features

**Done:** media control on macOS — transport by synthesising hardware media
keys (so any player responds, not just an enumerated list), volume and mute via
AppleScript, and now-playing read from Music and Spotify.

That last part is limited by Apple, not by effort: `MediaRemote` was the private
framework that exposed universal now-playing, and it was closed to unentitled
processes in macOS 15.4. Asking players directly is the only route left, so
metadata is blank for browsers and anything not enumerated. Playback control
still works with all of them, because media keys are routed by the system.

**Remaining:** Windows media control via `GlobalSystemMediaTransportControls`
(a WinRT interface, so it needs a real binding rather than a `lookupFunction`)
· presentation mode · gamepad with gyroscope · quick actions and the custom
command registry · Wake-on-LAN · multi-monitor enumeration · notifications.

Each is small on its own. They are grouped because none of them changes the
architecture.

---

## Milestone 6 — platform expansion

- **Linux desktop.** `libei`/XTEST for input, PipeWire for capture. The
  `InputBackend` interface already anticipates it.
- **Browser client.** Would need the WebSocket transport that ADR 0001
  deliberately did not build. `FramedConnection`'s interface is the seam.
- **Wear OS / watchOS.** Media and presentation control only.

---

## Deliberately not planned

**Cloud relay and remote internet access.** The brief lists them as future
features, and they are technically straightforward — but they change the
product from "a thing on your LAN" into "a service that can reach your desktop
from anywhere", which is a different security posture, a different threat
model, and an operational commitment. It should be a deliberate decision with
its own ADR, not an increment.

**AI assistant and voice commands.** No clear user problem yet. Adding them
before there is one produces a feature nobody asked for and a permission prompt
everybody resents.
