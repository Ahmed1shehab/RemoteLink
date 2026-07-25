import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../input/touchpad_screen.dart';
import '../pairing/pairing_screen.dart';

/// Lists computers found on the network and connects to one.
///
/// This is the app's first screen, and its job is to have nothing on it: the
/// user should open RemoteLink, see their computer already listed, tap it, and
/// be controlling it. No IP addresses, no ports, no "add device" flow. Every
/// piece of state here exists to make that path shorter or to explain why it
/// did not happen.
class DeviceListScreen extends ConsumerWidget {
  const DeviceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(discoveredDevicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Computers'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Search again',
            onPressed: () async {
              final backend = await ref.read(discoveryProvider.future);
              await backend.refresh();
            },
          ),
        ],
      ),
      body: devices.when(
        loading: () => const _Searching(),
        error: (error, _) => _DiscoveryError(error: error),
        data: (list) => list.isEmpty
            ? const _Searching()
            : RefreshIndicator(
                onRefresh: () async {
                  final backend = await ref.read(discoveryProvider.future);
                  await backend.refresh();
                },
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, index) => _DeviceTile(
                    device: list[index],
                    onTap: () => _connect(context, ref, list[index]),
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _connect(
    BuildContext context,
    WidgetRef ref,
    DiscoveredDevice device,
  ) async {
    final client = await ref.read(clientProvider.future);
    final trustStore = await ref.read(trustStoreProvider.future);
    final peer = await trustStore.findById(device.id);

    if (!context.mounted) return;

    // Passing the stored key turns the handshake from trust-on-first-use into
    // strict verification. A server presenting a different key is then rejected
    // outright rather than prompting the user to re-pair — which is exactly the
    // dialog an attacker who took over the address would be hoping for.
    await client.connect(
      ConnectionTarget(
        host: device.address,
        port: device.port,
        deviceId: device.id,
        serverPublicKey: peer != null && !peer.revoked ? peer.publicKey : null,
        displayName: device.name,
      ),
    );

    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            peer == null ? PairingScreen(device: device) : const TouchpadScreen(),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.onTap});

  final DiscoveredDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final canPair = device.beacon.acceptsNewPairings || device.isTrusted;

    return ListTile(
      leading: Icon(
        switch (device.beacon.platform.name) {
          'macos' => Icons.laptop_mac,
          'windows' => Icons.laptop_windows,
          _ => Icons.computer,
        },
        size: 32,
      ),
      title: Text(device.name),
      subtitle: Text(
        device.isTrusted
            ? 'Paired · ${device.address}'
            : canPair
                ? 'Tap to pair · ${device.address}'
                : 'Not accepting new devices',
      ),
      trailing: device.isTrusted
          ? Icon(Icons.verified_user, color: Theme.of(context).colorScheme.primary)
          : const Icon(Icons.chevron_right),
      enabled: canPair,
      onTap: canPair ? onTap : null,
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Looking for computers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Make sure RemoteLink is running on your computer and both '
                'devices are on the same Wi-Fi network.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _DiscoveryError extends StatelessWidget {
  const _DiscoveryError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.wifi_off, size: 48),
              const SizedBox(height: 16),
              Text(
                'Could not search the network',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              // On iOS this is almost always the local-network permission
              // prompt having been declined, which is worth naming explicitly
              // because the fix is in Settings and not in this app.
              Text(
                'RemoteLink needs permission to find devices on your local '
                'network. Check Settings if you declined the prompt.\n\n$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}
