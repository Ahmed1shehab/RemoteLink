import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import '../input/touchpad_screen.dart';

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
  const PairingScreen({required this.device, super.key});

  final DiscoveredDevice device;

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
        name: widget.device.name,
        platform: widget.device.beacon.platform,
        pairedAt: DateTime.now(),
        permissionTier: 2,
        lastAddress: widget.device.address,
      ),
    );
    await persistTrustStore(trustStore);

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const TouchpadScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text('Pair with ${widget.device.name}')),
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
              Text(
                _grouped(_code!),
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontFamily: 'monospace',
                      letterSpacing: 6,
                    ),
              ),
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

  static String _grouped(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

class _PairingFailed extends StatelessWidget {
  const _PairingFailed();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.gpp_bad_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.error,
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
