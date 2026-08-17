import 'package:flutter/material.dart';

/// Reduced-motion support, in one place so it cannot be half-applied.
///
/// The platform switch is "Reduce motion" on macOS and "Show animations in
/// Windows" on Windows; Flutter surfaces both as
/// [MediaQueryData.disableAnimations]. Nothing in the framework applies it for
/// you, so every animation has to ask.
///
/// A copy of the mobile app's file of the same name. `packages/` may not import
/// Flutter (CONTRIBUTING §1), so there is nowhere below `apps/` for it to live.
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
/// Read off a default [PageTransitionsTheme] rather than listed out here, so
/// that a framework change to a platform's default transition is inherited
/// rather than pinned.
PageTransitionsTheme reducedMotionAwarePageTransitions() {
  const defaults = PageTransitionsTheme();
  return PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      for (final entry in defaults.builders.entries)
        entry.key: ReducedMotionPageTransitionsBuilder(entry.value),
    },
  );
}
