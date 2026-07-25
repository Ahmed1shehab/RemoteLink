#!/usr/bin/env bash
#
# Generates the platform runner directories and applies the permissions
# RemoteLink needs to see the local network.
#
# The runners are `flutter create` output and are not committed, so this runs
# once per fresh checkout. Every edit below is one the app cannot work without:
# without the entitlements the desktop cannot open a listening socket, and
# without the usage descriptions the phone's discovery finds nothing and the OS
# gives no reason why.
#
# Safe to re-run — `flutter create` is additive and PlistBuddy edits are
# idempotent.

set -euo pipefail
cd "$(dirname "$0")/.."

PLIST=/usr/libexec/PlistBuddy

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

# Sets a plist key, adding it if absent and overwriting if present.
set_plist() {
  local file="$1" key="$2" type="$3" value="$4"
  "$PLIST" -c "Add :$key $type $value" "$file" 2>/dev/null \
    || "$PLIST" -c "Set :$key $value" "$file"
}

say "Generating platform runners"
(cd apps/desktop && flutter create --platforms=macos,windows --project-name remotelink_desktop .)
# macOS is included for the phone app on purpose. Running the client as a
# desktop window is the fastest way to exercise the whole stack — no simulator,
# no permission prompts, no entitlement review — and it is the fallback in
# docs/RUNNING.md when the iOS Simulator misbehaves.
(cd apps/mobile && flutter create --platforms=ios,android,macos --project-name remotelink_mobile .)

# ── macOS ────────────────────────────────────────────────────────────────────
#
# Flutter's macOS template ships a sandboxed app with no network access at all.
# The server entitlement is the one people forget: `network.client` alone lets
# the app make outbound connections but not accept them, so the desktop starts
# cleanly and then silently never sees a phone.
say "macOS entitlements"
for app in desktop mobile; do
  for config in DebugProfile Release; do
    file="apps/$app/macos/Runner/${config}.entitlements"
    [ -f "$file" ] || continue
    set_plist "$file" "com.apple.security.network.server" bool true
    set_plist "$file" "com.apple.security.network.client" bool true
    echo "  patched $file"
  done
done

# Note: no `keychain-access-groups` entitlement is added for the client's macOS
# build, deliberately. Keychain access groups resolve `$(AppIdentifierPrefix)`
# from a provisioning profile, so adding one forces development signing and
# breaks `flutter run` with ad-hoc signing. The client instead uses the
# platform keystore only on iOS and Android — where it ships, and where the
# profile provides the prefix — and a permission-restricted file on desktop.
# See `identityStoreProvider` in apps/mobile/lib/src/app/providers.dart.

MAC_PLIST=apps/desktop/macos/Runner/Info.plist
if [ -f "$MAC_PLIST" ]; then
  set_plist "$MAC_PLIST" "NSLocalNetworkUsageDescription" string \
    "RemoteLink lets your phone find and control this computer over your local network."
  # LSUIElement hides the Dock icon: this is a menu-bar service, and a bouncing
  # Dock icon for something that runs all day is wrong.
  set_plist "$MAC_PLIST" "LSUIElement" bool true
  echo "  patched $MAC_PLIST"
fi

# ── iOS ──────────────────────────────────────────────────────────────────────
#
# iOS 14+ blocks local-network traffic until the user accepts a prompt, and the
# prompt only appears if this key exists. Without it, discovery returns nothing
# and there is no error to diagnose.
say "iOS local network permission"
IOS_PLIST=apps/mobile/ios/Runner/Info.plist
if [ -f "$IOS_PLIST" ]; then
  set_plist "$IOS_PLIST" "NSLocalNetworkUsageDescription" string \
    "RemoteLink uses your local network to find and control your computer."
  "$PLIST" -c "Delete :NSBonjourServices" "$IOS_PLIST" 2>/dev/null || true
  "$PLIST" -c "Add :NSBonjourServices array" "$IOS_PLIST"
  "$PLIST" -c "Add :NSBonjourServices:0 string _remotelink._tcp" "$IOS_PLIST"
  echo "  patched $IOS_PLIST"
fi

# ── Android ──────────────────────────────────────────────────────────────────
#
# CHANGE_WIFI_MULTICAST_STATE is the one that matters. Android drops multicast
# packets before they reach the app unless a multicast lock is held, and the
# permission is what allows taking it. Without it discovery is silently dead.
say "Android permissions"
MANIFEST=apps/mobile/android/app/src/main/AndroidManifest.xml
if [ -f "$MANIFEST" ] && ! grep -q "CHANGE_WIFI_MULTICAST_STATE" "$MANIFEST"; then
  python3 - "$MANIFEST" <<'PY'
import sys
path = sys.argv[1]
source = open(path).read()
permissions = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
'''
marker = '<application'
index = source.index(marker)
open(path, 'w').write(source[:index] + permissions.strip() + '\n\n    ' + source[index:])
print(f"  patched {path}")
PY
else
  echo "  already patched (or manifest not generated)"
fi

say "Done"
cat <<'EOF'

Next:

  flutter pub get
  ./tool/verify.sh                          # tests first — see README

  cd apps/desktop && flutter run -d macos   # grant Accessibility when asked
  cd apps/mobile  && flutter run -d macos   # easiest first client (see README)

EOF
