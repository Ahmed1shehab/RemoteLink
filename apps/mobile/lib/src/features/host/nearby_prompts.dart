import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/motion.dart';
import '../pairing/pairing_code.dart';
import '../transfer/transfer_controller.dart';
import '../transfer/transfer_model.dart';
import 'host_providers.dart';
import 'phone_host_service.dart';

/// The two questions another device can ask this phone, wherever the user is.
///
/// Both used to be asked by the Send tab, which meant they were asked only when
/// the user happened to be looking at it. A file offer that arrived while the
/// touchpad was open produced nothing at all — no sheet, no badge, no sound —
/// and the sender watched a transfer sit at "offered" until it timed out. A
/// device knocking to pair had nowhere to appear at all, because until this
/// release nothing could knock.
///
/// So the prompts moved to the root, next to the share listener, for the same
/// reason that one lives there: an event that arrives from outside the app does
/// not wait for the right screen to be open.
///
/// One at a time, and in that order. Pairing first because it is the question
/// underneath — a device that has not been let in cannot offer anything — and
/// two sheets stacked on one another is how a user ends up approving the one
/// they did not read.
void listenForNearbyPrompts(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
) {
  ref.listen<AsyncValue<List<PendingInboundPairing>>>(
    inboundPairingsProvider,
    (previous, next) {
      if (next.valueOrNull?.isEmpty ?? true) return;
      unawaited(_drain(ref, navigator));
    },
  );

  ref.listen<TransferState>(
    transferControllerProvider,
    (previous, next) {
      final request = next.pendingIncoming;
      if (request == null) return;
      if (previous?.pendingIncoming?.transferId == request.transferId) return;
      unawaited(_drain(ref, navigator));
    },
  );
}

/// True while a prompt is on screen.
///
/// A plain variable rather than provider state: it is a property of the
/// navigator, there is exactly one of those, and putting it in the provider
/// graph would only invite a rebuild to reason about.
bool _promptOnScreen = false;

/// Raises prompts one at a time until there are none left.
///
/// The loop is the part that matters. Two devices can knock while the user is
/// looking at neither, and an earlier version of this simply dropped the
/// second — `showModalBottomSheet` returned null because one was already up,
/// and null read as "declined". The second device was refused without anyone
/// being asked, which is the wrong answer and, worse, a silent one.
Future<void> _drain(WidgetRef ref, GlobalKey<NavigatorState> navigator) async {
  if (_promptOnScreen) return;
  if (navigator.currentContext == null) {
    // Nothing to raise a sheet on yet. This is the cold start: iOS will launch
    // this app in the background to deliver a connection, and the question can
    // arrive before the first frame has been built. Retried on the next frame
    // rather than dropped — the request is still sitting in the host's pending
    // list, and dropping it would leave the other device waiting on an answer
    // nobody was ever asked for.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_drain(ref, navigator)),
    );
    return;
  }

  _promptOnScreen = true;
  try {
    while (true) {
      // Pairing first, and re-read every pass rather than captured: it is the
      // question underneath — a device that has not been let in cannot offer
      // anything — and the list can have changed while the last sheet was up.
      final knocking =
          ref.read(inboundPairingsProvider).valueOrNull?.firstOrNull;
      if (knocking != null) {
        await _askToPair(ref, navigator, knocking);
        continue;
      }

      final offered = ref.read(transferControllerProvider).pendingIncoming;
      if (offered != null) {
        await _askToAccept(ref, navigator, offered);
        continue;
      }

      return;
    }
  } finally {
    _promptOnScreen = false;
  }
}

Future<T?> _showPrompt<T>(
  GlobalKey<NavigatorState> navigator,
  WidgetBuilder builder,
) async {
  final context = navigator.currentContext;
  if (context == null) return null;
  return showModalBottomSheet<T>(
    context: context,
    // Dismissing is an answer, and the answer is no. Both prompts treat a
    // swipe-away and a tap outside as a decline, which is why they can afford
    // to be dismissible at all: there is no state where getting rid of the
    // sheet leaves the other device waiting on something.
    isScrollControlled: true,
    showDragHandle: true,
    builder: builder,
  );
}

/// Asks whether to let a device that has never paired with this phone in.
Future<void> _askToPair(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
  PendingInboundPairing request,
) async {
  final accepted = await _showPrompt<bool>(
    navigator,
    (context) => _PairingPrompt(request: request),
  );

  final service = await ref.read(phoneHostServiceProvider.future);
  if (accepted ?? false) {
    await service.approvePairing(request);
  } else {
    await service.declinePairing(request);
  }
}

/// Asks whether to take what a paired device is offering.
Future<void> _askToAccept(
  WidgetRef ref,
  GlobalKey<NavigatorState> navigator,
  PendingIncomingTransfer request,
) async {
  final accepted = await _showPrompt<bool>(
    navigator,
    (context) => _IncomingPrompt(request: request),
  );

  final controller = ref.read(transferControllerProvider.notifier);
  if (accepted ?? false) {
    await controller.acceptIncomingTransfer(request);
  } else {
    await controller.declineIncomingTransfer(request);
  }
}

/// The sheet a device knocking to pair puts up.
class _PairingPrompt extends StatelessWidget {
  const _PairingPrompt({required this.request});

  final PendingInboundPairing request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return _PromptFrame(
      icon: Icons.link_rounded,
      title: 'A device wants to connect',
      // The device id, not a name it sent. A name is the one thing an unpaired
      // stranger controls completely, and rendering "Ahmed's iPhone" above a
      // code the user is about to approve is precisely the confusion the code
      // exists to defeat.
      subtitle: request.provisionalName,
      body: <Widget>[
        PairingCodeDisplay(
          digits: request.shortAuthenticationString,
          textStyle: text.displaySmall?.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 6,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Connect only if the other device is showing these same six digits. '
          'If they differ, something else is answering — decline and try again.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
      declineLabel: 'Not now',
      acceptLabel: 'Codes match',
    );
  }
}

/// The sheet an incoming transfer puts up.
class _IncomingPrompt extends StatelessWidget {
  const _IncomingPrompt({required this.request});

  final PendingIncomingTransfer request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final files = request.offer.files;
    final count = files.length;

    return _PromptFrame(
      icon: Icons.download_rounded,
      title: count == 1 ? 'Incoming file' : 'Incoming files',
      subtitle: '${request.peerName} · ${formatBytes(request.totalBytes)}',
      body: <Widget>[
        // Named, not counted. "3 files" is not enough to decide with, and the
        // decision is the whole reason this sheet exists.
        for (final file in files.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatBytes(file.size),
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (count > 4)
          Text(
            'and ${count - 4} more',
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: 12),
        Text(
          kIncomingDestinationExplanation,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
      declineLabel: 'Decline',
      acceptLabel: 'Accept',
    );
  }
}

/// The shape both prompts share.
///
/// One frame rather than two layouts, because the two sheets answer the same
/// kind of question and a user who has seen one should not have to read the
/// other's furniture to find the buttons.
class _PromptFrame extends StatelessWidget {
  const _PromptFrame({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.declineLabel,
    required this.acceptLabel,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> body;
  final String declineLabel;
  final String acceptLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      // The sheet is as tall as its content and no taller, but a long file list
      // at a large text size can outgrow the screen, so it scrolls rather than
      // pushing the buttons past the bottom edge — which is the one part of
      // this that must always be reachable.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: scheme.primary, size: 28),
            ),
            const SizedBox(height: 16),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            ...body,
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: _PromptButton(
                    label: declineLabel,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PromptButton(
                    label: acceptLabel,
                    isPrimary: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A prompt's answer, at a size a thumb can hit without looking.
///
/// 52 rather than the framework's 40-ish default. These two buttons sit side by
/// side under a decision the user is making while holding the phone at an
/// angle, and the cost of hitting the wrong one is either letting a stranger in
/// or losing a file someone is watching send.
class _PromptButton extends StatelessWidget {
  const _PromptButton({
    required this.label,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll<Size>(Size.fromHeight(52)),
      animationDuration: context.motion(const Duration(milliseconds: 200)),
    );
    return isPrimary
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton(
            onPressed: onPressed, style: style, child: Text(label));
  }
}
