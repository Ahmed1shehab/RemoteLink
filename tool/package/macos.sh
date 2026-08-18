#!/usr/bin/env bash
#
# Builds a signed, notarised, stapled .dmg of the desktop companion.
#
#   tool/package/macos.sh
#
# Configuration comes from the environment, because the alternative is a
# checked-in file holding a team identifier and an Apple ID:
#
#   RL_SIGN_IDENTITY   "Developer ID Application: Name (TEAMID)"
#                      List candidates with:
#                        security find-identity -v -p codesigning
#   RL_NOTARY_PROFILE  A keychain profile created once with:
#                        xcrun notarytool store-credentials <name> \
#                          --apple-id <you@example.com> \
#                          --team-id <TEAMID> \
#                          --password <app-specific-password>
#
# Both are optional. Without them this produces an unsigned build and says
# plainly what the user will see when they open it — which is more useful than
# refusing to run, and is what a contributor without a certificate needs.
#
# ## Why signing is not a formality here
#
# macOS binds the Accessibility and Screen Recording grants to the code
# signature. Ship an unsigned build and every user re-grants both on every
# update; change the signing identity and they re-grant once. Those two
# permissions are the product — without them the phone can see a computer it
# cannot touch — so the signature is a feature, not paperwork.

set -euo pipefail

cd "$(dirname "$0")/../.."
ROOT="$PWD"

APP_DIR="apps/desktop"
BUILD_DIR="$APP_DIR/build/macos/Build/Products/Release"
OUT_DIR="build/release"

VERSION="$(grep '^version:' "$APP_DIR/pubspec.yaml" | head -1 | cut -d' ' -f2)"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[33m!!  %s\033[0m\n' "$1"; }

say "Building Remote Link $VERSION for macOS"
(cd "$APP_DIR" && flutter build macos --release)

# Globbed rather than named. The bundle is called after PRODUCT_NAME, which is
# the product's display name and has changed once already; a hard-coded path
# here would fail the next time somebody renames the app and would look like a
# build failure rather than a stale script.
APP="$(find "$BUILD_DIR" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP" ]; then
  echo "no .app in $BUILD_DIR — did the build actually succeed?" >&2
  exit 1
fi
APP_NAME="$(basename "$APP" .app)"
say "Built $APP_NAME.app"

IDENTITY="${RL_SIGN_IDENTITY:-}"
ENTITLEMENTS="$ROOT/$APP_DIR/macos/Runner/Release.entitlements"

if [ -n "$IDENTITY" ]; then
  say "Signing with $IDENTITY"

  # Inner code first, then the bundle. `--deep` would do this in one call and is
  # documented by Apple as unsuitable for distribution: it applies the same
  # entitlements to every nested binary, and a framework carrying the app's
  # entitlements is a notarisation rejection.
  #
  # `--options runtime` is the hardened runtime, which notarisation requires.
  # `--timestamp` fetches a trusted timestamp, without which the signature stops
  # validating the day the certificate expires rather than continuing to vouch
  # for a build made while it was valid.
  find "$APP/Contents/Frameworks" \
    \( -name '*.dylib' -o -name '*.framework' \) -maxdepth 1 -print0 2>/dev/null |
    while IFS= read -r -d '' item; do
      codesign --force --options runtime --timestamp --sign "$IDENTITY" "$item"
    done

  codesign --force --options runtime --timestamp \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP"

  say "Verifying the signature"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  warn "RL_SIGN_IDENTITY is not set — building unsigned."
  warn "Gatekeeper will refuse to open this build by double-click, and the"
  warn "Accessibility grant will reset every time it is rebuilt."
fi

say "Building the disk image"
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/$APP_NAME $VERSION.dmg"
rm -f "$DMG"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
# The symlink is the whole install instruction: the window shows the app and the
# Applications folder, and the gesture between them is obvious without a word of
# documentation.
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

PROFILE="${RL_NOTARY_PROFILE:-}"
if [ -n "$IDENTITY" ] && [ -n "$PROFILE" ]; then
  say "Notarising (this waits on Apple, usually a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

  # Stapling attaches the notarisation ticket to the file, so the first launch
  # works on a machine with no internet. Without it Gatekeeper has to ask Apple,
  # and an offline user sees the warning the notarisation was meant to remove.
  say "Stapling the ticket"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"

  say "Checking it the way Gatekeeper will"
  spctl --assess --type open --context context:primary-signature -vv "$DMG"
elif [ -n "$IDENTITY" ]; then
  warn "RL_NOTARY_PROFILE is not set — signed but not notarised."
  warn "Gatekeeper still warns on a signed build that Apple has not seen."
fi

say "Done: $DMG"
