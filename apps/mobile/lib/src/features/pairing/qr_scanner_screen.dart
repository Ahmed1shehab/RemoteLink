import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rl_crypto/rl_crypto.dart';

import '../../app/app_icons.dart';

/// Points the camera at the code the computer is showing.
///
/// Pops a [PairingPayload] when it reads one, or nothing when the user backs
/// out. It deliberately does no connecting of its own: a screen holding a live
/// camera should not also be holding a socket, and the caller already owns the
/// decision about what to do with a computer once it has been identified.
///
/// Anything that is not a Remote Link code is ignored rather than reported as
/// an error the user has to dismiss. A camera pointed at a room sees posters,
/// packaging, and Wi-Fi codes, and stopping to complain about each one would
/// make the screen unusable in exactly the situation it exists for.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  /// Guards against the second frame.
  ///
  /// Detection keeps firing while the route pops, and without this the screen
  /// pops twice — taking the device list with it on the second pop, which
  /// looks from the outside like the app closing itself.
  bool _handled = false;

  /// Set once a code was read that is not one of ours.
  ///
  /// A line under the viewfinder rather than a dialog, and it stays: the only
  /// thing that clears it is a successful scan, which closes the screen
  /// anyway. Its job is to answer "is this thing even working?" for someone
  /// holding the phone over a code that will never be accepted.
  bool _sawForeignCode = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final payload = PairingPayload.tryParse(raw);
      if (payload == null) continue;

      _handled = true;
      Navigator.of(context).pop(payload);
      return;
    }

    // Every code in this frame was something else. Said once, quietly.
    if (!_sawForeignCode && capture.barcodes.isNotEmpty && mounted) {
      setState(() => _sawForeignCode = true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Scan code'),
          actions: <Widget>[
            IconButton(
              icon: const AppIcon(AppIcons.settings),
              tooltip: 'Torch',
              onPressed: () => unawaited(_controller.toggleTorch()),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _ScannerUnavailable(
                  error: error,
                  onRetry: () => unawaited(_controller.start()),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'On your computer, open Remote Link and click '
                    '“Pair a phone”.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_sawForeignCode) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      'That code is not from Remote Link.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

/// Shown in place of the viewfinder when the camera cannot run.
///
/// Denial is not a dead end and must not look like one: discovery still finds
/// computers on a normal network, so the way out is to go back to the list,
/// not to give up. The permission case says which switch to flip, because
/// "camera permission denied" without a location is an error message
/// that leaves the user exactly where they were.
class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final unsupported = error.errorCode == MobileScannerErrorCode.unsupported;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ExcludeSemantics(
            child: AppIcon(
              denied ? AppIcons.settings : AppIcons.monitorPlay,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            switch ((denied, unsupported)) {
              (true, _) => 'Remote Link cannot use the camera',
              (_, true) => 'This device has no camera to scan with',
              _ => 'The camera could not start',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            switch ((denied, unsupported)) {
              (true, _) => 'Turn the camera on for Remote Link in your '
                  'device’s Settings, under Apps.\n\nYou can pair without it: '
                  'go back, and the computer appears in the list on its own '
                  'as long as both are on the same Wi-Fi.',
              (_, true) => 'Go back — the computer appears in the list on its '
                  'own as long as both are on the same Wi-Fi.',
              _ => 'Something stopped the camera from starting. Try again, or '
                  'go back and pick the computer from the list.',
            },
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!denied && !unsupported) ...<Widget>[
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: onRetry,
              icon: const AppIcon(AppIcons.settings),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}
