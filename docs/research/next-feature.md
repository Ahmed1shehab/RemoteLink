# Research: the one next feature for Remote Link

**Date:** 2026-11-19 · **Question:** which single new feature would add the most
value? · **Out of scope:** screen sharing (parked behind `kScreenSharingShipped`)
and ads/subscriptions (in progress on `feat/ads-subscriptions`).

**Answer:** **Quick Actions**, which is the custom command registry (RL-207). The
user saves commands on the computer and runs them from the phone with one tap.
The wire code already exists, the desktop half is pure Dart, and it works the
same on iOS and Android. It also gives the two strongest competitors' headline
"run my thing" feature to a product that has no answer to it today.

Every external claim cites its source. Claims about this repo cite `file:line`.

---

## 1. What Remote Link has today (checked in the code)

- **Shipped:** touchpad, keyboard, media, clipboard text plus history, file
  transfer both ways, phone-to-phone, watch trackpad, QR pairing
  (`README.md`, Done table). Windows media control has since landed too
  (commit `39c7f99`), and desktop clipboard images exist
  (`macos_clipboard.dart:334`, `win32_clipboard.dart:298`). README and BACKLOG
  are stale on both points.
- **Reserved on the wire but decoded as opaque:** `slideCommand`,
  `laserPointer`, `presentationBlank`, `gamepadState` and `motionState`
  (`packages/rl_protocol/lib/src/codec.dart:214-219`).
- **Decoded and routed, but refused:** `runCommand` (`0x0804`). The dispatcher
  checks the tier (`messages/system.dart:472`, `canRunCommands`). Then
  `_onRunCommand` logs "no command registry is configured" and does nothing
  (`apps/desktop/lib/src/domain/desktop_service.dart:2775-2783`).
- **Desktop supports it, the phone never sends it:** `powerCommand`,
  `launchApplication` and `openUrl` are carried out on the desktop
  (`desktop_service.dart:2647-2770`). A search of `apps/mobile/lib` finds no
  code that sends any of them.
- **Native code policy:** the dependency notes say a Swift/Kotlin shim "this
  repository deliberately does not ship (ADR 0003)" (`apps/mobile/pubspec.yaml`,
  `gal` entry). In practice the repo already has four Kotlin files
  (`apps/mobile/android/app/src/main/kotlin/...`) and `WatchBridge.swift`. So
  native code is allowed, but only when there is no other way.

## 2. Competitor headline features (primary sources)

| Product | Headline features | Source |
|---|---|---|
| KDE Connect | Files and links shared · phone notifications everywhere · "Fully customizable commands" · media remote · presentation remote and virtual trackpad · ring your phone and see its battery | [kdeconnect.kde.org](https://kdeconnect.kde.org/) |
| KDE Connect (plugins) | Run Commands ("Execute console commands directly", which can also show as Android 11+ Device Controls) · slideshow remote with laser pointer · notification sync with reply · SMS · Ring My Phone · clipboard text only, no images | [userbase.kde.org/KDEConnect](https://userbase.kde.org/KDEConnect) |
| KDE Connect iOS | Clipboard, share files/URLs, touchpad/keyboard, presentation laser pointer, remote commands. The App Store listing names "remote commands" | [App Store](https://apps.apple.com/us/app/kde-connect/id1580245991) |
| Unified Remote | Mouse, screen mirroring, power with WOL, keyboard, file browsing, media. "100+ programs" | [unifiedremote.com](https://www.unifiedremote.com/) |
| Unified Remote (tiers) | 18 remotes free, 40+ more in Full. Custom remotes, widgets, voice, NFC tags and Siri are **Full only** | [unifiedremote.com/features](https://www.unifiedremote.com/features) |
| Unified Remote iOS | "custom remotes you can build yourself" · Siri and Shortcuts to "send actions" · power and WOL | [App Store](https://apps.apple.com/us/app/unified-remote/id825534179) |
| Microsoft Phone Link | Android over Wi-Fi: notifications, messages, calls, photos, apps, copy-paste, file transfer. iPhone over **Bluetooth**: notifications, messages, calls only | [Phone Link requirements](https://support.microsoft.com/en-us/windows/apps/phonelink/phone-link-requirements-and-setup) |
| LocalSend | Cross-platform, end-to-end encrypted, no internet, full Wi-Fi speed | [localsend.org](https://localsend.org/) |
| Pushbullet | Notification mirroring (Android is "currently the only source"), universal copy-paste, SMS, file and link pushes | [docs.pushbullet.com](https://docs.pushbullet.com/) |
| AirDroid Personal | File transfer, remote control of Android, screen mirroring, remote camera, SMS and notifications, calls, Find Phone | [airdroid.com/personal](https://www.airdroid.com/personal/) |

## 3. What users ask for (primary sources)

**KDE Connect: open wishlist bugs ranked by CC count** (people subscribed).
Votes are not exposed. Pulled from the
[bugs.kde.org REST API](https://bugs.kde.org/rest/bug?product=kdeconnect&severity=wishlist&resolution=---&include_fields=id,summary,cc)
on 2026-11-19:

| CCs | Bug | Request |
|---|---|---|
| 31 | [391624](https://bugs.kde.org/show_bug.cgi?id=391624) | Screen sharing (excluded here) |
| 19 | [410149](https://bugs.kde.org/show_bug.cgi?id=410149) | Make and receive calls from the PC |
| 18 | [374017](https://bugs.kde.org/show_bug.cgi?id=374017) | Stream audio between devices |
| 15 | [392164](https://bugs.kde.org/show_bug.cgi?id=392164) | Button for sharing clipboard content |
| 13 | [451258](https://bugs.kde.org/show_bug.cgi?id=451258) | Image clipboard copy/paste |
| 12 | [393664](https://bugs.kde.org/show_bug.cgi?id=393664) | Wake-on-LAN |
| 10 | [447508](https://bugs.kde.org/show_bug.cgi?id=447508) | Send folders |
| 5 | [472069](https://bugs.kde.org/show_bug.cgi?id=472069) | iOS integration with Apple Shortcuts |
| — | [422768](https://bugs.kde.org/show_bug.cgi?id=422768) | Allow reordering of run commands |

**LocalSend: issues ranked by 👍.** From the GitHub search API
(`repo:localsend/localsend is:issue sort:reactions-+1`):
[#11 headless CLI](https://github.com/localsend/localsend/issues/11) (96),
[#189 Wi-Fi Direct with QR](https://github.com/localsend/localsend/issues/189) (63),
[#850 Bluetooth discovery](https://github.com/localsend/localsend/issues/850) (48),
[#2523 Wi-Fi Aware](https://github.com/localsend/localsend/issues/2523) (44),
[#2153 run in background on Android](https://github.com/localsend/localsend/issues/2153) (26).
Clipboard sync gets far less:
[#163](https://github.com/localsend/localsend/issues/163) (11). LocalSend users
mostly ask for **other transports and automation**, not new remote features.

**Unified Remote.** Its help centre says it builds "the most requested features"
and points to a community voting board
([help article](https://help.unifiedremote.com/article/19-will-you-add-a-remote-for)).
That board (`community.unifiedremote.com`) no longer resolves in DNS, so no
vote counts could be collected. The iOS listing has 3.8★ from 297 ratings, but
shows only three reviews, so it says little about themes
([App Store](https://apps.apple.com/us/app/unified-remote/id825534179)).

**KDE Connect iOS reviews** (4.2★, 281 ratings): people praise transfers. The
complaints are that features only work with the app open, and transfers stalling
after about 20 files
([App Store](https://apps.apple.com/us/app/kde-connect/id1580245991)).

**Caveat:** CC counts and 👍 measure demand in each product's own user base,
not in Remote Link's. App-store review samples are tiny. Treat this as a
direction, not a measurement.

## 4. Gap list (competitors have it, Remote Link does not; checked in the code)

| Gap | Who has it | How absence was checked in this repo |
|---|---|---|
| Run user-defined commands / quick actions | KDE Connect, Unified Remote (paid) | `_onRunCommand` refuses (`desktop_service.dart:2775`). No registry file exists |
| Power / lock / launch / open-URL buttons on the phone | Unified Remote | Desktop handles them. Phone never sends them (search of `apps/mobile/lib`) |
| Phone notifications on the computer | KDE Connect, Phone Link, Pushbullet, AirDroid | No notification listener among the four Kotlin files. RL-540 covers the *opposite* direction, desktop to phone |
| Presentation remote with laser pointer | KDE Connect, Unified Remote | `0x0Axx` decodes as opaque (`codec.dart:214-216`) |
| Image clipboard on the phone | KDE wishlist (451258), Pushbullet is text only too | The phone uses only text `Clipboard.setData` (`clipboard_controller.dart:308`) |
| Gamepad | — (only in the roadmap) | `0x0Bxx` decodes as opaque (`codec.dart:217-218`) |
| SMS and calls | Phone Link, KDE, AirDroid, Pushbullet | None |
| Ring / find my phone | KDE, AirDroid | No matches for find/ring phone |
| Send folders | KDE wishlist (447508) | Desktop rejects dropped folders (`home_screen.dart:1030-1048`) |
| Wake-on-LAN | Unified Remote | Removed on purpose because it "could not report whether it had done anything" (`ROADMAP.md`, M2 item 5) |

## 5. Top five candidates, scored

Scores are 1–5, where 5 is best. For cost, 5 means *cheapest*. For platform
limits, 5 means *no limits*.

| Candidate | Demand | Fit (wire/backlog) | Cost here | Platform limits | Total |
|---|---|---|---|---|---|
| **A. Quick Actions (RL-207)** | 4 | 5 | 4 | 5 | **18** |
| B. Phone→PC notification mirroring | 5 | 2 | 1 | 1 | 9 |
| C. Presentation mode (RL-500) | 3 | 5 | 2 | 4 | 14 |
| D. Image clipboard on the phone | 3 | 4 | 2 | 3 | 12 |
| E. Gamepad (RL-510) | 2 | 4 | 1 | 1 | 8 |

**A. Quick Actions.** *Demand:* KDE Connect makes "Fully customizable commands"
one of its six headlines ([site](https://kdeconnect.kde.org/)) and lists them in
its iOS listing ([App Store](https://apps.apple.com/us/app/kde-connect/id1580245991)).
Unified Remote sells custom remotes and Siri "send actions" as Full-version
features ([features](https://www.unifiedremote.com/features),
[App Store](https://apps.apple.com/us/app/unified-remote/id825534179)). KDE users
ask to reorder commands and to trigger them from Shortcuts (422768, 472069).
*Fit:* `runCommand 0x0804` already has a codec with caps of 256 B id, 32 params
and 4 KiB per param (`messages/system.dart:184-200`). Tier gating already
exists, and the elevation flow has shipped (commit `84a4547`). RL-207 has a
full spec with acceptance tests. One message is missing: the desktop has no way
to send the phone its command list. *Cost:* M, pure Dart on both sides, with
`Process.run` and no shell. No new plugin and no native code. *Platform:* the
phone only sends a message while in the foreground, which is how the app
already works on iOS.

**B. Notification mirroring.** It has the strongest demand signal: it is a
headline for four of the six competitors (table in §2). The platform limits
sink it. iOS apps "can't access notifications of other apps"
([KDE Connect iOS README](https://invent.kde.org/network/kdeconnect-ios/-/raw/master/README.md)).
Phone Link gets iPhone notifications only through Bluetooth pairing
([Microsoft](https://support.microsoft.com/en-us/windows/apps/phonelink/phone-link-requirements-and-setup)).
On Android it needs a `NotificationListenerService` with
`BIND_NOTIFICATION_LISTENER_SERVICE`
([Android docs](https://developer.android.com/reference/android/service/notification/NotificationListenerService)),
which means Kotlin. It also needs a native toast on Windows and macOS, a new
`0x0Dxx` subsystem (`0x0Cxx` is now phone control), and a `SECURITY.md`
privacy section first (RL-540 sets that rule). Delivery depends on the
background link, which exists only on Android (`README.md`). The SMS and calls
add-ons are further fenced off by Play policy: those permissions are for
default SMS/Phone handlers apart from reviewed exceptions
([Play policy](https://support.google.com/googleplay/android-developer/answer/10208820)).

**C. Presentation mode.** KDE Connect advertises the slideshow remote and laser
pointer on both its site and its iOS listing (sources above). All three wire
codes are reserved, and both apps already advertise `Capabilities.presentation`
(`desktop_service.dart:67`, `apps/mobile/lib/src/app/providers.dart:46`). But
next/previous slide is already possible with the keyboard tab's arrow keys, so
the slice that is cheap adds little. The part that is new, a click-through
always-on-top laser overlay and blanking a single display, needs a second
transparent native window. Flutter desktop has no simple way to do that.
Good second pick.

**D. Image clipboard on the phone.** Demand is real (KDE 451258, 13 CCs) and
the desktop half exists. Flutter's `Clipboard` handles plain text only
([api.flutter.dev](https://api.flutter.dev/flutter/services/Clipboard-class.html)),
so this needs a new third-party plugin or native code on two platforms. It also
needs the size and metered-network rules from RL-410.

**E. Gamepad.** The Windows virtual-pad driver the backlog relies on, ViGEmBus,
is "RETIRED" and was archived in November 2023
([GitHub](https://github.com/nefarius/ViGEmBus)). On macOS there is no virtual
HID without an entitlement (RL-510). The evidence for demand is weak.

## 6. Recommendation: Quick Actions (RL-207), first shippable slice

**Why this one.** It is the only candidate that scores well on all four axes.
It turns a refused message into a feature, and it adds no native code and no
new privacy surface beyond what RL-207 already bounds. It also fits the
in-progress monetisation work better than anything else: Unified Remote already
sells this exact feature as paid
([features](https://www.unifiedremote.com/features)). That last point is an
observation, not part of the score.

**What the user sees**
- **Desktop › Settings › Quick actions.** A list with *Add / Edit / Test run /
  Remove* and an enable switch. Each command has a name, an executable chosen
  with the file picker, a fixed argument list, a working directory, and a
  minimum tier (default `extended`). New commands start **disabled**, as RL-207
  item 6 requires.
- **Phone, new "Actions" tab.** A grid of tiles with each command's name. A tap
  sends `runCommand` and shows a success or failure toast. If the device's tier
  is too low, a tile offers the existing elevation request instead of failing
  silently.

**Messages**
- `runCommand 0x0804` (exists, phone → desktop): `commandId`, with
  `parameters` always empty in this slice.
- **New:** `commandCatalog 0x0806` (desktop → phone): a list of `{id, name,
  minTier}`. It is sent after `PermissionGrant` and whenever the registry
  changes. Per `PROTOCOL.md` §5 a new type does not bump the version, and old
  phones log and drop it. It carries no command text, which keeps the
  `SECURITY.md` rule that "command text never crosses the wire".
- **New:** `runCommandResult`, so the toast is honest instead of guessing. It
  could be `0x0807` with `{id, exitCode | refusedReason}`. Or the slice could
  reuse the structured `error 0x0007` for refusals and send nothing on success.
  This is a design choice to settle in review.
- **New capability bit** `commands`, added to `kMobileCapabilities` (the
  providers.dart comment warns that a missing bit hides the tab silently) and
  advertised by the desktop only when at least one command is enabled.

**Files likely to change**
- `packages/rl_protocol/lib/src/message_type.dart`, `messages/system.dart`,
  `codec.dart`, `messages/control.dart` (capability bit); `docs/PROTOCOL.md` §4.
- `apps/desktop/lib/src/domain/command_registry.dart` (new). It stores JSON in
  app support with an integrity MAC (RL-207 item 1, the same pattern as the
  mobile trust-store MAC in `apps/mobile/lib/src/app/providers.dart:172`).
- `apps/desktop/lib/src/domain/desktop_service.dart`: `_onRunCommand` resolves
  the id and runs `Process.run(exe, args, runInShell: false)`. It also builds
  the catalog and sets the capability.
- `apps/desktop/lib/src/ui/command_editor.dart` (new) and `settings_screen.dart`.
- `apps/mobile/lib/src/features/actions/` (new): `actions_screen.dart` and a
  catalog provider. Add `actions` to `ControlTab`
  (`features/control/control_screen.dart:45`). Add l10n strings in both apps
  (RL-702 shipped, including RTL).

**Tests that prove it**
- `rl_protocol`: round-trip `commandCatalog`. Check that an oversize list or
  name is rejected, and that an old decoder treats `0x0806` as unknown.
- `apps/desktop/test/command_registry_test.dart`: persist and reload. A file
  whose MAC fails to verify gets **no** commands. A new entry starts disabled.
- `apps/desktop/test/desktop_service_test.dart`: a registered id runs. An
  unknown id is refused and logged and runs nothing. A `standard` device is
  refused an `extended` command. Use a fake process runner and assert it
  received an argv list, never a shell string.
- `apps/desktop/test/dispatcher_matrix_test.dart`: add `runCommand` and
  `commandCatalog` to the per-tier matrix.
- `apps/mobile/test/control_tabs_test.dart` and
  `advertised_capabilities_test.dart`: the Actions tab appears only with the
  `commands` bit, and the bit is in `kMobileCapabilities`.
- A widget test checking that a tap sends exactly one `RunCommand(id)`.

**What this slice deliberately leaves out**
- **Placeholders and parameters.** The codec supports them, but they bring
  input validation and UI design (RL-207 item 4). Do them in slice 2.
- **Power, launch and open-URL tiles.** The desktop handles these already, so
  this is cheap. Power needs the `admin` tier, though, so it needs its own UX.
  Slice 2.
- **iOS Shortcuts/Siri, Android Device Controls, home-screen widgets.** These
  are each competitor's next layer, and each needs native code (Swift or
  Kotlin).
- **Defining or editing commands from the phone.** This is forbidden by
  RL-207's risk note: "do not accept a command definition over the network".
- **Command output streamed back to the phone, scheduling, chaining.**
- **Linux desktop** (RL-600).

## 7. Limits of this research

- None of the demand data comes from Remote Link users. Its own diagnostics and
  analytics, if they exist, would outrank everything in §3.
- The Unified Remote vote board was unreachable. The Google Play listings
  (Pushbullet and others) render client-side and returned no text, so Android
  review themes are missing.
- The scores are a judgement made from the sources above, not a formula.
  Notification mirroring would win if Remote Link were an Android-only product.
