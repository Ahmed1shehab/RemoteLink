# ADR 0005 — A phone can listen

**Status:** accepted · **Date:** 2026-09-10 · **Milestone:** 1

## Context

Until this change the phone was a pure client. It dialled a computer, and
everything it could do was something it asked that computer to perform. The
shape was load-bearing in more places than it looked: `sendFiles` put an offer
on `client.session`, and there was exactly one of those, so the Send screen
offered one destination and the transfer controller never had to ask which
connection a message belonged to.

Sending a file from one phone to another does not fit that shape. A transfer
needs one end listening, and neither phone was ever the end that listens. The
gap showed up as a feature request phrased as a UI complaint — the Send screen
was confusing — but no amount of rearranging it could produce a second device
to send to.

The transport had the missing half already. `RemoteLinkServer` is in
`rl_transport` and knows nothing about desktops; `bonsoir` publishes a DNS-SD
record from iOS and Android as readily as from macOS; the handshake, the trust
store and the six-digit confirmation are all in `packages/` and all
platform-neutral. What was missing was an owner for them inside the phone app,
and a decision about what a listening phone is willing to be asked to do.

## Decision

The phone runs `RemoteLinkServer`. `PhoneHostService`
(`apps/mobile/lib/src/features/host/`) owns it, advertises over Bonjour,
answers pairing requests with the same SAS flow the desktop uses, and writes
accepted peers into the same trust store the phone already keeps.

Three constraints shape it.

**The listening phone denies by default, per message.** `isAllowedFromPeer` is
the phone's answer to `CommandDispatcher`, and CONTRIBUTING §4 applies to it
unchanged: a paired device is untrusted input however it authenticated. The
list has two entries — file transfer, and clipboard text — and is written as a
switch with a `default` arm so that adding a message type to the protocol
cannot silently widen what a phone accepts. A `KeyEvent` arriving at a phone is
not a feature waiting to be built; it is a message that should never have been
sent.

**A host advertises what it can host, not what it can drive.** As a client the
phone advertises `mouse` to mean "I can send pointer events". As a host the
same bit would mean "you may move my cursor", which nothing on this end can
honour. `kPhoneHostCapabilities` is therefore much narrower than
`kMobileCapabilities`: clipboard text, file transfer, compression. The
intersection between two phones is exactly those, which is also what makes the
control screen's tab list come out right without a special case — see
`visibleTabs`.

**Sessions are addressed by peer, never by "the" session.** `PeerLink` names a
device this phone can reach, and `MobileTransferController._sessionFor`
resolves the session from the peer id at the moment it sends. Nothing in the
widget layer holds a `Session`: partly because a screen has no business holding
a transport object, and partly because a `Session` cannot be constructed
without a socket, which would have made the send UI untestable.

## Consequences

Discovery now has to exclude this phone from its own results. It advertises
itself, and a browser cannot tell its own record from anyone else's, so without
the filter in `discoveredDevicesProvider` the device list opens offering to
connect the phone to itself.

Both questions a nearby device can ask — "may I pair" and "will you take this
file" — are raised from the app root rather than from a screen. This fixed a
defect that predates phone-to-phone: an incoming offer was only ever asked
about on the Send tab, so a transfer that arrived while the user was on the
touchpad produced nothing at all and the sender watched it time out.

Receiving is on by default and can be switched off in Settings › Receiving. On
by default because "open Settings first" is where the conversation between the
person sending and the person receiving stops. Switchable because being listed
on a network is itself something a person may object to, even though nothing
can arrive unasked.

## What this does not do

**No continuous clipboard sync between phones.** The desktop's two-way sync
carries a Lamport clock and an echo guard tuned for exactly one peer;
generalising it to N peers is a separate piece of work with its own failure
modes. Text sent between phones is a one-shot `ClipboardUpdate`, not a
subscription.

**No control of one phone from another.** The capability set says so and the
allow-list enforces it. `Capabilities.phoneControl` remains what it was: a bit
the phone advertises only when a backend exists that can honour it, and none
does.

**No background hosting on iOS.** The listening socket goes away when iOS
suspends the app, which is the platform's decision rather than this app's. The
lifecycle listener is one-directional for that reason — it restores the host on
resume and never stops it on pause, because a user who leaves the app to *pick*
the file they are about to send must not disconnect the device they are sending
to.

## Rejected options

### Routing phone-to-phone transfers through the computer

Rejected. It would have required a computer to be present and paired with both
phones, which is not the situation the feature is for, and it would have put
the file on a third machine's disk on the way past.

### A separate, simpler protocol between phones

Rejected. The existing one already carries file transfer, is already
implemented on both ends, and already has an authenticated handshake with a
verified short authentication string. A second protocol would have meant a
second trust store, a second pairing flow, and a second set of decoder
hardening — for a payload the first one already carries.

### Hosting only while a "Receive" screen is open

Rejected as the default, in the AirDrop shape. It makes receiving a mode the
user has to enter before the sender can find them, which requires the two
people to coordinate out of band about an app that exists so they do not have
to. The Settings switch covers the case where being invisible is what is
actually wanted.
