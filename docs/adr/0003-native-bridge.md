# ADR 0003 — `dart:ffi` for native desktop integration

**Status:** accepted · **Date:** 2026-07-25 · **Milestone:** 1

## Context

The desktop must synthesise mouse and keyboard input and read the clipboard on
Windows and macOS. The target is under 10 ms from finger to cursor, of which
the network already claims 1–3 ms on a LAN.

## Decision

`dart:ffi` directly to `user32.dll` and Core Graphics. Hand-written bindings,
not `ffigen`. Both backends compiled into every build, selected at run time.

## Reasoning

### FFI over platform channels

A `MethodChannel` round trip costs roughly 50–150 µs: it hops to the platform
thread and back through a message codec. At 240 Hz that is up to 3.6% of a core
spent purely on marshalling — but the throughput is not the real problem. The
problem is **jitter**: the platform thread is shared, so the hop's cost varies
with whatever else is scheduled, and variable latency on the cursor path shows
up as stutter. An FFI call into `SendInput` is a direct call costing tens of
nanoseconds with no scheduling involved.

FFI also means these packages are testable with `dart test` and no Flutter
engine, which is why `rl_native` has unit tests at all.

### Hand-written bindings over ffigen

The entire surface is six structs and about thirty functions. A hand-written
binding carries the "why" — that `MOUSEINPUT` is 32 bytes on x64 because
`ULONG_PTR` forces 8-byte alignment; that `KEYEVENTF_EXTENDEDKEY` is what keeps
right Alt behaving as AltGr — and a regenerated file would erase all of it on
every run. If this grows past a couple of dozen symbols, generate it.

### Run-time selection over conditional imports

Both implementations stay in one binary and both compile on every platform's
analyzer run. The cost is a slightly larger binary. The benefit is that a
change to the Windows backend cannot silently break on a macOS developer's
machine — which is exactly the failure mode conditional imports produce, and it
surfaces in CI rather than in the developer's editor.

## API-specific decisions

**`SendInput`, not `mouse_event`/`keybd_event`.** It is the only Windows API
that submits several events atomically. Sending Ctrl-down and C-down as two
calls lets a context switch land between them, and the application sees a bare
`C` before the modifier arrives.

**`CGEventPost`, not the Accessibility API.** `AXUIElement` actions depend on
each app exposing accessibility metadata, which games, Electron apps, and
anything drawing its own UI generally do not.

**`kCGHIDEventTap`, not the session tap.** Posting at HID level makes events
behave like real hardware: they pass through the window server's full
processing, respect the active layout, and reach every application.

**Counter polling, not clipboard notifications.** Windows offers
`AddClipboardFormatListener`, which needs a hidden window and a message loop.
`GetClipboardSequenceNumber` is one cheap system call, so a 50 ms poll is
immeasurable CPU and comfortably meets the sub-100 ms target. On macOS,
`NSPasteboard.changeCount` is the same trick — and there AppKit offers no
change notification at all, so it is not merely simpler, it is the only option.

## Consequences and risks

- **Manual memory management.** Core Foundation is reference counted and Dart's
  GC knows nothing about it. Every `CGEventCreate*` is released in a `finally`;
  missing one leaks a few hundred bytes per event, which at 120 Hz is ~3 MB per
  minute — a leak that only shows up after an hour and is miserable to find.
- **Struct layout is a correctness dependency.** Dart FFI computes the C ABI
  layout from field types, so `MOUSEINPUT` and `INPUT` are right on x64 and
  arm64. A 32-bit target would need re-checking.
- **Objective-C via `objc_msgSend` is the highest-risk code in this repository,
  and it has already cost one crash.** Two distinct hazards, both silent:

  1. **A wrong signature is an ABI mismatch, not a compile error.** Each call
     shape needs its own `lookupFunction` typedef, and getting one wrong
     corrupts registers rather than failing to build.

  2. **There is no ARC.** Objects returned by methods that are not `alloc`,
     `new`, `copy`, or `mutableCopy` are *autoreleased*, and the main thread's
     runloop drains its pool every iteration. Storing such a reference in a
     field without retaining it produces a pointer that is valid for the rest
     of the current callback and dangling forever after.

     This happened: `MacosClipboardBackend` cached the result of
     `+stringWithUTF8String:` and used it on a later event-loop turn. The
     failure surfaced as `EXC_BREAKPOINT` inside `-[NSArray containsObject:]`
     — ARM64 pointer authentication catching a freed object's `isa` — roughly a
     minute after launch, the first time the clipboard changed. Nothing in the
     Dart layer could have caught it, and nothing in the crash pointed at the
     line that cached the object.

     **Rule for this file:** any Objective-C object stored beyond the call that
     produced it must be `objc_retain`ed and released in `dispose`. Objects
     consumed within one synchronous call need nothing. Class objects and
     exported framework constants are permanent and are exempt.

  If this surface grows past the clipboard, the balance tips toward a small
  Swift plugin over a platform channel: the added native code buys ARC, and
  ARC removes hazard 2 entirely. That trade is not worth it for six selectors;
  it clearly would be for sixty.
- **Permission failures are silent on macOS.** Without Accessibility
  permission, every `CGEventPost` does nothing at all — no error, no exception.
  `AXIsProcessTrusted` is checked up front so the app can explain, instead of
  the user facing a remote that looks connected and does nothing.
- **UIPI is a hard ceiling on Windows.** An unelevated process cannot inject
  into an elevated one. This is Windows working correctly, not a bug to route
  around, and it is surfaced as a message rather than as dropped keystrokes.
