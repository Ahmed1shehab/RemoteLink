import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

// These operations run off the input hot path. Async I/O is intentional: a
// large transfer must never block cursor dispatch on the desktop isolate.
// ignore_for_file: avoid_slow_async_io

import 'package:rl_core/rl_core.dart';
import 'package:rl_crypto/rl_crypto.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

typedef DiskSpaceProbe = Future<int> Function(String canonicalPath);

/// Desktop filesystem adapter for the transport-agnostic transfer engine.
final class FileTransferStore implements IncomingTransferStore {
  FileTransferStore(
    this.destination, {
    DiskSpaceProbe? diskSpaceProbe,
  }) : _diskSpaceProbe = diskSpaceProbe ?? _availableDiskBytes;

  final Directory destination;
  final DiskSpaceProbe _diskSpaceProbe;
  final Map<String, int> _reservations = <String, int>{};
  Future<void> _prepareChain = Future<void>.value();

  @override
  Future<Map<String, IncomingFile>> prepare(
    FileOffer offer, {
    required String namespace,
  }) {
    final result = Completer<Map<String, IncomingFile>>();
    _prepareChain = _prepareChain.then((_) async {
      try {
        result.complete(await _prepareNow(offer, namespace));
      } on Object catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<Map<String, IncomingFile>> _prepareNow(
    FileOffer offer,
    String namespace,
  ) async {
    await destination.create(recursive: true);
    final root = await destination.resolveSymbolicLinks();
    final partialRoot = Directory(_join(root, '.remotelink-partials'));
    await _ensureDirectoryInside(partialRoot, root);

    final transferDirectory = Directory(
      _join(
        partialRoot.path,
        await _stableId('$namespace\u0000${offer.transferId}'),
      ),
    );
    await _ensureDirectoryInside(transferDirectory, root);
    final manifestFile = File(_join(transferDirectory.path, 'manifest.json'));
    final reservationKey = '$namespace\u0000${offer.transferId}';
    final manifest = await _loadManifest(
      manifestFile,
      offer,
      namespace,
      onBytesStored: (count) => _releaseReservation(reservationKey, count),
    );

    var requiredBytes = 0;
    for (final offered in offer.files) {
      final entry = manifest.entries[offered.fileId];
      requiredBytes += offered.size - (entry?.coveredBytes ?? 0);
    }
    final available = await _diskSpaceProbe(root);
    final reservedElsewhere = _reservations.entries
        .where((entry) => entry.key != reservationKey)
        .fold(0, (total, entry) => total + entry.value);
    if (requiredBytes > available - reservedElsewhere) {
      throw InsufficientSpaceError(
        requiredBytes: requiredBytes,
        availableBytes: available,
      );
    }
    _reservations[reservationKey] = requiredBytes;

    for (final offered in offer.files) {
      if (manifest.entries.containsKey(offered.fileId)) continue;
      final partial = File(
        _join(
            transferDirectory.path, '${await _stableId(offered.fileId)}.part'),
      );
      await _createSafePartial(partial, root);
      manifest.entries[offered.fileId] = _DiskEntry(
        offer: offered,
        partial: partial,
        ranges: <ReceivedRange>[],
      );
    }
    await manifest.persist();
    return <String, IncomingFile>{
      for (final entry in manifest.entries.entries)
        entry.key: _DiskIncomingFile(manifest, entry.value, root),
    };
  }

  void _releaseReservation(String key, int bytes) {
    final remaining = (_reservations[key] ?? 0) - bytes;
    if (remaining <= 0) {
      _reservations.remove(key);
    } else {
      _reservations[key] = remaining;
    }
  }
}

final class _DiskManifest {
  _DiskManifest({
    required this.namespace,
    required this.transferId,
    required this.file,
    required this.entries,
    required this.onBytesStored,
  });

  final String namespace;
  final String transferId;
  final File file;
  final Map<String, _DiskEntry> entries;
  final void Function(int bytes) onBytesStored;
  Future<void> _writeChain = Future<void>.value();

  Future<void> persist() {
    final queued = _writeChain.then((_) => _persistNow());
    _writeChain = queued.then((_) {}, onError: (Object _) {});
    return queued;
  }

  Future<void> _persistNow() async {
    final encoded = jsonEncode(<String, Object?>{
      'version': 1,
      'namespace': namespace,
      'transferId': transferId,
      'files': <Object?>[
        for (final entry in entries.values)
          <String, Object?>{
            'fileId': entry.offer.fileId,
            'fileName': entry.offer.fileName,
            'size': entry.offer.size,
            'sha256': entry.offer.sha256 == null
                ? null
                : base64Encode(entry.offer.sha256!),
            'ranges': <Object?>[
              for (final range in entry.ranges) <int>[range.start, range.end],
            ],
          },
      ],
    });
    final temporary = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.create(exclusive: true);
    final output = await temporary.open(mode: FileMode.writeOnly);
    try {
      await output.writeString(encoded);
      await output.flush();
    } finally {
      await output.close();
    }
    await temporary.rename(file.path);
  }
}

final class _DiskEntry {
  _DiskEntry({
    required this.offer,
    required this.partial,
    required this.ranges,
  });

  final OfferedFile offer;
  final File partial;
  final List<ReceivedRange> ranges;

  int get coveredBytes =>
      ranges.fold(0, (total, range) => total + range.length);
}

final class _DiskIncomingFile implements IncomingFile {
  _DiskIncomingFile(this._manifest, this._entry, this._canonicalRoot);

  final _DiskManifest _manifest;
  final _DiskEntry _entry;
  final String _canonicalRoot;

  @override
  OfferedFile get offer => _entry.offer;

  @override
  List<ReceivedRange> get receivedRanges =>
      List<ReceivedRange>.unmodifiable(_entry.ranges);

  @override
  Future<void> write(int offset, Uint8List bytes) async {
    await _verifyRegularFileInside(_entry.partial, _canonicalRoot);
    final length = await _entry.partial.length();
    if (offset != length) {
      throw FileSystemException(
        'non-contiguous chunk: expected offset $length, got $offset',
        _entry.partial.path,
      );
    }
    final output = await _entry.partial.open(mode: FileMode.writeOnlyAppend);
    try {
      await output.writeFrom(bytes);
      await output.flush();
    } finally {
      await output.close();
    }
    _entry.ranges
      ..add(ReceivedRange(offset, offset + bytes.length))
      ..replaceRange(0, _entry.ranges.length, _mergeRanges(_entry.ranges));
    await _manifest.persist();
    _manifest.onBytesStored(bytes.length);
  }

  @override
  Stream<List<int>> read() => _entry.partial.openRead(0, offer.size);

  @override
  Future<void> commit() async {
    await _verifyRegularFileInside(_entry.partial, _canonicalRoot);
    final destination = await _reserveCollisionFreeFile(
      Directory(_canonicalRoot),
      offer.fileName,
    );
    await _entry.partial.rename(destination.path);
    await _verifyRegularFileInside(destination, _canonicalRoot);
    _manifest.entries.remove(offer.fileId);
    await _manifest.persist();
  }

  @override
  Future<void> delete() async {
    final unreceived = offer.size - _entry.coveredBytes;
    final type =
        await FileSystemEntity.type(_entry.partial.path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      await _verifyRegularFileInside(_entry.partial, _canonicalRoot);
      await _entry.partial.delete();
    } else if (type != FileSystemEntityType.notFound) {
      throw FileSystemException(
          'partial is not a regular file', _entry.partial.path);
    }
    _manifest.entries.remove(offer.fileId);
    await _manifest.persist();
    _manifest.onBytesStored(unreceived);
  }
}

Future<_DiskManifest> _loadManifest(
  File file,
  FileOffer offer,
  String namespace, {
  required void Function(int bytes) onBytesStored,
}) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) {
    return _DiskManifest(
      namespace: namespace,
      transferId: offer.transferId,
      file: file,
      entries: <String, _DiskEntry>{},
      onBytesStored: onBytesStored,
    );
  }
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('manifest is not a regular file', file.path);
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(await file.readAsString());
  } on Object catch (error) {
    throw FileSystemException('invalid transfer manifest: $error', file.path);
  }
  if (decoded is! Map<String, Object?> ||
      decoded['version'] != 1 ||
      decoded['namespace'] != namespace ||
      decoded['transferId'] != offer.transferId ||
      decoded['files'] is! List<Object?>) {
    throw FileSystemException('manifest identity mismatch', file.path);
  }

  final offeredById = <String, OfferedFile>{
    for (final item in offer.files) item.fileId: item,
  };
  final entries = <String, _DiskEntry>{};
  for (final raw in decoded['files']! as List<Object?>) {
    if (raw is! Map<String, Object?>) {
      throw FileSystemException('invalid manifest entry', file.path);
    }
    final fileId = raw['fileId'];
    if (fileId is! String) {
      throw FileSystemException('invalid manifest file id', file.path);
    }
    final offered = offeredById[fileId];
    final encodedHash =
        offered?.sha256 == null ? null : base64Encode(offered!.sha256!);
    if (offered == null ||
        raw['fileName'] != offered.fileName ||
        raw['size'] != offered.size ||
        raw['sha256'] != encodedHash ||
        raw['ranges'] is! List<Object?> ||
        entries.containsKey(fileId)) {
      throw FileSystemException('manifest metadata mismatch', file.path);
    }
    final partial = File(
      _join(file.parent.path, '${await _stableId(fileId)}.part'),
    );
    final partialType =
        await FileSystemEntity.type(partial.path, followLinks: false);
    if (partialType != FileSystemEntityType.file) {
      throw FileSystemException(
          'manifest partial is not a regular file', partial.path);
    }
    final length = await partial.length();
    final ranges = <ReceivedRange>[];
    for (final rawRange in raw['ranges']! as List<Object?>) {
      if (rawRange is! List<Object?> ||
          rawRange.length != 2 ||
          rawRange[0] is! int ||
          rawRange[1] is! int) {
        throw FileSystemException('invalid manifest range', file.path);
      }
      final range = ReceivedRange(rawRange[0]! as int, rawRange[1]! as int);
      if (range.start < 0 ||
          range.end <= range.start ||
          range.end > offered.size ||
          range.end > length) {
        throw FileSystemException('manifest range is out of bounds', file.path);
      }
      ranges.add(range);
    }
    final merged = _mergeRanges(ranges);
    if (merged.length != ranges.length) {
      throw FileSystemException('manifest ranges overlap', file.path);
    }
    entries[fileId] = _DiskEntry(
      offer: offered,
      partial: partial,
      ranges: ranges,
    );
  }
  return _DiskManifest(
    namespace: namespace,
    transferId: offer.transferId,
    file: file,
    entries: entries,
    onBytesStored: onBytesStored,
  );
}

Future<void> _ensureDirectoryInside(Directory directory, String root) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.link ||
      type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.directory) {
    throw FileSystemException('unsafe transfer directory', directory.path);
  }
  if (type == FileSystemEntityType.notFound) {
    await directory.create();
  }
  final canonical = await directory.resolveSymbolicLinks();
  if (!_isInside(canonical, root)) {
    throw FileSystemException(
        'transfer directory escapes destination', canonical);
  }
}

Future<void> _createSafePartial(File file, String root) async {
  final parent = await file.parent.resolveSymbolicLinks();
  if (!_isInside(parent, root)) {
    throw FileSystemException('partial parent escapes destination', parent);
  }
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.notFound) {
    throw FileSystemException('unexpected partial path collision', file.path);
  }
  await file.create(exclusive: true);
  final output = await file.open(mode: FileMode.writeOnly);
  await output.close();
  await _verifyRegularFileInside(file, root);
}

Future<void> _verifyRegularFileInside(File file, String root) async {
  final type = await FileSystemEntity.type(file.path, followLinks: false);
  if (type != FileSystemEntityType.file) {
    throw FileSystemException('expected a regular file', file.path);
  }
  final canonical = await file.resolveSymbolicLinks();
  if (!_isInside(canonical, root)) {
    throw FileSystemException('file escapes destination', canonical);
  }
}

Future<File> _reserveCollisionFreeFile(Directory root, String fileName) async {
  final dot = fileName.lastIndexOf('.');
  final hasExtension = dot > 0;
  final stem = hasExtension ? fileName.substring(0, dot) : fileName;
  final extension = hasExtension ? fileName.substring(dot) : '';
  for (var suffix = 1; suffix < 1000000; suffix++) {
    final candidateName =
        suffix == 1 ? fileName : _collisionName(stem, extension, suffix);
    final candidate = File(_join(root.path, candidateName));
    final type =
        await FileSystemEntity.type(candidate.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) continue;
    try {
      await candidate.create(exclusive: true);
      return candidate;
    } on FileSystemException {
      if (!await candidate.exists()) rethrow;
      continue;
    }
  }
  throw FileSystemException(
      'could not allocate collision-free filename', root.path);
}

String _collisionName(String stem, String extension, int suffix) {
  final marker = ' ($suffix)';
  var boundedStem = stem;
  var boundedExtension = extension;
  while (utf8.encode('$boundedStem$marker$boundedExtension').length >
      kMaxFileNameBytes) {
    if (boundedStem.isNotEmpty) {
      boundedStem =
          String.fromCharCodes(boundedStem.runes.toList()..removeLast());
    } else if (boundedExtension.isNotEmpty) {
      boundedExtension = String.fromCharCodes(
        boundedExtension.runes.toList()..removeLast(),
      );
    } else {
      throw const FileSystemException(
        'collision suffix exceeds filename cap',
      );
    }
  }
  return '$boundedStem$marker$boundedExtension';
}

List<ReceivedRange> _mergeRanges(List<ReceivedRange> input) {
  final sorted = List<ReceivedRange>.from(input)
    ..sort((left, right) => left.start.compareTo(right.start));
  final result = <ReceivedRange>[];
  for (final range in sorted) {
    if (result.isEmpty || range.start > result.last.end) {
      result.add(range);
      continue;
    }
    final previous = result.removeLast();
    result.add(
      ReceivedRange(
        previous.start,
        range.end > previous.end ? range.end : previous.end,
      ),
    );
  }
  return result;
}

Future<String> _stableId(String value) async {
  final digest = await Primitives.sha256(utf8.encode(value));
  return digest.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String _join(String parent, String child) =>
    '$parent${Platform.pathSeparator}$child';

bool _isInside(String candidate, String root) =>
    candidate == root || candidate.startsWith('$root${Platform.pathSeparator}');

Future<int> _availableDiskBytes(String canonicalPath) async {
  if (Platform.isWindows) {
    final drive = Directory(canonicalPath).absolute.path.substring(0, 2);
    final result = await Process.run(
      'powershell',
      <String>[
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'(Get-PSDrive -Name $args[0].TrimEnd(":"))[0].Free',
        drive,
      ],
    );
    if (result.exitCode == 0) {
      final bytes = int.tryParse(result.stdout.toString().trim());
      if (bytes != null) return bytes;
    }
  } else {
    final result = await Process.run('df', <String>['-Pk', canonicalPath]);
    if (result.exitCode == 0) {
      final lines = result.stdout
          .toString()
          .trim()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (lines.length >= 2) {
        final columns = lines.last.trim().split(RegExp(r'\s+'));
        final kibibytes = columns.length >= 4 ? int.tryParse(columns[3]) : null;
        if (kibibytes != null) return kibibytes * 1024;
      }
    }
  }
  throw FileSystemException(
      'could not determine available disk space', canonicalPath);
}
