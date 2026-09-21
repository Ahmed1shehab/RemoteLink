import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/ui/pairing_qr.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';

PairingPayload _payloadFor(String host) => PairingPayload(
      deviceId: const DeviceId('ABCDEFGHJKMNPQRSTVWXYZ0123'),
      publicKey: Uint8List.fromList(List<int>.generate(32, (i) => i)),
      name: 'Studio PC',
      host: host,
      port: 47811,
      token: Uint8List(0),
    );

Future<void> _pump(WidgetTester tester, List<String> addresses) async {
  // A desktop-sized surface. The default 800×600 test window is smaller than
  // any window this dialog is ever opened in, and at that size the content
  // scrolls — which is correct behaviour but makes the picker untappable
  // without a scroll step that tests nothing.
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PairingQrDialog(
          addresses: addresses,
          buildPayload: _payloadFor,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders a code for the only address', (tester) async {
    await _pump(tester, <String>['192.168.1.4']);

    final qr = tester.widget<PairingQrCode>(find.byType(PairingQrCode));
    expect(qr.uri, _payloadFor('192.168.1.4').toUri());
    expect(
      PairingPayload.tryParse(qr.uri),
      isNotNull,
      reason: 'whatever is drawn must be something the phone can parse',
    );
    expect(find.text('192.168.1.4:47811'), findsOneWidget);
  });

  testWidgets('offers no address picker when there is nothing to pick',
      (tester) async {
    await _pump(tester, <String>['192.168.1.4']);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('lets the user switch to another address', (tester) async {
    // The reason this control exists: a Docker bridge or VPN adapter can sort
    // ahead of the Wi-Fi address, and a code encoding an unreachable address
    // fails in the least diagnosable way there is — the phone reads it
    // happily and then times out.
    await _pump(tester, <String>['172.17.0.1', '192.168.1.4']);

    expect(
      tester.widget<PairingQrCode>(find.byType(PairingQrCode)).uri,
      contains('h=172.17.0.1'),
    );

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('192.168.1.4').last);
    await tester.pumpAndSettle();

    expect(
      tester.widget<PairingQrCode>(find.byType(PairingQrCode)).uri,
      contains('h=192.168.1.4'),
    );
    expect(find.text('192.168.1.4:47811'), findsOneWidget);
  });

  testWidgets('the code carries this computer’s real static key',
      (tester) async {
    // The point of the whole flow. If the key in the code is not the key the
    // handshake will prove, scanning is no better than typing an address.
    await _pump(tester, <String>['192.168.1.4']);

    final parsed = PairingPayload.tryParse(
      tester.widget<PairingQrCode>(find.byType(PairingQrCode)).uri,
    );
    expect(parsed!.publicKey, _payloadFor('192.168.1.4').publicKey);
    expect(parsed.publicKey, hasLength(32));
  });
}
