# Phone to phone

Two phones, one Wi-Fi network, no computer in the middle and no account
anywhere. A phone finds another phone the same way it finds a computer, is let
in the same way, and can then do exactly two things: **send files** and **send
text**.

This document is the feature. [ADR 0005](adr/0005-a-phone-can-listen.md) is the
decision behind it — why a phone listens at all, and what was rejected — and
[PROTOCOL.md](PROTOCOL.md) is the wire format. What follows is what the feature
does, what it deliberately does not, and where each part lives.

---

## 1. Why it is only two things

A phone hosting is not a small desktop. `kPhoneHostCapabilities` claims three
bits — clipboard text, file transfer, compression — against the dozen or more a
computer offers, and the difference is not a backlog. A capability bit is a
claim about what *this* end takes part in, and the two ends keep only the
intersection:

| | phone as client | phone as host | negotiated between two phones |
|---|---|---|---|
| `mouse` / `keyboard` | claimed | not claimed | absent |
| `mediaControl` | claimed | not claimed | absent |
| `screenCapture` | — | not claimed | absent |
| `clipboardText` | claimed | claimed | **present** |
| `fileTransfer` | claimed | claimed | **present** |

As a client the phone says `mouse` to mean "I can send pointer events". As a
host the same bit would mean "you may move my cursor", which nothing on a phone
can honour. So the control screen between two phones comes out with exactly two
tabs — Send and Clipboard — with no special case anywhere in the UI:
`visibleTabs` filters the tab list by the negotiated set, and the negotiation
already did the work.

The capability set is a claim, not a control. The control is
`isAllowedFromPeer` in `phone_host_service.dart`, which checks every arriving
message against a two-entry list and denies by default, per message, exactly as
`CommandDispatcher` does on the desktop. CONTRIBUTING §4 applies unchanged here:
a paired device is untrusted input however it authenticated. A `KeyEvent`
arriving at a phone is not a feature waiting to be built; it is a message that
should never have been sent.

---

## 2. Finding each other

A phone that is receiving does what a computer does:

* **Bonjour / DNS-SD**, service type `_remotelink._tcp`, published by
  `PhoneAdvertiser`. This is the whole story on iOS — the UDP beacon needs the
  multicast entitlement Apple grants by written application — so where the
  desktop treats Bonjour as the second of two routes, a phone treats it as the
  first and, on one platform, the only one.
* **The UDP beacon**, attempted anyway and allowed to fail. On Android it
  works and adds a second route on networks where DNS-SD is filtered.

The record carries the same `Beacon` the desktop's does: device id, name,
platform, the port actually bound (`kPhoneHostPort`, 47812, or whatever the OS
gave it instead), protocol version, a truncated key fingerprint, the capability
set and whether it is accepting new pairings.

Both phones appear in each other's device list, merged with the trust store by
the same code that lists computers — the user does not care how a device was
found, only whether they can reach it. A phone excludes its own record from its
own results (`discoveredDevicesProvider`); without that filter the list opens
offering to connect the phone to itself.

**Receiving is on by default** and switches off in Settings › Receiving. On by
default because the person who wants to receive a photo is mid-conversation
with the person sending it, and "open Settings first" is where that
conversation stops. Switchable because being *listed* on a network is itself
something a person may object to, even though nothing can arrive unasked.

---

## 3. Being let in

Two gates, in this order, and they answer different questions.

### First time: six digits

Identical to pairing with a computer, because it is the same code. The
handshake produces a short authentication string derived from both ephemeral
keys; both phones show the same six digits, and an attacker relaying the
connection necessarily holds two key agreements and cannot make both
transcripts hash alike. The dialling phone shows `PairingScreen`; the answering
phone raises a sheet from the app root, so it is asked wherever the user
happens to be rather than only on the Send tab.

The name on that sheet is the device id, never the name the device sent. A name
is the one thing an unpaired stranger controls completely, and rendering
"Ahmed's iPhone" above a code the user is about to approve is precisely the
confusion the code exists to defeat.

Approving writes a `TrustedPeer` built from the handshake result — the 32-byte
static key the peer *proved*, not the 8-byte fingerprint from the beacon and
not anything it claimed.

### Every time after: allow this connection

Pairing is a promise about a device, not a standing invitation to whoever is
holding it — and a phone is handed around far more than a computer is. So a
paired device that connects again is held at the door until someone allows it:

```text
handshake completes, session HELD (nothing but 0x00xx/0x01xx passes)
  host → peer   ConnectionRequest(name, timeoutSeconds)
  the user allows, refuses, or the window expires
  host → peer   ConnectionDecision(allowed | declined | timedOut)
```

The sheet says the name from the **trust store** — the one the user chose when
they paired — and shows no digits, because there is nothing left to compare:
the handshake already verified the stored key. A code a user cannot check is a
code they learn to approve.

Asked **once per device per run of the app**, not once per connection: a
phone's link drops every time the screen locks, and a prompt on each of those
would be tapped away unread. Switch it off in Settings › Receiving if the
phone lives somewhere nobody else can reach it.

The waiting end is told it is waiting. A held session drops everything outside
the handshake and trust subsystems, so without `ConnectionRequest` the sending
phone would show a working-looking app whose every action silently went
nowhere.

---

## 4. Sending files

The sending phone picks files, the receiving phone is asked, and the bytes move
directly between them.

* **Offer.** `FileOffer` names each file, its size and its hash. It is
  addressed to a peer, not to "the" session: `MobileTransferController`
  resolves the session from the peer id at the moment it sends, because a phone
  that can listen can have several links at once and sending an acceptance to
  the wrong one delivers a file to a device under another one's name.
* **Acceptance is explicit.** The receiving phone raises a sheet naming the
  files and their total size — named, not counted, because "3 files" is not
  enough to decide with and deciding is the whole reason the sheet exists.
  Declining, swiping it away and tapping outside are all the same answer.
* **Payload.** Chunks are encrypted per transfer with a key derived from the
  session exporter, so a file is not protected merely by the session that
  carried its offer.
* **Filenames are hostile input** and go through `sanitiseFileName` before
  touching a filesystem. See PROTOCOL.md §9.5.
* **Where it lands.** Photos and videos go to the Photos library; anything else
  opens the share sheet so the user chooses. Recent arrivals stay openable from
  the transfer list.

---

## 5. Sending text

The Clipboard tab sends what is on this phone's clipboard to the device at the
other end as a one-shot `ClipboardUpdate`. The receiving phone writes it
straight to its own clipboard and records it in its clipboard history, through
the same path a computer's text takes — the Lamport clock, the echo guard, the
`isSensitive` refusal and the history entry all happen exactly once per piece
of content, and a second implementation for phones is how those drift apart.

Two limits worth stating plainly:

* **It is one-shot, not a subscription.** The desktop's continuous two-way sync
  carries a clock and an echo guard tuned for exactly one peer; generalising it
  to several peers is separate work with its own failure modes.
* **Text travels from the phone that dialled to the phone that answered.** The
  clipboard controller sends over this phone's *client* connection, and a host
  has none pointed at its guest. To send text the other way, connect the other
  way round. Files have no such asymmetry — a transfer is addressed to a peer
  in either direction.

The "accept text from the other end" switch in Settings is the same one that
governs text from a computer. One preference rather than two, because from the
user's side it is one question.

---

## 6. What this deliberately does not do

* **No control of one phone from another.** No touchpad, no keyboard, no media
  keys, no screen. The capability set does not claim it and the allow-list
  refuses it per message.
* **No pairing by QR between two phones.** A phone can *scan* a code but cannot
  *show* one — `PairingQrDialog` is a desktop screen, and `pairingPayload` is a
  desktop method. Between two phones there is one way in: find the device and
  tap it. Where a network blocks discovery entirely, phone-to-phone therefore
  has no fallback; the computer has one because it has a screen to put a code
  on. Giving a phone the same screen is a contained piece of work and is not
  built.
* **No background hosting on iOS.** The listening socket goes away when iOS
  suspends the app. The lifecycle listener restores the host on resume and
  never stops it on pause — a user who leaves the app to *pick* the file they
  are about to send must not disconnect the device they are sending to.
* **No relay through a computer.** Rejected in ADR 0005: it would need a
  computer present and paired with both phones, which is not the situation the
  feature is for, and it would put the file on a third machine's disk on the
  way past.
* **No answer to `ClipboardRequest`.** A peer may ask a hosting phone for its
  current clipboard and the allow-list lets the message through, but nothing
  answers it. Reading a phone's clipboard is a toast on Android and an alert on
  iOS, and doing that because a peer asked — possibly while the user is looking
  at something else — is a decision nobody has made yet.

---

## 7. Where the code lives

| Piece | File |
|---|---|
| The listening half | `apps/mobile/lib/src/features/host/phone_host_service.dart` |
| What a phone will act on | `isAllowedFromPeer`, same file |
| Bonjour publication | `apps/mobile/lib/src/features/host/phone_advertiser.dart` |
| Providers and the Receiving switch | `apps/mobile/lib/src/features/host/host_providers.dart` |
| The three prompts (pair, allow, accept) | `apps/mobile/lib/src/features/host/nearby_prompts.dart` |
| Waiting at someone else's door | `apps/mobile/lib/src/features/devices/connection_hold.dart` |
| Transfers, addressed per peer | `apps/mobile/lib/src/features/transfer/transfer_controller.dart` |
| Text, both directions | `apps/mobile/lib/src/features/clipboard/clipboard_controller.dart` |
| Admission messages | `packages/rl_protocol/lib/src/messages/admission.dart` |
| Tests | `apps/mobile/test/phone_host_test.dart`, `clipboard_sync_test.dart`, `transfer_test.dart` |
