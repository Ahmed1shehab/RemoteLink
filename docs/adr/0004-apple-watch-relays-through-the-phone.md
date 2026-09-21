# ADR 0004 — The Apple Watch relays through the phone

**Status:** accepted · **Date:** 2026-08-26 · **Milestone:** 1

## Context

The watchOS app is a full-screen trackpad for the computer paired with Remote
Link on the iPhone. Its original design sends packed input intents over
WatchConnectivity; the iPhone forwards them on the authenticated Remote Link
session it already holds.

That relay measures 200–230 ms round trip on physical hardware: one
12-byte binary message in flight, release builds on both ends, and Low Power
Mode off. A wider three-message window raised latency rather than lowering it,
confirming that WatchConnectivity serialises the work and that queue tuning
cannot recover the missing responsiveness. Roughly five pointer updates per
second—or about four at the repeated 230 ms reading—is usable only for coarse
pointing.

A direct watch client was proposed to remove the iPhone from the control path.
It would have used Bonjour discovery and `NWConnection` TCP, with an independent
X25519 identity, trust store, pairing flow, protocol implementation, and
encrypted session.

## Phase 0 evidence

The direct-client proposal had a go/no-go spike before its protocol work. A
temporary server on the Mac echoed 12 bytes over TCP, and a temporary screen in
the physical watch app opened an `NWConnection` to it.

The server was verified listening at `192.168.100.44:45454`. With the iPhone
nearby and its app in the foreground, the watch connection remained in
`.waiting` with POSIX `ENETDOWN` (50, “Network is down”). No payload reached the
server, so there was no round-trip number to record.

This matches Apple's documented platform policy rather than a broken route.
[TN3135: Low-level networking on watchOS](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
states that a normal watch app cannot use low-level networking. An
`NWConnection` is deliberately held in `.waiting` with `ENETDOWN`; `NWBrowser`
and Bonjour are covered by the same restriction. Changing whether the paired
phone is foregrounded, in aeroplane mode, or powered off cannot make the API
available, so the remaining routing conditions were not run.

## Decision

The watch remains a **thin remote for the phone**. It sends movement, clicks,
presses, and releases to the iPhone over WatchConnectivity. The iPhone puts
those intents on its existing Remote Link session to the computer.

The watch does not speak the Remote Link wire protocol, hold its own identity,
pair independently, browse Bonjour, or open a TCP connection. The Phase 0 spike
was deleted after the no-go result.

## Rejected options

### A direct `NWConnection` and Bonjour client

Rejected because public watchOS APIs do not permit either operation for a
normal app. This is stronger than the original concern that watch traffic might
be proxied through the iPhone: the connection is blocked before watchOS chooses
a route. The observed `ENETDOWN` is the exact failure Apple documents.

### Reclassifying the app to obtain low-level networking

watchOS permits low-level networking for specific active audio-streaming, VoIP,
and DeviceDiscoveryUI application-service cases. Remote Link is none of those.
Pretending otherwise would misuse capabilities, constrain the product around an
unrelated execution mode, and produce an app that cannot be shipped honestly.

### A separate HTTP service used through `URLSession`

High-level HTTP networking is available on watchOS, but this would not be a
Swift implementation of the existing Remote Link client. It would require a
second server and wire protocol on the desktop, a discoverable HTTPS endpoint
with a workable certificate story on arbitrary local networks, and a separate
security review. `URLSession` traffic may still be proxied through the paired
iPhone, so it also does not establish that the 200 ms latency problem is solved.
That cost is not justified without a new measurement-led proposal of its own.

### Delegating pairing or copying the phone identity

Rejected because neither changes the unavailable transport. Copying a private
identity between devices would also collapse two trust principals into one and
make revocation ambiguous; delegated pairing would add protocol and UI without
creating a usable session.

## Costs and consequences

- Pointer updates still pay roughly 200 ms round trip through
  WatchConnectivity. The watch remains suitable for coarse pointing, not
  trackpad-quality continuous control.
- The phone must remain reachable. If iOS has suspended its network session,
  the first gesture after idle can be lost while the phone reconnects.
- The relay keeps one message in flight and accumulates movement rather than
  building an unbounded queue. The phone smooths a received movement batch over
  the fast computer hop; this improves visible stepping but cannot remove the
  watch-to-phone delay.
- There is one protocol and crypto implementation rather than a byte-exact
  Swift duplicate, and the watch holds no long-lived Remote Link secrets.
- The watch installs as the iPhone app's companion target, created by
  `apps/mobile/ios/tool/add_watch_target.rb`. It is not a standalone Remote Link
  peer.
- If Apple later permits low-level networking for ordinary watch apps, this
  decision can be revisited. The first step remains a physical direct-RTT spike,
  not a protocol port.
