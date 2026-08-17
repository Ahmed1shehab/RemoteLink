import 'package:flutter/material.dart';

/// Reduced-motion support, in one place so it cannot be half-applied.
///
/// The platform switch is "Reduce Motion" on iOS and "Remove animations" on
/// Android; Flutter surfaces both as [MediaQueryData.disableAnimations].
/// Nothing in the framework applies it for you — an `AnimatedContainer` keeps
/// animating and a route keeps sliding — so every animation has to ask.
///
/// Why it matters here more than in most apps: RemoteLink is used while looking
/// at *the computer*, with the phone moving in the hand. For someone with a
/// vestibular disorder, motion in the periphery is the part that triggers
/// symptoms, and it is exactly the motion they are not looking at.
///
/// The desktop app carries its own copy of this file: `packages/` may not
/// import Flutter (CONTRIBUTING §1), so there is nowhere below `apps/` for it
/// to live.
extension ReducedMotion on BuildContext {
  /// True when the user has asked the system to remove animation.
  bool get prefersReducedMotion => MediaQuery.disableAnimationsOf(this);

  /// [duration], or zero when the user has asked for no animation.
  ///
  /// Zero rather than "shorter": a fast animation is still animation, and the
  /// setting is a request to remove it, not to hurry it along.
  Duration motion(Duration duration) =>
      prefersReducedMotion ? Duration.zero : duration;
}

/// Wraps another builder and skips it entirely under reduced motion.
///
/// Route transitions are the largest movement in the app and the one the
/// framework will not drop on its own, so they are wrapped rather than replaced
/// — the ordinary platform transition is still what everyone else sees.
class ReducedMotionPageTransitionsBuilder extends PageTransitionsBuilder {
  const ReducedMotionPageTransitionsBuilder(this.delegate);

  final PageTransitionsBuilder delegate;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return delegate.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// Flutter's own per-platform defaults, each wrapped to honour the setting.
///
/// Read off a default [PageTransitionsTheme] rather than listed out here, on
/// purpose: the framework changes which builder a platform gets between
/// releases — Android has moved to a predictive-back transition since this app
/// was started — and a hard-coded list would quietly pin every platform to
/// whatever was current on the day it was written.
PageTransitionsTheme reducedMotionAwarePageTransitions() {
  const defaults = PageTransitionsTheme();
  return PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      for (final entry in defaults.builders.entries)
        entry.key: ReducedMotionPageTransitionsBuilder(entry.value),
    },
  );
}
