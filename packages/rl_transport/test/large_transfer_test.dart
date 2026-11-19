import 'dart:async';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';
import 'package:test/test.dart';

void main() {
  // Over real loopback sessions, because the defect lived in the seam between
  // the transfer engine and the session: the engine bounded what it believed
  // was in flight, and the session reported a chunk "sent" the moment it was
  // queued. An in-memory test that calls the receiver directly cannot see that.
  test('a 32 MiB send never runs more than the flow-control window ahead',
      () async {
    final link = await _Link.open();
    addTearDown(link.close);
    final data = Uint8List.fromList(
      List<int>.generate(32 * 1024 * 1024, (i) => (i * 31 + 7) & 0xFF),
    );

    var maxAhead = 0;
    final result = await link.transfer(data, (chunk) async {
      final ahead = link.client.currentQuality.sentBytes -
          link.server.currentQuality.receivedBytes;
      if (ahead > maxAhead) maxAhead = ahead;
      await link.client.sendFileChunk(chunk);
    });

    expect(result, CompletionDisposition.completed);
    // With plain `send` this measured the whole file — 32 MiB queued before
    // the peer had read the first chunk, with the heartbeat stuck behind it.
    // The allowance over the window is per-record framing and the MAC.
    expect(maxAhead, lessThanOrEqualTo(kMaximumInFlightFileBytes + 64 * 1024));
    expect(link.client.isEstablished, isTrue);
    expect(link.server.isEstablished, isTrue);
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('fileOfferBatches', () {
    test('keeps a selection that fits in one offer whole', () {
      final items = List<int>.generate(kMaxFileOfferCount, (i) => i);
      expect(fileOfferBatches(items), <List<int>>[items]);
    });

    test('splits a selection past the cap without losing or reordering', () {
      final items = List<int>.generate(kMaxFileOfferCount * 2 + 5, (i) => i);
      final batches = fileOfferBatches(items);
      expect(batches.map((b) => b.length),
          <int>[kMaxFileOfferCount, kMaxFileOfferCount, 5]);
      expect(batches.expand((b) => b), items);
    });

    test('returns nothing for nothing', () {
      expect(fileOfferBatches(<int>[]), isEmpty);
    });
  });
}

final class _Link {
  _Link(this._server, this._remote, this.client, this.server, this.exporter);

  final RemoteLinkServer _server;
  final RemoteLinkClient _remote;
  final Session client;
  final Session server;
  final Uint8List exporter;

  static Future<_Link> open() async {
    final phone = await DeviceIdentity.generate();
    final desktop = await DeviceIdentity.generate();
    final trustStore = InMemoryTrustStore();
    await trustStore.upsert(TrustedPeer(
      id: phone.id,
      publicKey: phone.publicKey,
      name: 'phone',
      platform: PlatformKind.android,
      pairedAt: DateTime.now(),
      permissionTier: PermissionTier.extended.wireValue,
    ));
    final server = RemoteLinkServer(
      identity: desktop,
      capabilities: const Capabilities(Capabilities.mouse),
      trustStore: trustStore,
      clock: SystemClock(),
      port: 0,
    );
    final client = RemoteLinkClient(
      identity: phone,
      capabilities: const Capabilities(Capabilities.mouse),
      clock: SystemClock(),
    );
    await server.start();
    final accepted = server.accepted.first;
    await client.connect(ConnectionTarget(
      host: '127.0.0.1',
      port: server.boundPort,
      deviceId: desktop.id,
      serverPublicKey: desktop.publicKey,
    ));
    final serverSession = await accepted;
    final clientSession = await client.waitUntilConnected();
    return _Link(server, client, clientSession, serverSession.session,
        clientSession.exporterSecret);
  }

  Future<void> close() async {
    await _remote.dispose();
    await _server.stop();
  }

  Future<CompletionDisposition?> transfer(
    Uint8List data,
    Future<void> Function(FileChunk chunk) sendChunk,
  ) async {
    final offer = FileOffer(transferId: 'big', files: <OfferedFile>[
      OfferedFile(
        fileId: 'file-1',
        fileName: 'big.bin',
        size: data.length,
        fileType: 'application/octet-stream',
        sha256: await Primitives.sha256(data),
      ),
    ]);
    final store = _CountingStore();
    final receiver = FileTransferReceiver(
      exporterSecret: server.exporterSecret,
      store: store,
      storageNamespace: 'phone',
    );
    final accept =
        (await receiver.acceptOffer(offer, tier: PermissionTier.extended))
            .accept;
    final done = Completer<CompletionDisposition>();
    final subscription = server.messages.listen((message) async {
      switch (message) {
        case final FileChunk chunk:
          await receiver.receiveChunk(chunk, tier: PermissionTier.extended);
        case final FileComplete complete:
          done.complete(
              await receiver.complete(complete, tier: PermissionTier.extended));
        default:
      }
    });
    try {
      await FileTransferSender(exporterSecret: exporter).sendAccepted(
        offer: offer,
        accept: accept,
        sources: <String, OutgoingFile>{'file-1': _MemoryFile(data)},
        sendChunk: sendChunk,
        sendComplete: client.send,
      );
      return await done.future.timeout(const Duration(seconds: 30));
    } finally {
      await subscription.cancel();
    }
  }
}

final class _MemoryFile implements OutgoingFile {
  _MemoryFile(this.bytes);
  final Uint8List bytes;
  @override
  int get size => bytes.length;
  @override
  Future<Uint8List> read(int offset, int length) async =>
      Uint8List.sublistView(bytes, offset, offset + length);
  @override
  Stream<List<int>> readAll() => Stream<List<int>>.value(bytes);
}

final class _CountingStore implements IncomingTransferStore {
  @override
  Future<Map<String, IncomingFile>> prepare(
    FileOffer offer, {
    required String namespace,
  }) async =>
      <String, IncomingFile>{
        for (final f in offer.files) f.fileId: _MemoryIncoming(f),
      };
}

final class _MemoryIncoming implements IncomingFile {
  _MemoryIncoming(this.offer) : _bytes = Uint8List(offer.size);

  @override
  final OfferedFile offer;
  final Uint8List _bytes;
  int _end = 0;

  @override
  List<ReceivedRange> get receivedRanges => _end == 0
      ? const <ReceivedRange>[]
      : <ReceivedRange>[ReceivedRange(0, _end)];

  @override
  Future<void> write(int offset, Uint8List bytes) async {
    _bytes.setRange(offset, offset + bytes.length, bytes);
    if (offset == _end) _end += bytes.length;
  }

  @override
  Stream<List<int>> read() => Stream<List<int>>.value(_bytes);

  @override
  Future<void> commit() async {}

  @override
  Future<void> delete() async {}
}
