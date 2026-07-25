# ADR 0001 — Discovery over UDP multicast, transport over raw TCP

**Status:** accepted · **Date:** 2026-07-25 · **Milestone:** 1

## Context

The phone must find the desktop with no IP entry, and then hold a connection
whose latency budget is under 10 ms end to end for cursor movement. Two
independent decisions, made together because they share the constraint.

## Decision A — discovery

Custom UDP beacons on multicast `239.255.78.10:47810`, with directed broadcast
as a fallback.

### Options

**mDNS / DNS-SD (Bonjour)** — the obvious, standard answer, and the first
design. Rejected because:

- Dart's `multicast_dns` can *browse* but not *publish*. Advertising would need
  Bonjour on macOS and either the Bonjour service or a hand-written responder on
  Windows — a native dependency on precisely the platform where users are least
  likely to have it installed.
- All the metadata would live in DNS-SD TXT key-value pairs anyway, so the
  parsing work is identical. Only the framing differs.
- Latency is worse. mDNS query/response goes through the platform resolver's
  caching and backoff; a direct query datagram is answered in one round trip,
  typically under 50 ms.

**SSDP** — HTTP-over-UDP. Verbose, no advantage here, and shares the multicast
filtering problems without the interoperability payoff.

**Manual IP entry with a QR shortcut** — reliable and trivial, but it fails the
product's central promise. "It just works" is the feature.

### Consequences

- **Lost:** no third-party Bonjour browser will see a RemoteLink desktop.
  Acceptable for a closed protocol where both endpoints ship together.
- **Gained:** zero native dependencies, sub-50 ms discovery, and full control of
  the payload.
- **Mitigated:** `DiscoveryBackend` is an interface. A DNS-SD backend can be
  added later without the UI or connection layer changing.

The client binds one socket **per network interface** rather than a single
wildcard socket. This is not paranoia — a laptop routinely has Wi-Fi, Ethernet,
and several virtual adapters (Docker, VPN, VirtualBox), and a wildcard multicast
join lands on whichever the OS picks, frequently a virtual adapter that reaches
nothing. This is the difference between "sometimes finds my PC" and "always
finds my PC".

## Decision B — transport

Raw TCP with `TCP_NODELAY` and a four-byte length prefix.

### Options

**WebSocket** — would bring a browser client for free. Rejected on latency:

- The HTTP upgrade handshake adds a round trip to every connect, and reconnect
  time is a headline requirement.
- RFC 6455 requires client-to-server frames to be XOR-masked, so every byte of
  every mouse event gets copied and transformed on a phone.
- Its framing duplicates what the length prefix already does, buying nothing.

**QUIC** — genuinely attractive: multiplexed streams would let bulk file
transfer stop head-of-line-blocking cursor movement, and connection migration
would survive a Wi-Fi handoff without reconnecting. Rejected for milestone 1
only because Dart has no mature QUIC implementation, and adding one is a larger
project than the rest of this milestone. **This is the most likely transport
change in the product's life.**

**UDP with a custom reliability layer** — best possible latency for input, but
reimplementing congestion control and retransmission correctly is a
multi-month project with a long tail of subtle bugs. The planned compromise is
TCP for the control channel plus a UDP side-channel for lossy input only,
sharing the same session keys. `MessageType.isLossy` already marks which
messages qualify.

### Consequences

- Head-of-line blocking is real: a large clipboard image will delay cursor
  updates behind it. Mitigated today by coalescing lossy messages under
  backpressure — several pending mouse deltas fold into one, so the cursor
  arrives where the finger is rather than replaying the gesture late. Solved
  properly by the UDP channel or by QUIC.
- Nagle's algorithm is disabled. It would hold a 22-byte mouse event back to
  coalesce it, saving 18 bytes of header at the cost of up to 40 ms — the single
  most visible latency bug this protocol could have.
- Header and body are written in one `add` so the OS emits one segment.
  Writing the prefix separately would produce two packets per mouse move.
