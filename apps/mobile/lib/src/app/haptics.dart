import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Centralized haptic feedback router that honors the user's preference.
///
/// On mobile, tactile confirmation is essential when using a glass screen as a
/// touchpad or remote control — without physical buttons, a light click or
/// gesture bump tells the finger that the action registered before the remote
/// screen can reflect it.
///
/// However, some users find persistent haptics distracting, battery-draining,
/// or inaccessible. Every call to [HapticFeedback] in the app routes through
/// this helper so that toggling the haptics preference in Settings completely
/// and reliably silences all vibrations across the touchpad, keyboard, and
/// media screens.
final class AppHaptics {
  const AppHaptics(this._ref);

  final Ref _ref;

  /// Selection click feedback (e.g. discrete mouse clicks, keyboard taps, media buttons).
  Future<void> selectionClick() async {
    if (!_ref.read(hapticsProvider)) return;
    await HapticFeedback.selectionClick();
  }

  /// Medium impact feedback (e.g. 3-finger swipe gesture trigger, long-press drag initiate).
  Future<void> mediumImpact() async {
    if (!_ref.read(hapticsProvider)) return;
    await HapticFeedback.mediumImpact();
  }

  /// Light impact feedback for subtle UI adjustments.
  Future<void> lightImpact() async {
    if (!_ref.read(hapticsProvider)) return;
    await HapticFeedback.lightImpact();
  }

  /// Heavy impact feedback for high-emphasis actions.
  Future<void> heavyImpact() async {
    if (!_ref.read(hapticsProvider)) return;
    await HapticFeedback.heavyImpact();
  }

  /// Static convenience helper taking a [WidgetRef] for selection click.
  static Future<void> selection(WidgetRef ref) =>
      ref.read(appHapticsProvider).selectionClick();

  /// Static convenience helper taking a [WidgetRef] for medium impact.
  static Future<void> medium(WidgetRef ref) =>
      ref.read(appHapticsProvider).mediumImpact();
}

/// Provider exposing [AppHaptics].
final appHapticsProvider = Provider<AppHaptics>((ref) => AppHaptics(ref));
