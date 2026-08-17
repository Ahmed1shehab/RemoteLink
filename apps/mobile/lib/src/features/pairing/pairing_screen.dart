import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../control/control_screen.dart';
import 'pairing_code.dart';

/// Shows the six-digit code and waits for the user to confirm it matches.
///
/// The entire security of a first-time connection rests on the user actually
/// comparing these digits, so the screen is built around making that easy: the
/// number is the largest thing on it, grouped into threes so the eye can track
/// position, and the confirm button says what the user is asserting rather than
/// "OK".
///
/// An attacker relaying the connection necessarily runs two separate key
/// agreements and cannot make both transcripts hash to the same digits, so
/// mismatched numbers are a reliable signal — but only if the user looks.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({
    required this.deviceName,
    required this.address,
    this.platform = PlatformKind.unknown,
    super.key,
  });

  /// Name to show while pairing. From the beacon when discovered, or the typed
  /// address when connecting manually.
  final String deviceName;

  /// Where this connection was dialled, stored so a paired computer stays
  /// reachable on networks where discovery does not work.
  final String address;

  final PlatformKind platform;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  String? _code;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    unawaited(_watchSession());
  }

  Future<void> _watchSession() async {
    final client = await ref.read(clientProvider.future);
    final session = await client.sessions.first;
    if (!mounted) return;

    // The SAS is derived locally from the shared secret, not read out of
    // anything the desktop sent. That is precisely why a relay cannot influence
    // it: an attacker in the middle holds two different secrets and the two
    // screens would disagree.
    setState(() => _code = session.shortAuthenticationString);
  }

  Future<void> _confirm() async {
    setState(() => _confirming = true);

    final client = await ref.read(clientProvider.future);
    final trustStore = await ref.read(trustStoreProvider.future);
    final session = client.session;

    if (session == null) {
      if (mounted) setState(() => _confirming = false);
      return;
    }

    // The trust record stores the full 32-byte key proven during the handshake.
    // The beacon's 8-byte fingerprint exists only to pre-filter the device list
    // and must never become the trust key — that would accept any device able
    // to produce a matching 64-bit prefix.
    await trustStore.upsert(
      TrustedPeer(
        id: session.peerId,
        publicKey: session.peerStaticPublicKey,
        name: widget.deviceName,
        platform: widget.platform,
        pairedAt: DateTime.now(),
        permissionTier: 2,
        lastAddress: widget.address,
      ),
    );
    await persistTrustStore(
      trustStore,
      await ref.read(identityStoreProvider.future),
    );

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const ControlScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Pair with ${widget.deviceName}')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (state == ClientState.failed)
              const _PairingFailed()
            else if (_code == null)
              const Column(
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 24),
                  Text('Connecting securely…'),
                ],
              )
            else ...<Widget>[
              Text(
                'Check that your computer is showing these digits',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              PairingCodeDisplay(digits: _code!),
              const SizedBox(height: 32),
              Text(
                'If the numbers are different, something is intercepting the '
                'connection. Cancel and try again on a network you trust.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: _confirming ? null : _confirm,
                child: const Text('The numbers match'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PairingFailed extends StatelessWidget {
  const _PairingFailed();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              Icons.gpp_bad_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Could not establish a secure connection',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'The computer refused the connection, or its identity did not '
            'match what this phone had stored.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
}
