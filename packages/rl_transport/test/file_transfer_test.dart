import 'dart:async';
import 'dart:typed_data';

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';
import 'package:test/test.dart';

void main() {
  final exporter = Uint8List.fromList(List<int>.generate(32, (index) => index));

  test('full encrypted transfer completes end to end in memory', () async {
    final data = _patternBytes(900000);
    final store = _MemoryStore();
    final result = await _transfer(
      data: data,
      exporter: exporter,
      store: store,
      transferId: 'full-transfer',
    );

    expect(result, CompletionDisposition.completed);
    expect(store.delivered['report.bin'], data);
  });

  test('resume after interruption is byte-identical', () async {
    final data = _patternBytes(1100000);
    final store = _MemoryStore();
    final offer = await _offer('resume-transfer', data);
    final source = _MemoryOutgoingFile(data);
    final firstReceiver = FileTransferReceiver(
      exporterSecret: exporter,
      store: store,
      storageNamespace: 'peer-1',
      maximumChunkSize: 128 * 1024,
    );
    final firstAccept =
        (await firstReceiver.acceptOffer(offer, tier: PermissionTier.extended))
            .accept;
    var received = 0;
    await expectLater(
      FileTransferSender(exporterSecret: exporter).sendAccepted(
        offer: offer,
        accept: firstAccept,
        sources: <String, OutgoingFile>{'file-1': source},
        sendChunk: (chunk) async {
          received++;
          if (received > 3) throw StateError('simulated disconnect');
          expect(
            await firstReceiver.receiveChunk(
              chunk,
              tier: PermissionTier.extended,
            ),
            ChunkDisposition.accepted,
          );
        },
        sendComplete: (_) async {},
      ),
      throwsStateError,
    );

    final reconnectExporter = Uint8List.fromList(
      List<int>.generate(32, (index) => 255 - index),
    );
    final resumedReceiver = FileTransferReceiver(
      exporterSecret: reconnectExporter,
      store: store,
      storageNamespace: 'peer-1',
      maximumChunkSize: 128 * 1024,
    );
    final resumedAccept = (await resumedReceiver.acceptOffer(
      offer,
      tier: PermissionTier.extended,
    ))
        .accept;
    expect(_resumeOffset(resumedAccept.fileTokens['file-1']!), 3 * 128 * 1024);

    CompletionDisposition? completion;
    await FileTransferSender(exporterSecret: reconnectExporter).sendAccepted(
      offer: offer,
      accept: resumedAccept,
      sources: <String, OutgoingFile>{'file-1': source},
      sendChunk: (chunk) async {
        expect(
          await resumedReceiver.receiveChunk(
            chunk,
            tier: PermissionTier.extended,
          ),
          ChunkDisposition.accepted,
        );
      },
      sendComplete: (message) async {
        completion = await resumedReceiver.complete(
          message,
          tier: PermissionTier.extended,
        );
      },
    );

    expect(completion, CompletionDisposition.completed);
    expect(store.delivered['report.bin'], data);
  });

  test('whole-file hash mismatch deletes the partial', () async {
    final data = _patternBytes(400000);
    final wrongHash = Uint8List(32)..fillRange(0, 32, 0xA5);
    final store = _MemoryStore();
    final result = await _transfer(
      data: data,
      exporter: exporter,
      store: store,
      transferId: 'bad-hash',
      offeredHash: wrongHash,
    );

    expect(result, CompletionDisposition.hashMismatch);
    expect(store.deletedFiles, contains('file-1'));
    expect(store.delivered, isEmpty);
    expect(store.states['peer-1/bad-hash/file-1']!.deleted, isTrue);
  });

  test('bad chunk CRC is rejected without killing the transfer', () async {
    final data = _patternBytes(1000);
    final store = _MemoryStore();
    final offer = await _offer('crc-transfer', data);
    final receiver = FileTransferReceiver(
      exporterSecret: exporter,
      store: store,
      storageNamespace: 'peer-1',
    );
    final accept =
        (await receiver.acceptOffer(offer, tier: PermissionTier.extended))
            .accept;
    final captured = <FileChunk>[];
    await FileTransferSender(exporterSecret: exporter).sendAccepted(
      offer: offer,
      accept: accept,
      sources: <String, OutgoingFile>{'file-1': _MemoryOutgoingFile(data)},
      sendChunk: (chunk) async => captured.add(chunk),
      sendComplete: (_) async {},
    );
    final valid = captured.single;
    final writer = ByteWriter();
    valid.writeTo(writer);
    final corrupted = writer.toBytes()..last ^= 0x01;

    expect(
      () => FileChunk.readFrom(ByteReader(corrupted)),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'code',
          contains('file_chunk_checksum_mismatch'),
        ),
      ),
    );
    expect(
      await receiver.receiveChunk(valid, tier: PermissionTier.extended),
      ChunkDisposition.accepted,
    );
    final hash = await Primitives.sha256(data);
    expect(
      await receiver.complete(
        FileComplete(
          transferId: offer.transferId,
          fileId: 'file-1',
          sha256: hash,
        ),
        tier: PermissionTier.extended,
      ),
      CompletionDisposition.completed,
    );
  });

  test('session drops a bad chunk CRC and keeps carrying input', () async {
    final phone = await DeviceIdentity.generate();
    final desktop = await DeviceIdentity.generate();
    final trustStore = InMemoryTrustStore();
    await trustStore.upsert(
      TrustedPeer(
        id: phone.id,
        publicKey: phone.publicKey,
        name: 'phone',
        platform: PlatformKind.android,
        pairedAt: DateTime.now(),
        permissionTier: PermissionTier.extended.wireValue,
      ),
    );
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
    addTearDown(() async {
      await client.dispose();
      await server.stop();
      await trustStore.dispose();
    });
    await server.start();
    final accepted = server.accepted.first;
    await client.connect(
      ConnectionTarget(
        host: '127.0.0.1',
        port: server.boundPort,
        deviceId: desktop.id,
        serverPublicKey: desktop.publicKey,
      ),
    );
    final serverSession = await accepted;
    final clientSession = await client.waitUntilConnected();
    final inputMessage = serverSession.session.messages.firstWhere(
      (message) => message is MouseMove,
    );

    await clientSession.send(const _BadCrcChunk());
    await clientSession.send(const MouseMove(deltaX: 3, deltaY: 4));

    expect(await inputMessage, isA<MouseMove>());
    expect(serverSession.session.isEstablished, isTrue);
    expect(clientSession.isEstablished, isTrue);
  });

  test('standard-tier peer is refused before storage is prepared', () async {
    final store = _MemoryStore();
    final offer = await _offer('denied-transfer', _patternBytes(32));
    final receiver = FileTransferReceiver(
      exporterSecret: exporter,
      store: store,
      storageNamespace: 'peer-1',
    );

    final decision =
        await receiver.acceptOffer(offer, tier: PermissionTier.standard);

    expect(decision.accept.fileTokens, isEmpty);
    expect(decision.abort?.reason, FileAbortReason.declined);
    expect(store.prepareCalls, 0);
  });

  test('flow control never exceeds four MiB of unacknowledged bytes', () async {
    final flow = FileTransferFlowControl();
    final releases = <Completer<void>>[];
    final operations = <Future<void>>[];
    for (var index = 0; index < 32; index++) {
      operations.add(
        flow.run(256 * 1024, () {
          final release = Completer<void>();
          releases.add(release);
          return release.future;
        }),
      );
    }
    await Future<void>.delayed(Duration.zero);
    expect(releases, hasLength(16));
    expect(flow.inFlightBytes, kMaximumInFlightFileBytes);
    expect(flow.maximumObservedBytes, kMaximumInFlightFileBytes);

    while (releases.length < 32) {
      final current = List<Completer<void>>.from(releases);
      for (final release in current) {
        if (!release.isCompleted) release.complete();
      }
      await Future<void>.delayed(Duration.zero);
    }
    for (final release in releases) {
      if (!release.isCompleted) release.complete();
    }
    await Future.wait(operations);
    expect(flow.maximumObservedBytes, lessThanOrEqualTo(4 * 1024 * 1024));
  });

  test('traversal name is rejected before any file is opened', () {
    final store = _MemoryStore();

    expect(
      () => FileOffer(
        transferId: 'traversal',
        files: <OfferedFile>[
          OfferedFile(
            fileId: 'file-1',
            fileName: '../outside.txt',
            size: 1,
            fileType: 'text/plain',
          ),
        ],
      ),
      throwsA(isA<Exception>()),
    );
    expect(store.prepareCalls, 0);
    expect(store.openedFiles, 0);
  });
}

Future<CompletionDisposition?> _transfer({
  required Uint8List data,
  required Uint8List exporter,
  required _MemoryStore store,
  required String transferId,
  Uint8List? offeredHash,
}) async {
  final offer = await _offer(transferId, data, sha256: offeredHash);
  final receiver = FileTransferReceiver(
    exporterSecret: exporter,
    store: store,
    storageNamespace: 'peer-1',
  );
  final accept =
      (await receiver.acceptOffer(offer, tier: PermissionTier.extended)).accept;
  CompletionDisposition? completion;
  await FileTransferSender(exporterSecret: exporter).sendAccepted(
    offer: offer,
    accept: accept,
    sources: <String, OutgoingFile>{'file-1': _MemoryOutgoingFile(data)},
    sendChunk: (chunk) async {
      expect(
        await receiver.receiveChunk(chunk, tier: PermissionTier.extended),
        ChunkDisposition.accepted,
      );
    },
    sendComplete: (message) async {
      completion = await receiver.complete(
        message,
        tier: PermissionTier.extended,
      );
    },
  );
  return completion;
}

Future<FileOffer> _offer(
  String transferId,
  Uint8List data, {
  Uint8List? sha256,
}) async =>
    FileOffer(
      transferId: transferId,
      files: <OfferedFile>[
        OfferedFile(
          fileId: 'file-1',
          fileName: 'report.bin',
          size: data.length,
          fileType: 'application/octet-stream',
          sha256: sha256 ?? await Primitives.sha256(data),
        ),
      ],
    );

int _resumeOffset(String token) => int.parse(token.split('.').last);

Uint8List _patternBytes(int length) => Uint8List.fromList(
      List<int>.generate(length, (index) => (index * 31 + 7) & 0xFF),
    );

final class _MemoryOutgoingFile implements OutgoingFile {
  _MemoryOutgoingFile(this.bytes);

  final Uint8List bytes;

  @override
  int get size => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async =>
      Uint8List.sublistView(bytes, offset, offset + length);

  @override
  Stream<List<int>> readAll() => Stream<List<int>>.value(bytes);
}

final class _BadCrcChunk extends Message {
  const _BadCrcChunk();

  @override
  MessageType get type => MessageType.fileChunk;

  @override
  void writeTo(ByteWriter writer) {
    writer
      ..writeString('crc-session-transfer')
      ..writeString('session')
      ..writeString('file-1')
      ..writeString('token')
      ..writeUint64(0)
      ..writeLengthPrefixedBytes(const <int>[1, 2, 3, 4])
      ..writeUint32(0);
  }
}

final class _MemoryStore implements IncomingTransferStore {
  final Map<String, _MemoryIncomingFile> states =
      <String, _MemoryIncomingFile>{};
  final Map<String, Uint8List> delivered = <String, Uint8List>{};
  final List<String> deletedFiles = <String>[];
  int prepareCalls = 0;
  int openedFiles = 0;

  @override
  Future<Map<String, IncomingFile>> prepare(
    FileOffer offer, {
    required String namespace,
  }) async {
    prepareCalls++;
    return <String, IncomingFile>{
      for (final file in offer.files)
        file.fileId: states.putIfAbsent(
          '$namespace/${offer.transferId}/${file.fileId}',
          () {
            openedFiles++;
            return _MemoryIncomingFile(file, delivered, deletedFiles);
          },
        )..verifyOffer(file),
    };
  }
}

final class _MemoryIncomingFile implements IncomingFile {
  _MemoryIncomingFile(this.offer, this._delivered, this._deletedFiles)
      : _bytes = Uint8List(offer.size);

  @override
  final OfferedFile offer;
  final Map<String, Uint8List> _delivered;
  final List<String> _deletedFiles;
  final Uint8List _bytes;
  final List<ReceivedRange> _ranges = <ReceivedRange>[];
  bool deleted = false;

  void verifyOffer(OfferedFile resumed) {
    if (resumed.fileName != offer.fileName || resumed.size != offer.size) {
      throw StateError('resume metadata mismatch');
    }
  }

  @override
  List<ReceivedRange> get receivedRanges =>
      List<ReceivedRange>.unmodifiable(_ranges);

  @override
  Future<void> write(int offset, Uint8List bytes) async {
    if (deleted) throw StateError('file deleted');
    _bytes.setRange(offset, offset + bytes.length, bytes);
    _ranges.add(ReceivedRange(offset, offset + bytes.length));
    _merge();
  }

  void _merge() {
    _ranges.sort((left, right) => left.start.compareTo(right.start));
    for (var index = _ranges.length - 1; index > 0; index--) {
      final left = _ranges[index - 1];
      final right = _ranges[index];
      if (left.end < right.start) continue;
      _ranges[index - 1] = ReceivedRange(
        left.start,
        left.end > right.end ? left.end : right.end,
      );
      _ranges.removeAt(index);
    }
  }

  @override
  Stream<List<int>> read() => Stream<List<int>>.value(_bytes);

  @override
  Future<void> commit() async {
    _delivered[offer.fileName] = Uint8List.fromList(_bytes);
  }

  @override
  Future<void> delete() async {
    deleted = true;
    _bytes.fillRange(0, _bytes.length, 0);
    _ranges.clear();
    _deletedFiles.add(offer.fileId);
  }
}
