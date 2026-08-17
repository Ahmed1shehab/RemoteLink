# RemoteLink wire protocol, version 1

This is the normative specification. Where it and the code disagree, this
document is wrong and should be fixed — but the code is expected to match.

All multi-byte integers are **big-endian** ("network order"). This costs
nothing on either platform and makes a packet capture readable without
byte-swapping in your head.

---

## 1. Layering

```text
┌─────────────────────────────────────────┐
│ Message      typed payload (§4)         │
├─────────────────────────────────────────┤
│ Frame        20-byte header + payload   │  §3
├─────────────────────────────────────────┤
│ AEAD record  ChaCha20-Poly1305          │  §6  (after handshake)
├─────────────────────────────────────────┤
│ Length prefix  u32                      │  §2
├─────────────────────────────────────────┤
│ TCP                                     │
└─────────────────────────────────────────┘
```

Note the ordering: the **entire frame, header included, is encrypted**. An
observer on the network learns only that a record of some size was sent. If
headers were outside the AEAD, a stream of 22-byte records at 120 Hz would
announce "the user is moving the mouse right now" to anyone watching.

---

## 2. Record framing

```text
+--------+------------------+
| u32 N  | N bytes          |
+--------+------------------+
```

TCP is a byte stream, not a message channel: one `write` can arrive as three
reads and three writes can arrive as one. The length prefix is the minimal
correct fix — self-describing, no escaping, no delimiter scanning, and the
receiver knows exactly how much to buffer before it has to interpret anything.

`N` must not exceed **17 MiB** (`kMaxRecordSize`). A record above the cap is a
protocol violation and the connection closes without allocating. This limit
exists for the pre-authentication window specifically: before the handshake
completes, anyone who can reach the port can send four bytes, and without a cap
those four bytes would request a 4 GiB allocation.

---

## 3. Frame header

Fixed 20 bytes.

| Offset | Size | Field             | Notes |
|--------|------|-------------------|-------|
| 0      | 1    | `version`         | 1 |
| 1      | 2    | `type`            | §4 |
| 3      | 4    | `sequence`        | wraps at 2³² |
| 7      | 8    | `timestampMicros` | sender's monotonic clock |
| 15     | 1    | `flags`           | below |
| 16     | 4    | `payloadLength`   | ≤ 16 MiB |
| 20     | N    | `payload`         | |
| 20+N   | 4    | `crc32c`          | only if `hasChecksum` |

### Flags

| Bit | Name           | Meaning |
|-----|----------------|---------|
| 0   | `compressed`   | payload is raw DEFLATE |
| 1   | `requiresAck`  | sender wants an `ack` |
| 2   | `isAck`        | this frame is an acknowledgement |
| 3   | `hasChecksum`  | CRC-32C trailer present |
| 4   | `fragment`     | part of a multi-frame message |
| 5   | `lastFragment` | final fragment |

### On `timestampMicros`

Never compared across devices — the two clocks are unrelated and no
synchronisation is assumed or required. It is echoed back in `pong`, so the
originator computes round-trip time entirely against its own monotonic
timeline. This removes a whole class of "negative latency" bugs that arise the
moment you try to compare two machines' clocks.

### On `sequence`

Used to correlate acknowledgements and detect reordering on the (planned)
unreliable channel. It is **not** a replay defence — that is the AEAD nonce
counter's job, enforced independently in `rl_crypto`.

### On the checksum

CRC-32C (Castagnoli, reversed polynomial `0x82F63B78`), chosen over CRC-32
because it detects errors better on short frames and has a hardware
instruction available for a future fast path. It is a *corruption* check only.
Once the AEAD is established, Poly1305 provides authentication and the flag is
left off to save four bytes per frame.

---

## 4. Message types

Codes are grouped by subsystem so a capture is readable and routing can switch
on the high byte.

| Range    | Subsystem |
|----------|-----------|
| `0x00xx` | session control |
| `0x01xx` | pairing and trust |
| `0x02xx` | pointer input |
| `0x03xx` | keyboard input |
| `0x04xx` | clipboard |
| `0x05xx` | media |
| `0x06xx` | screen streaming |
| `0x07xx` | file transfer |
| `0x08xx` | system and power |
| `0x09xx` | device management |
| `0x0Axx` | presentation |
| `0x0Bxx` | gamepad |

**Codes are append-only and never reused.** A value that shipped keeps its
meaning forever; a retired message becomes reserved rather than being recycled.
This is what lets an old client talk to a new server safely.

---

## 5. Versioning and compatibility

Three rules, and they are what make minor protocol changes non-breaking:

1. **Unknown message types are ignored, not fatal.** A v1 build receiving a
   v1.1 message logs and drops it.
2. **Trailing bytes in a known payload are ignored.** Decoders read the fields
   they know and stop; a newer peer may have appended more.
3. **`version` is bumped only when an older build cannot parse the frame at
   all.** Adding a message type or appending a field does not qualify.

Version negotiation happens in the hello exchange: the client advertises
`[minVersion, maxVersion]`, the server picks the highest it also supports, and
a non-overlapping range is a clean, immediate failure rather than a confusing
one later.

---

## 6. Handshake

A simplified Noise XX pattern. Five records, roughly 2.5 round trips — under
5 ms on a LAN.

```text
1  client → server   ClientHello                       plaintext
2  server → client   ServerHello                       plaintext
                     ── both derive handshake keys from ee ──
3  server → client   seal(s_s)                         encrypted
                     ── both derive master from ee‖es‖se‖ss ──
4  client → server   seal(s_c ‖ confirm_c)             encrypted
5  server → client   seal(confirm_s)                   encrypted
```

Records 1 and 2 carry ordinary encoded messages. Records 3–5 carry the sealed
blob **as the frame payload**, with type `handshakeFinish` and no inner message
encoding — the state machine already knows what each step must be, and a type
tag there would only be a field an attacker could vary.

### Why this shape

* **Ephemeral exchange first**, so everything after it is confidential and the
  session has forward secrecy: recovering both long-term keys later does not
  decrypt a recorded session.
* **Static keys never travel in the clear.** A passive observer cannot
  fingerprint which devices are talking. This is the only reason record 3
  exists rather than putting `s_s` into record 2.
* **Mutual authentication is deferred to the last two records**, because
  neither side can compute the static-static term until both statics have
  arrived.
* **Every record is folded into a running transcript hash** used as HKDF salt
  and AEAD associated data, so tampering with any earlier byte breaks every
  later step.

### Key schedule

```text
h₀ = SHA-256("RemoteLink/1/handshake")
h₁ = SHA-256(h₀ ‖ ClientHello)
h₂ = SHA-256(h₁ ‖ ServerHello)

ss_ee    = X25519(e_c, e_s)
k_hs_c2s = HKDF(ikm = ss_ee, salt = h₂, info = "rl1 hs c2s")
k_hs_s2c = HKDF(ikm = ss_ee, salt = h₂, info = "rl1 hs s2c")

h₃ = SHA-256(h₂ ‖ sealed_server_static)

ikm  = ss_ee ‖ ss_es ‖ ss_se ‖ ss_ss
salt = h₃                                  ← frozen here on BOTH sides

k_c2s      = HKDF(ikm, salt, "rl1 data c2s")
k_s2c      = HKDF(ikm, salt, "rl1 data s2c")
confirm_c  = HKDF(ikm, salt, "rl1 confirm c")
confirm_s  = HKDF(ikm, salt, "rl1 confirm s")
resumption = HKDF(ikm, salt, "rl1 resumption")
exporter   = HKDF(ikm, salt, "rl1 exporter")
sas_seed   = HKDF(ikm, salt, "rl1 sas", 8 bytes)
```

The salt being **frozen at h₃** matters and is easy to get wrong. The two sides
reach that point at different places in their own message ordering — the client
after opening the server's static, the server after opening the client's finish.
Salting with the live transcript instead would silently derive different keys on
each side, and the only symptom would be an authentication failure two messages
later that looks nothing like the actual cause.

All four Diffie-Hellman terms are required. Dropping `ss` loses authentication;
dropping `es` or `se` lets an attacker who compromised one long-term key
impersonate the other; dropping `ee` loses forward secrecy.

### Short authentication string

```text
SAS = (u64_be(sas_seed) mod 1 000 000), zero-padded to six digits
```

Eight bytes are folded before the modulo so the bias is around 10⁻¹³ rather
than the 10⁻⁴ a 32-bit source would give.

---

## 7. Record encryption

* **Cipher:** ChaCha20-Poly1305, RFC 8439.
* **Keys:** one per direction, so the two sides can never collide on a nonce
  even though both encrypt concurrently.
* **Nonce:** 12 bytes — four zero bytes then a big-endian u64 counter. Derived
  from a counter rather than randomly, which removes any birthday-collision
  risk and makes the safety property trivially checkable: strictly increasing,
  therefore never repeated.
* **Counter:** implicit. TCP delivers in order, so both sides count the same
  records. Transmitting it would waste eight bytes per frame and hand an
  attacker a field to play with.
* **Rekey:** the connection is closed at 2³² messages under one key. Silently
  wrapping would repeat a nonce and destroy confidentiality outright.

ChaCha20-Poly1305 is preferred to AES-GCM because this runs on phones. Every
modern desktop has AES-NI, but a software AES-GCM fallback on a low-end Android
device is both slower and exposed to cache-timing attacks. ChaCha20 is fast and
constant-time everywhere with no hardware dependency.

---

## 8. Discovery

UDP on port **47810**, multicast group **239.255.78.10**, with directed
broadcast as a fallback for access points that filter multicast between
wireless clients.

Datagrams begin with the four bytes `RLNK`, so an unrelated service on the same
port is discarded in one comparison rather than being parsed.

| Kind       | Direction | Meaning |
|------------|-----------|---------|
| `announce` | server →  | "I am here", every 2 s and on change |
| `query`    | client →  | "who is there?", prompts an immediate answer |
| `goodbye`  | server →  | "I am leaving", so clients drop the entry at once |

A server answers a `query` **directly to the asker**, not to the group. A phone
that just opened the app gets an answer in one round trip and the other twenty
devices on the network are not woken up to ignore it.

The payload is plaintext by necessity — a device that has never paired must be
able to read it — and therefore contains nothing sensitive: a public key
fingerprint, a name the user chose, and an address already visible in every
packet header. Because the advertised `deviceId` is derived from the public key,
a beacon cannot lie about its identity without failing the handshake
immediately afterwards.

See `docs/adr/0001-discovery-and-transport.md` for why this is not mDNS.

---

## 9. File transfer

Subsystem `0x07xx`. The shape follows the
[LocalSend](https://github.com/localsend/protocol) v2.2 model rather than an
invention of our own — it is a proven design for exactly this problem, and its
flow maps almost one-to-one onto the codes reserved here. It is implemented from
their published specification; no LocalSend code is used.

### 9.1 Flow

```text
sender → receiver   fileOffer      transfer id + one entry per file
receiver → sender   fileAccept     session id + a token per ACCEPTED file
sender → receiver   fileChunk      repeated, per file, in offset order
sender → receiver   fileComplete   whole-file SHA-256, per file
either direction    fileAbort      at any point
```

**A declined file is simply absent from the token map.** This is adopted
directly from LocalSend and is better than the obvious alternative: it expresses
partial acceptance without a second message type, and there is no state in which
a file is both accepted and rejected.

### 9.2 Divergences from LocalSend

LocalSend runs over HTTP with TLS, so its session identifier and token travel as
URL query parameters and it offers an optional PIN. None of that applies here:
these messages ride the authenticated, encrypted session of §6 and §7. The
per-file token is therefore a **replay guard inside an already-authenticated
channel**, not the primary authentication, and there is no PIN because the SAS
comparison at pairing time already did that job.

### 9.3 Payloads

`fileOffer` carries a transfer id and a count-prefixed list of file entries:

| Field | Type | Notes |
|---|---|---|
| `fileId` | string | ≤ 128 bytes, unique within the transfer |
| `fileName` | string | ≤ 255 bytes, **sanitised — see §9.5** |
| `size` | u64 | bytes |
| `fileType` | string | MIME type, ≤ 255 bytes |
| presence bits | u8 | bit 0 `sha256`, bit 1 `modifiedAt`, bit 2 `accessedAt` |
| `sha256` | 32 bytes | present only if bit 0 |
| `modifiedAt` / `accessedAt` | u64 | microseconds since epoch, UTC, if their bit is set |

At most **1024** files per offer, and a chunk payload is capped at **1 MiB**.
Both are checked before allocating, as §2 requires of every length on the wire.

`fileAccept` carries the transfer id, a session id, and a count-prefixed map of
`fileId → token`. `fileChunk` carries transfer id, session id, file id, token,
a u64 offset, length-prefixed bytes, and a CRC-32C of those bytes.
`fileComplete` carries transfer id, file id, and the 32-byte whole-file digest.
`fileAbort` carries the transfer id, an optional file id, and a reason:
`declined`, `cancelled`, `ioError`, `hashMismatch`, `tooLarge`, `timeout`.

### 9.4 Per-transfer encryption

Chunks are sealed a second time, under a key derived per transfer:

```text
k_transfer = HKDF(ikm = exporter, salt = "", info = "rl1 file " ‖ transferId)
nonce      = u32_be(fileIndex) ‖ u64_be(offset)
aad        = transferId ‖ 0x00 ‖ fileId ‖ 0x00 ‖ offset
```

Two things about this are load-bearing.

**The nonce is supplied by the caller**, which §7 deliberately forbids for the
session cipher. It is safe here only because it is *structural rather than
chosen*: `(fileIndex, offset)` is unique by construction within a transfer, and
each transfer has its own key. The associated data binds the identifiers as
well, so a chunk cannot be replayed into a different file or a different offset
even within the same transfer.

**The exporter secret is per session.** A transfer resumed after a reconnect
therefore derives a *different* key, which is what makes re-sending an offset
safe. Encrypting different bytes at the same offset under the same key would be
a catastrophic nonce reuse; the per-session derivation is what prevents it, and
any future change that lets a sender re-read a file mid-transfer must preserve
that property.

Deriving per transfer also keeps a long file out of the session's own nonce
space, and means a compromised transfer key does not expose the session.

### 9.5 Filenames are hostile input

`fileName` arrives from a peer and becomes a path on disk. It is the highest-risk
field in the protocol, and it passes through one sanitiser with no bypass. That
sanitiser rejects:

- path separators, in either direction, and `..` in literal, mixed-case, nested,
  and repeatedly percent-encoded forms
- over-long UTF-8 encodings of `.`
- absolute paths and drive-rooted paths
- Windows reserved device names — `CON`, `PRN`, `AUX`, `NUL`, `COM1`–`COM9`,
  `LPT1`–`LPT9` — with or without an extension, case-insensitively
- trailing dots and trailing spaces, which Windows strips silently, turning two
  different names into one file
- control characters, and anything over 255 bytes encoded

Accepted names are normalised to Unicode NFC **once**, in the decoder. The
filesystem layer does not normalise again — one canonicalisation point, so two
spellings cannot diverge between the check and the write.

Containment is enforced structurally rather than by inspecting strings: peer and
transfer identifiers become SHA-256-derived internal names, every path is
canonicalised and checked against the canonical root, pre-existing symlinks at
the destination are refused, and final names are reserved atomically.

---

## 10. Keyboard representation

The canonical key identity on the wire is the **USB HID usage ID** (usage page
`0x07`). Neither platform's native codes are a superset of the other, so
picking one would force a lossy translation on the sender — which cannot even
know the receiver's OS until the handshake completes.

Each desktop backend maps a usage to whatever its OS treats as that key's
identity for shortcut purposes: a Windows virtual-key code, an ANSI `CGKeyCode`
on macOS. Both resolve shortcuts layout-independently, so Ctrl+C is Copy on a
French keyboard as well as a US one.

Text that genuinely depends on the layout — accented characters, emoji, CJK
composed in the phone's own IME — does not use this path at all. It goes
through `textInput`, which injects Unicode directly and bypasses keycodes
entirely.

Named shortcuts (`copy`, `taskManager`, …) travel as *intent* rather than as
keystrokes, and the desktop resolves them. That is why the phone ships one Copy
button rather than a per-platform branch.

---

## 11. Monitor topology

`screenTopology` (`0x0605`) is the desktop's description of the desk: for each
monitor an id, an origin, a size, a DPI scale, a primary flag, and a name. It is
sent once on connect and again whenever the layout changes.

```text
count        varuint, refused above 32 before anything is allocated
per monitor:
  id         varuint, never 0
  x, y       varint (zig-zag — a monitor left of the primary has a negative x)
  width      varuint
  height     varuint
  scale      float32
  flags      uint8, bit 0 = primary
  name       length-prefixed UTF-8, through `sanitiseDeviceName` on the way in
```

It is the only implemented code in the `0x06xx` range. `screenStreamStart`,
`screenStreamStop`, `screenFrame`, and `screenConfigure` are still declared and
decode as opaque bytes; they land with screen streaming itself.

### Addressing a monitor

`mouseMoveAbsolute` carries `monitorId` as an **appended** field, after the
`displayIndex` that shipped before it. The rules in §5 are what make that safe,
and both directions are tested against a frozen copy of the older decoder in
`mouse_move_absolute_compatibility_test.dart`.

`monitorId == 0` means the whole virtual desktop. That is not an arbitrary
sentinel — it is what a peer that predates the field sends, because the field is
absent from its payload and absence decodes as zero. Giving zero any other
meaning (the primary monitor, say) would change where every deployed phone's
taps land without altering a single byte on the wire, which is the silent kind
of break the append-only rule exists to prevent. A real monitor therefore never
carries id 0, and one that claims it is dropped on decode.

An **id**, not an index: unplugging the first of three monitors renumbers the
rest, so a phone still holding "display 1" would quietly start driving a
different screen. An id that no longer resolves falls back to the virtual
desktop, which is recoverable; addressing the wrong screen is not.

Normalisation is against `extent - 1`, so `1.0` is the last addressable pixel of
that monitor rather than the first pixel of its neighbour.
