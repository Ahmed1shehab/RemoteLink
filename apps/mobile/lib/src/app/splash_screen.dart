import 'package:flutter/material.dart';

import '../features/devices/device_list_screen.dart';
import 'brand.dart';
import 'motion.dart';

/// The brief interval between Flutter drawing and the first useful screen.
///
/// This is capped rather than held until discovery settles: a network browse can
/// take seconds, and turning that uncertainty into a branded wait would leave
/// the user staring at decoration when the device list could already help.
class LaunchScreen extends StatefulWidget {
  const LaunchScreen({super.key});

  @override
  State<LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<LaunchScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _maximumDuration = Duration(milliseconds: 1100);
  static const double _fadeStart = 0.76;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _maximumDuration,
  )..addStatusListener(_handleAnimationStatus);
  bool _showLaunch = true;
  bool _motionStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionStarted) return;
    _motionStarted = true;
    final duration = context.motion(_maximumDuration);
    _controller.duration = duration;
    if (context.prefersReducedMotion) {
      // A zero-duration fade still creates a composited transition, which is
      // motion to people who explicitly asked for none. Building the list
      // directly also gives assistive technology its useful first target.
      _showLaunch = false;
      return;
    }
    _controller.forward();
  }

  void _handleAnimationStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    // The splash has become fully transparent, so retaining it would leave a
    // semantic duplicate above the screen that the user has actually reached.
    setState(() => _showLaunch = false);
  }

  @override
  void dispose() {
    _controller
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showLaunch) return const DeviceListScreen();

    final scheme = Theme.of(context).colorScheme;
    final fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(_fadeStart, 1, curve: Curves.easeOutCubic),
    );
    // The mark and the name arrive together, over the first third of the cap,
    // so the splash reads as the app introducing itself rather than as a frame
    // that happened to be caught mid-load.
    final entrance = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.34, curve: Curves.easeOutCubic),
    );
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DeviceListScreen(),
        BlockSemantics(
          child: FadeTransition(
            opacity: ReverseAnimation(fade),
            child: Semantics(
              key: const ValueKey<String>('launch-screen-overlay'),
              container: true,
              label: kProductName,
              child: ColoredBox(
                color: scheme.surface,
                child: Center(
                  child: FadeTransition(
                    opacity: entrance,
                    child: ScaleTransition(
                      // A small rise from 96%, not a pop: the icon is the same
                      // artwork the launcher just showed, and anything larger
                      // would read as a second, different animation on top of
                      // the system's own icon-to-app transition.
                      scale:
                          Tween<double>(begin: 0.96, end: 1).animate(entrance),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const ExcludeSemantics(child: BrandMark(size: 120)),
                          const SizedBox(height: 28),
                          ExcludeSemantics(
                            child: Text(
                              kProductName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(color: scheme.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
