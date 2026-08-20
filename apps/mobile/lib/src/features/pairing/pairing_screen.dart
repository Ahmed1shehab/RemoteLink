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

    // The session already in hand comes first, and `sessions` is only awaited
    // when there is none. `sessions` is a broadcast stream, so it replays
    // nothing: if the handshake finished before this screen mounted — a fast
    // LAN, a reconnect, a rebuild — `first` waits for a *second* session that
    // is never coming, and the screen stays on "Connecting securely…" with a
    // perfectly good connection underneath it.
    final session = client.session ?? await client.sessions.first;
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

    // Unblocks the session, and it is not a formality.
    //
    // A session that needed pairing starts in `SessionState.pairing`, and in
    // that state `Session` silently drops every message outside subsystems
    // 0x00 and 0x01 — the permission grant, media state, system status, the
    // clipboard, and every byte of a file transfer. Only the desktop was
    // calling this; the phone wrote its trust record, navigated to the
    // controls, and left its own session pairing forever.
    //
    // The result was an app that looked connected and did nothing. The touchpad
    // read "Not connected", the Media tab showed "Nothing playing" against a
    // computer that was playing, and a file offer was answered by a desktop
    // whose reply the phone then discarded. Every one of those reads as a
    // separate bug and all of them were this line.
    //
    // A reconnect to an already-paired computer never hit it: the desktop
    // finds the peer in its trust store, does not ask for pairing, and the
    // session starts established. So this only ever broke the *first* session
    // with a computer — which is every user's first impression of the app.
    session.completePairing();

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
