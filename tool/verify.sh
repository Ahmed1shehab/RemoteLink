#!/usr/bin/env bash
#
# Format, analyse, and test the whole workspace without melos.
#
# Melos is convenient but it is one more thing that has to resolve before you
# can find out whether your code compiles. This script needs nothing but the
# Flutter SDK, which makes it the right thing for CI and for the first run on a
# fresh checkout.

set -euo pipefail

cd "$(dirname "$0")/.."

PURE_DART_PACKAGES=(
  packages/rl_core
  packages/rl_protocol
  packages/rl_crypto
  packages/rl_transport
  packages/rl_native
  # The harness is a workspace member with its own suite, and leaving it out of
  # this list once cost real time: a method added to `InputBackend` broke the
  # fake in its tests, and nothing noticed until an unrelated change happened to
  # run it by hand. Analysis covered it, tests did not.
  tool/latency_harness
)

FLUTTER_PACKAGES=(
  apps/desktop
  apps/mobile
)

echo "==> Resolving the workspace"
# One resolution for every package: pub workspaces share a single lockfile, so
# this is the only `pub get` the repository needs.
flutter pub get

echo
echo "==> Formatting"
dart format --set-exit-if-changed .

echo
echo "==> Analysing"
# --fatal-warnings but not --fatal-infos: warnings are defects, infos are style.
dart analyze --fatal-warnings .

echo
echo "==> Testing pure-Dart packages"
for package in "${PURE_DART_PACKAGES[@]}"; do
  if [ -d "$package/test" ]; then
    echo "--- $package"
    (cd "$package" && dart test --reporter expanded)
  fi
done

echo
echo "==> Testing Flutter packages"
for package in "${FLUTTER_PACKAGES[@]}"; do
  if [ -d "$package/test" ]; then
    echo "--- $package"
    (cd "$package" && flutter test)
  fi
done

echo
echo "All checks passed."
