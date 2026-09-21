import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

import '../../app/providers.dart';

/// The question this phone is putting to its user about a connected device.
///
/// Null when there is nothing to ask, which is the ordinary case: a device is
/// asked about once, and a device both ends agreed to is not asked about again.
@immutable
final class RememberPrompt {
  const RememberPrompt({required this.peerId, required this.peerName});

  final DeviceId peerId;

  /// The stored name, never one the peer sent with this connection.
  final String peerName;
}

/// Runs this phone's half of a "remember each other?" agreement.
///
/// Both ends ask, both answer, and a device is only remembered when both said
/// yes — the reasoning is on `RememberConnection`. This end's part is to put
/// the question once, send the answer, wait for the peer's, and write down
/// whatever the pair of them adds up to.
final class RememberController extends StateNotifier<RememberPrompt?> {
  RememberController(this._ref) : super(null);

  final Ref _ref;
  final Log _log = Log.scoped('mobile.remember');

  RememberAgreement? _agreement;

  /// A session came up. Decides whether there is anything to ask.
  Future<void> onConnected() async {
    final session = _ref.read(clientProvider).valueOrNull?.session;
    if (session == null) return;
    if (_agreement?.peerId == session.peerId) return;

    final store = await _ref.read(trustStoreProvider.future);
    final peer = await store.findById(session.peerId);
    if (!shouldAskToRemember(peer)) return;

    _agreement = RememberAgreement(
      peerId: session.peerId,
      peerName: peer!.name,
    );
    state = RememberPrompt(peerId: peer.id, peerName: peer.name);
  }

  /// The link went. Nothing half-agreed survives it — see the class comment on
  /// [RememberAgreement] — so the question is simply dropped and put again the
  /// next time both ends are up.
  void onDisconnected() {
    _agreement = null;
    state = null;
  }

  /// What the user said, on its way to the peer.
  Future<void> answer({required bool agreed}) async {
    final agreement = _agreement;
    if (agreement == null) return;
    state = null;
    if (!agreement.recordMine(agreed: agreed)) return;

    final client = _ref.read(clientProvider).valueOrNull;
    // Sent either way. A peer with its own copy of this question on screen has
    // no way to take it down but an answer, and withholding a no strands it.
    await client?.send(RememberConnection(agreed: agreed));
    await _settle();
  }

  /// The peer's half of the agreement.
  Future<void> onPeerAnswer({required bool agreed}) async {
    final agreement = _agreement;
    if (agreement == null) {
      // Nothing was asked here, so this phone already remembers the device and
      // its answer is already yes. Saying so lets a peer that has forgotten us
      // — a reinstall, a cleared trust file — agree again without a round that
      // could never complete.
      await _answerOnBehalfOfAnAgreementAlreadyMade();
      return;
    }
    if (!agreement.recordTheirs(agreed: agreed)) return;
    await _settle();
  }

  Future<void> _answerOnBehalfOfAnAgreementAlreadyMade() async {
    final session = _ref.read(clientProvider).valueOrNull?.session;
    if (session == null) return;
    final store = await _ref.read(trustStoreProvider.future);
    final peer = await store.findById(session.peerId);
    if (peer == null || !peer.autoAdmit) return;
    await _ref
        .read(clientProvider)
        .valueOrNull
        ?.send(const RememberConnection(agreed: true));
  }

  /// Writes down a settled agreement, and only a settled one.
  Future<void> _settle() async {
    final agreement = _agreement;
    // Nothing is written before this phone's own user has answered, and the
    // agreement is kept alive while it is only half answered so the peer's
    // answer arriving later in this session can still settle it.
    if (agreement == null || agreement.mine == null) return;
    if (agreement.isSettled) _agreement = null;

    final store = await _ref.read(trustStoreProvider.future);
    final peer = await store.findById(agreement.peerId);
    if (peer == null) return;

    await store.upsert(agreement.applyTo(peer));
    await persistTrustStore(
      store,
      await _ref.read(identityStoreProvider.future),
    );
    _ref.invalidate(trustedPeersProvider);

    _log.info(
      switch ((agreement.isAgreed, agreement.isSettled)) {
        (true, _) => 'both ends agreed to remember each other',
        (_, true) => 'this connection will not be remembered',
        (_, false) => 'answered here; waiting on the other end',
      },
      fields: <String, Object?>{'peer': agreement.peerId.value},
    );
  }

  /// Turns remembering on or off for a peer from the device list.
  ///
  /// The way out of an agreement. Switching it off does not un-pair anything;
  /// the device goes back to being asked about.
  Future<void> setRemembered(DeviceId peerId, {required bool remember}) async {
    final store = await _ref.read(trustStoreProvider.future);
    final peer = await store.findById(peerId);
    if (peer == null) return;
    await store.upsert(
      peer.copyWith(autoAdmit: remember, rememberAsked: true),
    );
    await persistTrustStore(
      store,
      await _ref.read(identityStoreProvider.future),
    );
    _ref.invalidate(trustedPeersProvider);
  }
}

final rememberPromptProvider =
    StateNotifierProvider<RememberController, RememberPrompt?>(
  RememberController.new,
);

/// Wires the controller to the session it is about.
///
/// Watched at the root, like the other listeners there: the answer decides what
/// happens on the *next* launch, so it cannot belong to a screen that may not
/// be open when the connection comes up.
final rememberNegotiationProvider = Provider<void>((ref) {
  final controller = ref.read(rememberPromptProvider.notifier);

  ref.listen<AsyncValue<ClientState>>(
    clientStateProvider,
    (previous, next) {
      switch (next.valueOrNull) {
        case ClientState.connected:
          unawaited(controller.onConnected());
        case null:
          break;
        case _:
          controller.onDisconnected();
      }
    },
    fireImmediately: true,
  );

  // Subscribed to the client directly rather than to a message provider, so
  // that nothing depends on a screen happening to be watching the stream at
  // the moment the peer answers.
  unawaited(() async {
    final client = await ref.read(clientProvider.future);
    final subscription = client.messages.listen((message) {
      if (message is! RememberConnection) return;
      unawaited(controller.onPeerAnswer(agreed: message.agreed));
    });
    ref.onDispose(subscription.cancel);
  }());
});

/// Puts the question on screen wherever the user happens to be.
void listenForRememberPrompts(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
) {
  ref.listen<RememberPrompt?>(rememberPromptProvider, (previous, next) {
    if (next == null) return;
    unawaited(_ask(ref, navigator, next));
  });
}

/// True while the question is on screen, so a reconnect cannot stack a second
/// copy on the first.
bool _promptOnScreen = false;

Future<void> _ask(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
  RememberPrompt prompt,
) async {
  if (_promptOnScreen) return;
  final context = navigator.currentContext;
  // No screen yet. Dropped rather than retried, unlike the hold dialog: nothing
  // is waiting on this answer, and the question comes back the next time this
  // device connects.
  if (context == null) return;

  _promptOnScreen = true;
  try {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => RememberDeviceDialog(peerName: prompt.peerName),
    );
    await ref
        .read(rememberPromptProvider.notifier)
        .answer(agreed: agreed ?? false);
  } finally {
    _promptOnScreen = false;
  }
}

/// Asks whether this phone should stop being asked about a device.
///
/// Public so a test can drive the real thing rather than a copy of it.
class RememberDeviceDialog extends StatelessWidget {
  const RememberDeviceDialog({required this.peerName, super.key});

  final String peerName;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Remember this connection?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Remote Link can reconnect to $peerName by itself next time — no '
              'code to scan, and nobody asked to allow it.',
            ),
            const SizedBox(height: 12),
            Text(
              '$peerName is being asked the same thing. Both devices have to '
              'agree, and either one can change its mind later.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remember'),
          ),
        ],
      );
}
