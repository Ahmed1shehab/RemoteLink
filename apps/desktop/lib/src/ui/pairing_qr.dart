import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:rl_crypto/rl_crypto.dart';

/// Shows the code a phone scans to pair with this computer.
///
/// This is the whole setup story on the desktop side, and it replaced two
/// things that read like configuration: reciting an IP address for someone to
/// type, and a Wake-on-LAN button that could not report whether it had worked.
/// The code carries the address, the port, and — the part that matters — this
/// computer's real long-term public key, so the phone verifies the handshake
/// against a key it read with its camera rather than one the network handed it.
///
/// Deliberately a dialog rather than a panel on the window. It is shown while
/// someone is standing at the machine with a phone in their hand, and it is
/// over in a few seconds; a permanent QR on the home screen would be a picture
/// of a secret sitting on a desk all day.
class PairingQrDialog extends StatefulWidget {
  const PairingQrDialog({
    required this.addresses,
    required this.buildPayload,
    super.key,
  });

  /// Every address this computer answers on, in the order the OS reported.
  ///
  /// Plural because the first one is not reliably the right one. A Docker
  /// bridge, a VPN tunnel, or a second NIC can sort ahead of the Wi-Fi address
  /// the phone can actually reach, and a QR encoding an unreachable address
  /// fails in the least diagnosable way there is — the phone scans it happily
  /// and then times out. So the user gets to pick when there is a choice.
  final List<String> addresses;

  /// Builds the payload for a chosen address.
  ///
  /// Injected rather than read from the service inside this widget so the
  /// dialog can be built in a test without starting a listening socket.
  final PairingPayload Function(String host) buildPayload;

  @override
  State<PairingQrDialog> createState() => _PairingQrDialogState();
}

class _PairingQrDialogState extends State<PairingQrDialog> {
  late String _host = widget.addresses.first;

  @override
  Widget build(BuildContext context) {
    final payload = widget.buildPayload(_host);
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: const Text('Pair a phone'),
      // Scrollable because the code has a floor it cannot go below and still
      // be readable across a desk, and a short window — a laptop at 1280×800
      // with the dialog's own insets — leaves less room than that plus the
      // address picker needs.
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Open Remote Link on your phone and tap “Scan code”.',
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              Center(child: PairingQrCode(uri: payload.toUri())),
              const SizedBox(height: 20),
              if (widget.addresses.length > 1) ...<Widget>[
                Text(
                  'This computer has more than one address. If the phone cannot '
                  'reach it, try another.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _host,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final address in widget.addresses)
                      DropdownMenuItem<String>(
                        value: address,
                        child: Text(address),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _host = value);
                  },
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      '$_host:${payload.port}',
                      style: textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy address',
                    onPressed: () => unawaitedCopy('$_host:${payload.port}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

/// Draws one pairing URI as a scannable code.
///
/// Split out from the dialog so a test can assert on the string that is
/// actually encoded. Reading it back off [QrImageView] is not possible — it
/// keeps its data private — and a test that cannot see what was drawn cannot
/// catch the failure that matters here, which is a code encoding the wrong
/// address or a key that is not this computer's.
class PairingQrCode extends StatelessWidget {
  const PairingQrCode({required this.uri, super.key});

  /// The `remotelink://pair/...` string the phone will read.
  final String uri;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          // White and black regardless of the app's theme. A QR code is read
          // by a camera, not by a person, and a dark-mode code drawn in the
          // surface colour is a code that scanners refuse — the quiet zone and
          // the contrast ratio are part of the format, not decoration.
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: QrImageView(
          data: uri,
          size: 240,
          backgroundColor: Colors.white,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
          // The payload is a fixed, machine-read string, so there is nothing
          // to gain from a smaller code and a great deal to lose from one a
          // phone cannot read across a desk.
          errorCorrectionLevel: QrErrorCorrectLevel.M,
        ),
      );
}

/// Puts [text] on the clipboard without making the caller await it.
///
/// Separate function only so the button above stays a one-liner; the clipboard
/// channel is fire-and-forget and there is nothing useful to do with a failure.
void unawaitedCopy(String text) {
  Clipboard.setData(ClipboardData(text: text));
}
