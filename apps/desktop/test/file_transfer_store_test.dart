import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remotelink_desktop/src/domain/file_transfer_store.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';

void main() {
  late Directory sandbox;
  late Directory destination;

  setUp(() async {
    sandbox =
        await Directory.systemTemp.createTemp('remotelink-transfer-test-');
    destination = Directory('${sandbox.path}/destination');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('persists ranges and resumes into a byte-identical file', () async {
    final bytes = _patternBytes(600000);
    final offer = _offer('resume', bytes.length);
    final firstStore = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 10 * 1024 * 1024,
    );
    final first =
        (await firstStore.prepare(offer, namespace: 'peer-1'))['file-1']!;
    await first.write(0, Uint8List.sublistView(bytes, 0, 300000));

    final resumedStore = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 10 * 1024 * 1024,
    );
    final resumed =
        (await resumedStore.prepare(offer, namespace: 'peer-1'))['file-1']!;
    expect(resumed.receivedRanges.single.start, 0);
    expect(resumed.receivedRanges.single.end, 300000);
    await resumed.write(300000, Uint8List.sublistView(bytes, 300000));
    await resumed.commit();

    expect(
      await File('${destination.path}/report.bin').readAsBytes(),
      bytes,
    );
  });

  test('does not follow a destination filename symlink and avoids overwrite',
      () async {
    await destination.create(recursive: true);
    final outside = File('${sandbox.path}/outside.txt');
    await outside.writeAsString('untouched');
    await Link('${destination.path}/report.bin').create(outside.path);
    final store = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 1024,
    );
    final file = (await store.prepare(
      _offer('collision', 4),
      namespace: 'peer-1',
    ))['file-1']!;
    await file.write(0, Uint8List.fromList(<int>[1, 2, 3, 4]));
    await file.commit();

    expect(await outside.readAsString(), 'untouched');
    expect(
      await File('${destination.path}/report (2).bin').readAsBytes(),
      <int>[1, 2, 3, 4],
    );
  });

  test('rejects a symlinked partial directory without writing outside',
      () async {
    await destination.create(recursive: true);
    final outside = Directory('${sandbox.path}/outside')..createSync();
    await Link('${destination.path}/.remotelink-partials').create(outside.path);
    final store = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 1024,
    );

    await expectLater(
      store.prepare(_offer('escape', 4), namespace: 'peer-1'),
      throwsA(isA<FileSystemException>()), // escape, not a space problem
    );
    expect(await outside.list().toList(), isEmpty);
  });

  test('refuses insufficient disk space before creating a partial file',
      () async {
    final store = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 3,
    );

    await expectLater(
      store.prepare(_offer('too-large', 4), namespace: 'peer-1'),
      throwsA(isA<InsufficientSpaceError>()),
    );
    final entities = destination.existsSync()
        ? await destination.list(recursive: true, followLinks: false).toList()
        : <FileSystemEntity>[];
    expect(entities.whereType<File>(), isEmpty);
  });

  test('isolates attacker-controlled transfer IDs by authenticated peer',
      () async {
    final store = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 1024,
    );
    final offer = _offer('same-id', 4);
    final first = (await store.prepare(offer, namespace: 'peer-1'))['file-1']!;
    final second = (await store.prepare(offer, namespace: 'peer-2'))['file-1']!;
    await first.write(0, Uint8List.fromList(<int>[1, 1, 1, 1]));
    await second.write(0, Uint8List.fromList(<int>[2, 2, 2, 2]));
    await first.commit();
    await second.commit();

    expect(
      await File('${destination.path}/report.bin').readAsBytes(),
      <int>[1, 1, 1, 1],
    );
    expect(
      await File('${destination.path}/report (2).bin').readAsBytes(),
      <int>[2, 2, 2, 2],
    );
  });

  test('reserves promised bytes across concurrent offers', () async {
    final store = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 6,
    );
    await store.prepare(_offer('first', 4), namespace: 'peer-1');

    await expectLater(
      store.prepare(_offer('second', 4), namespace: 'peer-2'),
      throwsA(isA<InsufficientSpaceError>()),
    );
  });

  test(
      'a hostile fileType arriving from a peer does not influence destination path',
      () async {
    final store = FileTransferStore(
      destination,
      diskSpaceProbe: (_) async => 1024,
    );
    final hostileOffer = FileOffer(
      transferId: 'hostile-mime',
      files: <OfferedFile>[
        OfferedFile(
          fileId: 'file-1',
          fileName: 'report.pdf',
          size: 4,
          fileType: '../../../../evil/path/traversal.sh',
        ),
      ],
    );
    final prepared =
        (await store.prepare(hostileOffer, namespace: 'peer-1'))['file-1']!;
    await prepared.write(0, Uint8List.fromList(<int>[1, 2, 3, 4]));
    await prepared.commit();

    expect(
      await File('${destination.path}/report.pdf').readAsBytes(),
      <int>[1, 2, 3, 4],
    );
    expect(File('${sandbox.path}/traversal.sh').existsSync(), isFalse);
    expect(File('${sandbox.path}/evil').existsSync(), isFalse);
  });
}

FileOffer _offer(String transferId, int size) => FileOffer(
      transferId: transferId,
      files: <OfferedFile>[
        OfferedFile(
          fileId: 'file-1',
          fileName: 'report.bin',
          size: size,
          fileType: 'application/octet-stream',
        ),
      ],
    );

Uint8List _patternBytes(int length) => Uint8List.fromList(
      List<int>.generate(length, (index) => (index * 17 + 3) & 0xFF),
    );
