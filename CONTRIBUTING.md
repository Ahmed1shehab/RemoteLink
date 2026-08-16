# Contributing to RemoteLink

The rules below are not style preferences. Each one exists because breaking it
causes a specific failure that is hard to see coming, and the reason is given so
you can tell when an exception is genuinely warranted.

---

## Setting up

Requires **Flutter 3.27+** (Dart 3.6+, for pub workspaces).

```bash
flutter pub get           # resolves the entire workspace — one lockfile
```

There is no bootstrap step. The root `pubspec.yaml` declares a native pub
workspace, so one `pub get` resolves every package together. A per-package
`pub get` is not how this repository resolves and will confuse you.

Platform runner directories are `flutter create` output and are not committed:

```bash
./tool/bootstrap_platforms.sh
```

See [docs/RUNNING.md](docs/RUNNING.md) before starting a simulator. It covers the
permissions that fail *silently* when missing, which is the single most common
reason a fresh checkout appears broken.

---

## The four rules

### 1. Nothing below `apps/` imports Flutter

Everything in `packages/` must run under `dart test` with no engine. This is why
the protocol, crypto, and transport tests execute in under a second and can run
in any CI container.

If a feature needs a Flutter plugin, the plugin binding goes in `apps/` and the
logic it drives goes in `packages/`. `SystemInfoBackend` is the pattern to copy:
an interface plus platform implementations in `rl_native`, consumed by the app.

### 2. The dependency direction is one-way

```text
rl_core ← rl_protocol ← rl_crypto ← rl_transport      rl_native ─┘
```

Nothing points backwards. `rl_protocol` must never import `rl_transport`; a
message type cannot know about sockets.

Adding a dependency to `rl_core` or `rl_protocol` deserves real scrutiny — they
sit beneath everything else, so a package that stops resolving there takes the
whole repository with it. This has already happened once: an aspirational
`riverpod_generator` entry dragged in an `analyzer` → `macros` → `_macros` chain
that stopped resolving on Dart 3.7+. Prefer the SDK, then a Dart-team package,
then nothing.

### 3. Wire codes are append-only

A `MessageType` value that has shipped keeps its meaning forever. A retired
message becomes reserved; it is never recycled. Adding a field means *appending*
to a payload, because decoders read the fields they know and ignore trailing
bytes.

This is the entire basis of the compatibility guarantee in
[docs/PROTOCOL.md](docs/PROTOCOL.md) §5 — an old build can talk to a new one
safely only because these rules hold. Renumbering a code to tidy the enum breaks
every deployed device silently.

### 4. Permission checks live on the desktop, per message

`CommandDispatcher` is the security boundary. Hiding a button in the phone UI is
a usability affordance, not a control: the phone is untrusted input regardless of
how it authenticated, because a paired device can be compromised, borrowed, or
running a modified client.

`PermissionTier.allows` denies by default. Adding a message type forces an
explicit decision there, and the table-driven dispatcher test will fail until you
make one. That failure is the feature.

---

## Treat peer input as hostile

Every field in every message arrived over a network from a device you do not
control. The decoders reflect that and new ones must too:

- Check declared counts and lengths **before** allocating. A four-byte length
  field must never be able to request a gigabyte.
- Anything that becomes a **filename** goes through `sanitiseFileName`. Anything
  that becomes a **display name** goes through `sanitiseDeviceName`. Do not write
  a third validator, and do not bypass either.
- Remember where a string ends up. A device name is rendered in the desktop UI
  *and* written to logs, which is why ANSI escapes and bidi overrides are
  rejected — one is terminal injection, the other is display spoofing.
- Constant-time comparison (`Primitives.constantTimeEquals`) for anything
  secret-adjacent. A `==` on lists exits at the first differing byte, and that
  timing difference is enough to forge a MAC one byte at a time.

---

## Testing

```bash
./tool/verify.sh          # format, analyze, every suite
```

Coverage is concentrated where correctness is hard to eyeball — adversarial
protocol input, the handshake driven end to end in memory, an explicit
machine-in-the-middle test asserting the two SAS values differ, the replay
window, and TCP framing under fragmented and coalesced reads. Match that
standard: a happy-path test for a decoder that parses hostile input is not
coverage.

Two habits worth keeping:

**Do not bind fixed ports or sleep on the wall clock in a test.** Both make a
suite that passes alone and fails when anything runs beside it. The repository
injects `Clock` for exactly this reason, and a timer body should be reachable
directly rather than only through a service that opens sockets.

**A test that cannot fail is worse than no test**, because it reports green. If
you write one to prove a bug is fixed, run it against the unfixed code first and
watch it fail.

---

## Commits

Explain *why*, not *what* — the diff already shows what changed. A commit that
says "fix clipboard race" is worth less than one that says which race, what it
looked like to the user, and why the chosen fix is right where the obvious one
is not.

Do not commit build output. `.dart_tool/` and `build/` are ignored; they embed
absolute paths from the machine that generated them and produce a conflict on
every merge.

---

## Licence

**This project currently has no `LICENSE` file**, which means it is
all-rights-reserved by default regardless of intent. That needs a decision from
the owner before outside contribution is meaningful, and before any third-party
code can be incorporated — notably for the planned LocalSend compatibility work,
where Apache-2.0 attribution and NOTICE obligations would attach.

Until then, treat contributions as being made with no licence grant in place.

---

## Security

Do not open a public issue for a security problem. See
[docs/SECURITY.md](docs/SECURITY.md), which documents the threat model and, more
usefully, what is deliberately *not* defended against.
