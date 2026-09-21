import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/app_icons.dart';
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
    this.viaScannedCode = false,
    super.key,
  });

  /// Name to show while pairing. From the beacon when discovered, or the typed
  /// address when connecting manually.
  final String deviceName;

  /// Where this connection was dialled, stored so a paired computer stays
  /// reachable on networks where discovery does not work.
  final String address;

  final PlatformKind platform;

  /// Whether the computer's key came off a scanned code rather than the
  /// network.
  ///
  /// It changes what this screen is for. With a scanned key the handshake was
  /// already told which key to accept, so it either authenticated against the
  /// key the camera read or it threw — there is nothing left for the user to
  /// compare, and showing six digits anyway would be asking them to re-check a
  /// question that has already been answered more strongly than they can
  /// answer it.
  ///
  /// It also changes what a failure means. A mismatch here is not "try again";
  /// it is the computer at that address presenting a different identity than
  /// the code did, which is the exact event this flow exists to catch. So the
  /// failure is terminal and offers no way onward — see [_ScannedKeyMismatch].
  final bool viaScannedCode;

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  String? _code;
  bool _confirming = false;

  /// Set when a scanned key did not match the key the computer proved.
  ///
  /// Distinct from a plain connection failure, because the two mean opposite
  /// things: a failure is "could not reach it", this is "reached something,
  /// and it was not the computer on the code".
  bool _keyMismatch = false;

  @override
  void initState() {
    super.initState();
    unawaited(_watchSession());
  }

  Future<void> _watchSession() async {
    final client = await ref.read(clientProvider.future);

    if (widget.viaScannedCode) {
      // `waitUntilConnected` rather than the stream, because this path needs
      // the *error*. A key mismatch is raised inside the reconnect supervisor,
      // which swallows it into a failed state; only the waiter is handed the
      // `SecurityError` itself, and telling a mismatch apart from an
      // unreachable address is the whole point here.
      try {
        await client.waitUntilConnected();
      } on SecurityError {
        if (mounted) setState(() => _keyMismatch = true);
        return;
      } on Object {
        // Everything else is an ordinary connection failure, which the
        // `ClientState.failed` branch of `build` already covers.
        return;
      }
      if (!mounted) return;

      // Nothing to confirm: the camera did the confirming.
      await _confirm();
      return;
    }

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
    ref.invalidate(trustedPeersProvider);

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
            // Checked ahead of the generic failure: a mismatch also leaves the
            // client failed, and the generic copy — "its identity did not
            // match what this phone had stored" — would quietly reframe an
            // impersonated computer as a stale pairing.
            if (_keyMismatch)
              _ScannedKeyMismatch(deviceName: widget.deviceName)
            else if (state == ClientState.failed)
              const _PairingFailed()
            else if (widget.viaScannedCode)
              const Column(
                // Sized to its contents, so the enclosing column's centring
                // actually places it mid-screen: a max-height child fills the
                // body and leaves the spinner pinned under the app bar.
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  CircularProgressIndicator(),
                  SizedBox(height: 24),
                  Text('Checking the code…'),
                ],
              )
            else if (_code == null)
              const Column(
                // Sized to its contents, so the enclosing column's centring
                // actually places it mid-screen: a max-height child fills the
                // body and leaves the spinner pinned under the app bar.
                mainAxisSize: MainAxisSize.min,
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

/// The computer at that address is not the computer on the code.
///
/// No "continue anyway", no fallback to comparing digits, and that absence is
/// the feature. Scanning exists precisely so that a substituted key is caught
/// before any trust is written; offering a softer route afterwards would hand
/// the attacker the dialog they were hoping for, and a user who has just been
/// told something is wrong is exactly the user who taps past it.
class _ScannedKeyMismatch extends StatelessWidget {
  const _ScannedKeyMismatch({required this.deviceName});

  final String deviceName;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: AppIcon(
              AppIcons.settings,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'This is not the computer on the code',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Something answered at that address with a different identity '
            'than the code showed. Remote Link did not pair with it and did '
            'not send it anything.\n\nOn a network you trust this should '
            'never happen. Show the code again on $deviceName and scan the '
            'new one.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
}

class _PairingFailed extends StatelessWidget {
  const _PairingFailed();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: AppIcon(
              AppIcons.settings,
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
