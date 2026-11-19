import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_mobile/src/features/actions/actions_controller.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

void main() {
  test('the controller exposes a received catalog and sends RunCommand on tap',
      () async {
    final computer = await DeviceIdentity.generate();
    final phone = await DeviceIdentity.generate();
    final trust = InMemoryTrustStore();
    addTearDown(trust.dispose);
    await trust.upsert(TrustedPeer(
      id: phone.id,
      publicKey: phone.publicKey,
      name: 'Phone',
      platform: PlatformKind.android,
      pairedAt: DateTime.now(),
      permissionTier: PermissionTier.extended.wireValue,
    ));
    const capabilities = Capabilities(Capabilities.commandRegistry);
    const timeout = Duration(seconds: 10);
    final server = RemoteLinkServer(
      identity: computer,
      capabilities: capabilities,
      trustStore: trust,
      clock: SystemClock(),
      port: 0,
    );
    await server.start();
    addTearDown(server.stop);
    final client = RemoteLinkClient(
      identity: phone,
      capabilities: capabilities,
      clock: SystemClock(),
    );
    addTearDown(client.dispose);

    final pending = server.accepted.first.timeout(timeout);
    await client.connect(ConnectionTarget(
      host: '127.0.0.1',
      port: server.boundPort,
      serverPublicKey: computer.publicKey,
      deviceId: computer.id,
    ));
    await client.waitUntilConnected(timeout: timeout);
    final desktopSession = (await pending).session;
    final arrived =
        client.messages.firstWhere((message) => message is CommandCatalog);
    await desktopSession.send(const CommandCatalog([
      CommandCatalogEntry(id: 'backup-id', name: 'Back up'),
    ]));
    await arrived.timeout(timeout);

    // Opening the Actions tab can happen after the admission catalog arrived.
    final controller = ActionsController(() => client);
    expect(controller.entries.map((entry) => (entry.id, entry.name)),
        [('backup-id', 'Back up')]);

    final sent = desktopSession.messages.first.timeout(timeout);
    expect(await controller.run('backup-id'), isTrue);
    final request = await sent as RunCommand;
    expect(request.commandId, 'backup-id');
    expect(request.parameters, isEmpty);

    await client.disconnect();
    expect(controller.entries, isEmpty);
  });
}
