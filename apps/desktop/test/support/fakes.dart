import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remotelink_desktop/src/app/providers.dart';
import 'package:remotelink_desktop/src/domain/desktop_service.dart';

/// Safe provider state for rendering the desktop home screen in widget tests.
///
/// These overrides deliberately stop at the UI-facing providers. In
/// particular, they never construct [DesktopService], whose constructor loads
/// native backends and whose startup opens real network services.
final List<Override> desktopHomeOverrides = <Override>[
  desktopStatusProvider.overrideWith(
    (ref) async => const DesktopStatus(
      isRunning: false,
      deviceName: 'Test computer',
      boundPort: 41234,
      localAddresses: <String>[],
      deviceId: 'test-device-id',
    ),
  ),
  connectedDevicesProvider.overrideWith(
    (ref) => Stream<List<ConnectedDevice>>.value(const <ConnectedDevice>[]),
  ),
  inputAvailabilityProvider.overrideWith(
    (ref) => Stream<({bool available, String? reason})>.value(
      (available: true, reason: null),
    ),
  ),
  pairingRequestProvider.overrideWith(
    (ref) => const Stream<PendingPairing>.empty(),
  ),
];
