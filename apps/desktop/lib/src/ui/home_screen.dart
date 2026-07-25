import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

import '../app/providers.dart';
import '../domain/desktop_service.dart';

/// The desktop's only window: status, connected devices, and pairing.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    // Pairing requests arrive asynchronously and need the user's attention
    // immediately, so they are presented as a modal rather than a list item.
    // A dialog is right here precisely because it is interruptive: a device is
    // asking for control of this machine right now.
    ref.listen(pairingRequestProvider, (previous, next) {
      final request = next.valueOrNull;
      if (request != null) _showPairingDialog(request);
    });

    final service = ref.watch(desktopServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('RemoteLink'),
      ),
      body: service.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _StartupError(error: error),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(DesktopService service) {
    final input = ref.watch(inputAvailabilityProvider).valueOrNull;
    final devices = ref.watch(connectedDevicesProvider);

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        if (input != null && !input.available && input.reason != null)
          _PermissionBanner(
            reason: input.reason!,
            onOpenSettings: service.openAccessibilitySettings,
          ),
        _StatusCard(service: service),
        const SizedBox(height: 24),
        Text(
          'Connected devices',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        devices.when(
          loading: () => const _EmptyState(
            message: 'Waiting for devices to connect…',
          ),
          error: (error, _) => _EmptyState(message: 'Error: $error'),
          data: (list) => list.isEmpty
              ? const _EmptyState(
                  message: 'No devices connected. Open RemoteLink on your '
                      'phone — it should find this computer automatically.',
                )
              : Column(
                  children: <Widget>[
                    for (final device in list)
                      _DeviceTile(
                        device: device,
                        onRevoke: () => service.revoke(device.id),
                        onTierChanged: (tier) =>
                            service.setTier(device.id, tier),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _showPairingDialog(PendingPairing request) async {
    final service = ref.read(desktopServiceProvider).valueOrNull;
    if (service == null) return;

    final approved = await showDialog<bool>(
      context: context,
      // Not dismissible: tapping outside must not be interpretable as either
      // answer. A pairing decision is one the user has to make explicitly.
      barrierDismissible: false,
      builder: (context) => _PairingDialog(request: request),
    );

    if (!mounted) return;
    if (approved ?? false) {
      await service.approvePairing(request);
    } else {
      await service.declinePairing(request);
    }
  }

}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.service});

  final DesktopService service;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              Icon(
                service.isRunning ? Icons.wifi_tethering : Icons.wifi_off,
                size: 40,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      service.isRunning
                          ? 'Discoverable on this network'
                          : 'Not running',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${service.deviceName} · port ${service.boundPort}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 2),
                    // The device ID is shown because it is the only thing a
                    // user can compare when they have two identically named
                    // computers on one network.
                    SelectableText(
                      service.identity.id.value,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.reason, required this.onOpenSettings});

  final String reason;
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                reason,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 16),
            // The banner clears itself within a couple of seconds of the grant,
            // so there is no "I've done it" button to press and no way to be
            // left looking at a stale error.
            FilledButton.tonal(
              onPressed: () => onOpenSettings(),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.onRevoke,
    required this.onTierChanged,
  });

  final ConnectedDevice device;
  final VoidCallback onRevoke;
  final ValueChanged<PermissionTier> onTierChanged;

  @override
  Widget build(BuildContext context) {
    final quality = device.quality;
    return Card(
      child: ListTile(
        leading: Icon(
          device.awaitingPairing ? Icons.hourglass_top : Icons.smartphone,
        ),
        title: Text(device.name),
        subtitle: Text(
          device.awaitingPairing
              ? 'Waiting for pairing approval'
              : '${device.address} · ${quality.roundTripMillis.toStringAsFixed(1)} ms'
                  ' · ${quality.bars}/4',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DropdownButton<PermissionTier>(
              value: device.tier,
              underline: const SizedBox.shrink(),
              onChanged: (tier) => tier == null ? null : onTierChanged(tier),
              items: <DropdownMenuItem<PermissionTier>>[
                for (final tier in PermissionTier.values)
                  DropdownMenuItem<PermissionTier>(
                    value: tier,
                    child: Text(_tierLabel(tier)),
                  ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.link_off),
              tooltip: 'Forget this device',
              onPressed: onRevoke,
            ),
          ],
        ),
      ),
    );
  }

  static String _tierLabel(PermissionTier tier) => switch (tier) {
        PermissionTier.readOnly => 'View only',
        PermissionTier.standard => 'Control',
        PermissionTier.extended => 'Control + files',
        PermissionTier.admin => 'Full access',
      };
}

class _PairingDialog extends StatelessWidget {
  const _PairingDialog({required this.request});

  final PendingPairing request;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Pair this device?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${request.peerName} wants to control this computer.'),
            const SizedBox(height: 20),
            Center(
              child: Text(
                // Spaced into pairs so the eye can compare it against the
                // phone's screen without losing its place — the entire security
                // of this flow rests on the user actually reading both.
                _spaced(request.shortAuthenticationString),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 4,
                    ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Only approve if your phone is showing exactly these six '
              'digits. Different numbers mean something is intercepting the '
              'connection.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Deny'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('The numbers match'),
          ),
        ],
      );

  static String _spaced(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is RemoteLinkError
        ? (error as RemoteLinkError).message
        : error.toString();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'RemoteLink could not start',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
