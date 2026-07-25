# ADR 0002 — Riverpod for application state

**Status:** accepted · **Date:** 2026-07-25 · **Milestone:** 1

## Context

Both apps need dependency injection and reactive state. The brief named
Riverpod and Bloc and asked for one to be chosen and used consistently.

## Decision

Riverpod 2.x in both apps. Domain state machines stay outside it as plain Dart.

## Reasoning

The deciding question is what shape this application's state actually has.

**Most of it is derived streams, not state machines.** Discovered devices,
connection state, link quality, clipboard status, connected peers, pairing
requests — every one is a stream from a lower layer that the UI observes and
occasionally combines. Riverpod expresses that as one provider per stream, with
`ref.watch` handling composition and disposal. The same in Bloc needs an event
class, a state class, and a mapper for each — roughly three times the code for
state that has no transitions worth modelling.

**The DI matters more than the state management here.** Six packages need to be
wired with an injectable clock so timing is testable, a trust store that is
async to construct, and an identity that must be generated once and reused.
Riverpod's providers are compile-checked DI with scoped overrides, so a test
replaces `clockProvider` with a `FakeClock` in one line. Bloc has no DI story
of its own and would need `get_it` alongside it — two libraries where one does.

**The genuine state machines are not in the UI layer at all.** The handshake,
the reconnect supervisor, and the session lifecycle are the complex stateful
parts of this system, and they live in `rl_crypto` and `rl_transport` as plain
Dart with no state-management dependency. They are tested by driving them
directly, with no widget tree and no library. Bloc's main advantage — explicit
modelling of complex transitions — would apply to code that deliberately does
not use it.

## What Bloc would have been better at

Honestly: the pairing flow. It has real states (idle → awaiting user → awaiting
peer → completed/failed) with guarded transitions, and a Bloc would document
those transitions more legibly than a `StateProvider` does. That is one flow
out of twenty, and it is modelled explicitly in `PairingState` anyway.

## Consequences

- `flutter_riverpod` with `riverpod_generator` for the annotated providers.
- Providers are the only place `ref` appears; widgets read them and nothing
  else. This keeps the UI layer replaceable.
- Domain code must never import Riverpod. `DesktopService` has no Flutter
  imports at all, so it can be driven from a test or a headless build.
- Consistency is enforced by review: no `setState` for anything that outlives a
  single widget, and no `InheritedWidget` hand-rolled alongside it.
