import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';
import 'auto_connect.dart';

/// Shows what is happening while a computer holds this phone at its door.
///
/// Raised from the root rather than from a screen, and as an overlay rather
/// than as a route, because the hold can begin at any moment and the phone may
/// be anywhere when it does. A reconnect after a Wi-Fi drop arrives while the
/// user is on the touchpad; an auto-connect at launch arrives before any screen
/// has settled. Pushing a route from either place would mean guessing what to
/// pop back to.
///
/// It is not decoration. A held session drops every message outside the
/// handshake and trust subsystems, so without something on screen the phone
/// shows a touchpad that moves no cursor and a Send button whose files go
/// nowhere — and the user has no way to learn that the answer is on the other
/// device, in a dialog nobody has walked over to yet.
void listenForConnectionHolds(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
) {
  ref.listen<AsyncValue<ClientState>>(clientStateProvider, (previous, next) {
    switch (next.valueOrNull) {
      case ClientState.awaitingApproval:
        unawaited(_show(ref, navigator));
      case ClientState.failed:
        _announceRefusal(ref, navigator);
      case _:
        break;
    }
  });
}

/// True while the wait is on screen, so a second state change cannot stack a
/// second copy of it on top of the first.
bool _holdOnScreen = false;

Future<void> _show(WidgetRef ref, GlobalKey<NavigatorState> navigator) async {
  if (_holdOnScreen) return;
  final context = navigator.currentContext;
  if (context == null) {
    // No screen yet — a cold start that auto-connected before the first frame.
    // Retried rather than dropped: the connection is genuinely being held, and
    // a phone left looking at a splash screen with no explanation is the exact
    // outcome this exists to prevent.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_show(ref, navigator)),
    );
    return;
  }

  _holdOnScreen = true;
  try {
    await showDialog<void>(
      context: context,
      // Not dismissible, because dismissing it would not answer anything. The
      // decision belongs to the other device; the only thing this end can do is
      // stop waiting, and that is a button with a name on it.
      barrierDismissible: false,
      builder: (context) => const WaitingForApprovalDialog(),
    );
  } finally {
    _holdOnScreen = false;
  }
}

/// Says out loud that a connection was turned away.
///
/// Only for a refusal. Every other reason a connection fails already has its
/// own copy somewhere — a key mismatch, an unreachable address — and this is
/// the one where "could not connect" would send the user to check their Wi-Fi
/// over a decision a person made on purpose.
void _announceRefusal(WidgetRef ref, GlobalKey<NavigatorState> navigator) {
  final client = ref.read(clientProvider).valueOrNull;
  final refusal = client?.refusal;
  if (refusal == null) return;

  final context = navigator.currentContext;
  if (context == null) return;

  final name = client?.target?.displayName ?? 'That device';
  final message = switch (refusal) {
    ConnectionAnswer.declined => '$name did not allow the connection.',
    ConnectionAnswer.timedOut =>
      'Nobody answered on $name, so the connection was not allowed.',
    ConnectionAnswer.allowed => null,
  };
  if (message == null) return;

  // Back to the device list, because there is nothing left to do on the
  // screens above it. Auto-connect takes the phone straight to the controls on
  // launch, and a refusal a second later would otherwise leave the user
  // holding a touchpad that moves nothing, with the explanation in a snackbar
  // they are about to scroll past.
  navigator.currentState?.popUntil((route) => route.isFirst);

  final target = client?.target;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        // Offered for a timeout and not for a decline, and the difference is
        // the whole reason this is here. A decline is an answer, and putting a
        // button next to it that dials straight back is how an app badgers
        // someone into changing their mind. Nobody being at the computer is
        // not an answer — it is the case where the user walks over to it and
        // needs the phone to try once more, and without this that costs
        // finding the device in the list again.
        action: refusal == ConnectionAnswer.timedOut && target != null
            ? SnackBarAction(
                label: 'Try again',
                onPressed: () async {
                  final client = await ref.read(clientProvider.future);
                  await client.connect(target);
                },
              )
            : null,
      ),
    );
}

/// The overlay itself: what is happening, who has to act, and a way out.
///
/// Public so a test can drive the real thing. A dialog reachable only through a
/// live socket is a dialog nothing asserts on, and what this one says — and
/// that it takes itself away again — is the whole of it.
class WaitingForApprovalDialog extends ConsumerWidget {
  const WaitingForApprovalDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pops itself when the wait ends, whichever way it ended. The alternative —
    // dismissing it from the listener that opened it — needs a context that
    // outlives the route, which is the shape that leaves a dialog up over a
    // connected app when the timing is unlucky.
    ref.listen<AsyncValue<ClientState>>(clientStateProvider, (previous, next) {
      if (next.valueOrNull == ClientState.awaitingApproval) return;
      if (!context.mounted) return;
      Navigator.of(context).pop();
    });

    final name = ref.watch(clientProvider).valueOrNull?.heldBy ??
        ref.watch(clientProvider).valueOrNull?.target?.displayName ??
        'that device';

    return AlertDialog(
      title: const Text('Waiting to be let in'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 24),
          Text('$name is asking whether to allow this connection.'),
          const SizedBox(height: 8),
          Text(
            'Go to it and tap Allow. Nothing is sent until someone does.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () async {
            // Auto-connect first, or the supervisor dials straight back in and
            // the wait reappears a second after the user asked it not to.
            ref.read(autoConnectProvider.notifier).cancel();
            final client = await ref.read(clientProvider.future);
            await client.disconnect();
          },
          child: const Text('Stop waiting'),
        ),
      ],
    );
  }
}
