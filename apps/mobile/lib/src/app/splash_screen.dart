import 'dart:math' as math;

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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ExcludeSemantics(
                        // The octahedron has six vertices and twelve edges, so
                        // its triangular outline remains recognisable at 144dp
                        // where a more detailed wireframe would turn to noise.
                        child: RepaintBoundary(
                          child: CustomPaint(
                            size: const Size.square(144),
                            painter: _LaunchSolidPainter(
                              progress: _controller,
                              strokeColor: scheme.primary,
                            ),
                          ),
                        ),
                      ),
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
      ],
    );
  }
}

class _LaunchSolidPainter extends CustomPainter {
  _LaunchSolidPainter({required this.progress, required this.strokeColor})
      : super(repaint: progress);

  final Animation<double> progress;
  final Color strokeColor;

  static const List<({double x, double y, double z})> _vertices =
      <({double x, double y, double z})>[
    (x: 1, y: 0, z: 0),
    (x: -1, y: 0, z: 0),
    (x: 0, y: 1, z: 0),
    (x: 0, y: -1, z: 0),
    (x: 0, y: 0, z: 1),
    (x: 0, y: 0, z: -1),
  ];

  static const List<({int a, int b})> _edges = <({int a, int b})>[
    (a: 0, b: 2),
    (a: 0, b: 3),
    (a: 0, b: 4),
    (a: 0, b: 5),
    (a: 1, b: 2),
    (a: 1, b: 3),
    (a: 1, b: 4),
    (a: 1, b: 5),
    (a: 2, b: 4),
    (a: 2, b: 5),
    (a: 3, b: 4),
    (a: 3, b: 5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final angle = progress.value * math.pi * 2;
    final sinY = math.sin(angle);
    final cosY = math.cos(angle);
    final sinX = math.sin(angle * 0.7);
    final cosX = math.cos(angle * 0.7);
    final scale = size.shortestSide * 0.31;
    final center = size.center(Offset.zero);
    final projected = <Offset>[];

    for (final vertex in _vertices) {
      final x = vertex.x;
      final y = vertex.y;
      final z = vertex.z;
      final rotatedX = x * cosY - z * sinY;
      final rotatedZ = x * sinY + z * cosY;
      final rotatedY = y * cosX - rotatedZ * sinX;
      final depth = rotatedZ * cosX + y * sinX;
      final perspective = 1 / (2.9 - depth * 0.35);
      projected.add(
        center +
            Offset(
              rotatedX * scale * perspective,
              rotatedY * scale * perspective,
            ),
      );
    }

    final paint = Paint()
      ..color = strokeColor
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final edge in _edges) {
      canvas.drawLine(projected[edge.a], projected[edge.b], paint);
    }
  }

  @override
  bool shouldRepaint(_LaunchSolidPainter oldDelegate) =>
      oldDelegate.strokeColor != strokeColor;
}
