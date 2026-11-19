# ADR 0006 — Ads and Subscriptions for Mobile Monetization

**Status:** accepted · **Date:** 2026-11-19 · **Milestone:** Monetization

## Context

Remote Link connects phones to computers and phones to other phones across local Wi-Fi. It requires no user accounts, no cloud relays, and no internet access for its core functions. Maintaining iOS and Android client applications in production, however, incurs recurring developer fees, store reviews, and ongoing maintenance.

To make the phone client sustainable while preserving the app's core mission, monetization is introduced exclusively in the mobile app (`apps/mobile`). The desktop app (`apps/desktop`) remains completely unmonetized and unmodified.

## Decision

1. **Monetization Engine:**
   - **Google AdMob** (`google_mobile_ads`) delivers unobtrusive advertisements to free users. Consent is collected through Google's User Messaging Platform (UMP) before initializing the ads SDK, complying with GDPR and regional privacy regulations without raising an Apple App Tracking Transparency (ATT) prompt.
   - **RevenueCat** (`purchases_flutter`) manages in-app purchases and subscriptions across Google Play and Apple App Store. One entitlement (`premium`) is unlocked by either:
     - `remotelink_premium_monthly`: $0.99/month auto-renewing subscription.
     - `remotelink_premium_lifetime`: $4.99 one-time non-consumable purchase.

2. **Local Peer-to-Peer Remains Local and Unaccounted:**
   - The device-to-device connection (WebSocket/TCP, Noise protocol cryptographic handshake, binary frames, file transfer streams, and Bonjour discovery) remains 100% local and untouched.
   - The ONLY internet traffic emitted by the phone app is for Google AdMob (ad requests and UMP consent) and RevenueCat (store receipt validation).
   - If the device is offline, peer-to-peer connections and all free functionality operate normally. If RevenueCat keys or AdMob unit IDs are absent, the app degrades gracefully: billing informs the user that purchases are unavailable, while the app continues running without crashing.

3. **Gated Premium Features:**
   Free users have complete access to the core remote controls (touchpad, soft and hardware keyboard, media controls, file transfer, and manual clipboard push/pull). Premium unlocks an ad-free experience plus three specific extras:
   - **Apple Watch trackpad relay** (`watch_bridge.dart` and settings): Relaying wrist gestures from watchOS through the phone to the desktop.
   - **Android background clipboard service** (`link_service.dart` and settings): Operating an Android accessibility service to read the clipboard while third-party apps are active.
   - **Unlimited clipboard history** (`clipboard_history_controller.dart`): Free users retain the 5 most recent items; premium users enjoy unlimited clipboard history up to the storage cap.

4. **Why These Three Features:**
   - They represent advanced "power-user" convenience rather than the core utility of Remote Link.
   - Apple Watch integration requires watchOS maintenance, wrist-to-phone connectivity, and companion app packaging.
   - Background accessibility clipboard reading on Android is a sensitive power-user capability that requires explicit configuration and background battery management.
   - Clipboard history storage beyond 5 recent items is a productivity convenience, whereas immediate 1-to-1 sync and recent history remain functional for free users.
   - Crucially, basic computer control, touchpad gestures, text input, media playback, and device-to-device file transfer remain fully usable on the free tier.

5. **Ad Placement and Input Surface Safety:**
   - **Anchored Banner:** Placed at the bottom of the main shell, situated safely above the liquid navigation bar.
   - **NEVER on Input Surfaces:** The banner is completely hidden on input tabs: touchpad, keyboard (soft keyboard and hardware keyboard views), and media controls while active/dragging, as well as fullscreen viewer routes. Placing banners on these surfaces would lead to catastrophic misclicks that send erratic mouse movements, clicks, or keystrokes to the controlled computer.
   - **Interstitials:** Shown only after a file transfer completes successfully, subject to an enforced 10-minute frequency cap, never at application cold start, and never while an incoming connection or pairing prompt (`nearby_prompts.dart`) is visible on screen.
   - **Zero Ad Requests for Premium Users:** As soon as the `premium` entitlement is recognized, all ad preloading and ad requests are halted immediately and any cached ads are released.

6. **Architecture and Testability:**
   - Platform channel dependencies are isolated behind pure-Dart abstractions (`BillingGateway`, `AdsGateway`, `InterstitialPolicy`).
   - In test environments, `FakeBillingGateway` and `NoopAdsGateway` are used, guaranteeing zero platform channel invocations and 100% deterministic unit and widget testing.
