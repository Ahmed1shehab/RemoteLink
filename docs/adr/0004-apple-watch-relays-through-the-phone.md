# ADR 0004 — The Apple Watch is a remote for the phone, not a second client

**Status:** accepted · **Date:** 2026-08-26 · **Milestone:** 1

## Context

The phone app is a trackpad for a computer on the same Wi-Fi. A watch on the
same wrist is the natural place to want the same trackpad — glance down, move
the cursor, click — without taking the phone out.

A watchOS app cannot be written in Flutter. Whatever is on the wrist is Swift,
and it either speaks the Remote Link protocol itself or it speaks to something
that does.

## Decision

The watch app is a **thin remote for the phone**. It sends intents — "move by
this much", "left click", "scroll this many lines" — to the iPhone app over
WatchConnectivity, and the iPhone puts them on the session it already holds
open to the computer.

The watch never touches the network, never holds a key, and never appears in a
trust store.

## Reasoning

### Against a second protocol client on the watch

Making the watch a peer would mean reimplementing, in Swift: the X25519
handshake, the ChaCha20-Poly1305 session layer with its replay window, the
binary framing, the discovery protocol, and the trust store — every line of
`packages/`, a second time, in a second language, with a second set of bugs in
the part of the system that has the worst failure mode.

It would also mean pairing. Pairing is a six-digit SAS the user compares
between two screens; one of those screens would be 40mm across. And it would
mean the watch had to be on the same Wi-Fi as the computer, which a watch
frequently is not — it is on the phone's Bluetooth, which is precisely the link
this design uses.

### What relaying costs

Stated plainly, because it is real:

**One more hop of latency.** Bluetooth to the phone, then Wi-Fi to the
computer. The watch batches movement at 30 Hz before sending — see
`WatchLink.flush` — because sending one message per touch update does not make
the cursor smoother, it fills the queue and the cursor arrives late and keeps
arriving after the finger has stopped.

**The phone has to be within Bluetooth range.** That is the same constraint as
every other watch app that is not standalone, and the watch says which of the
two links is down rather than a single "not connected" that would send the user
to check the wrong device half the time.

**The phone's session has to be alive.** iOS gives no way for an app to hold a
socket open indefinitely in the background — this is the same limit that means
Remote Link has an Android background service and no iOS equivalent.
`WCSession.sendMessage` does wake the phone app to deliver, so the phone need
not be in the user's hand; but if iOS has torn the socket down, the phone
reconnects on wake and the first gesture after a long idle can be lost. No
architecture available on iOS avoids that, so it is documented rather than
worked around.

### Why the pointer acceleration curve is not applied to watch input

`PointerController`'s acceleration judges speed by the size of each delta. The
watch has already batched a thirtieth of a second of movement into one delta,
so every one of them looks fast, and the curve would make the gentlest drag
leap. The user's *linear* sensitivity is applied and the curve is left to the
path it was tuned for — a finger on the phone's own glass. See
`WatchCommandTranslator`.

## Consequences

- The watch target lives inside `Runner.xcodeproj`, because a watch app must be
  embedded in its companion iPhone app to install at all. It is added by
  `apps/mobile/ios/tool/add_watch_target.rb` rather than by a hand-merged
  `project.pbxproj`, which would not survive the next `pod install`.
- `flutter build ios --simulator` now requires `-d <device-id>`: Flutter refuses
  to guess which paired watch simulator to build for. Device and archive builds
  are unaffected.
- The relay is watched at the app root, next to the background link. iOS
  launches the phone app in the background purely to deliver a message from the
  wrist, and in that launch there is no screen — so a listener owned by any
  screen would not exist at the only moment it was needed.
