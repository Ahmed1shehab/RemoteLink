import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rl_core/rl_core.dart';
import 'package:rl_protocol/rl_protocol.dart';
import 'package:rl_transport/rl_transport.dart';

/// Direction of a desktop transfer.
enum TransferDirection { incoming, outgoing }

/// Lifecycle states of a desktop transfer.
enum TransferStatus {
  prompting,
  offered,
  inProgress,
  completed,
  cancelled,
  declined,
  failed,
}

/// Progress details for one file in a transfer.
@immutable
final class TransferFileProgress {
  const TransferFileProgress({
    required this.fileId,
    required this.fileName,
    required this.totalBytes,
    required this.transferredBytes,
    this.isComplete = false,
    this.error,
  });

  final String fileId;
  final String fileName;
  final int totalBytes;
  final int transferredBytes;
  final bool isComplete;
  final String? error;

  double get progress =>
      totalBytes > 0 ? (transferredBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  TransferFileProgress copyWith({
    int? transferredBytes,
    bool? isComplete,
    String? error,
  }) =>
      TransferFileProgress(
        fileId: fileId,
        fileName: fileName,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        isComplete: isComplete ?? this.isComplete,
        error: error ?? this.error,
      );
}

/// Complete record of an incoming or outgoing transfer on desktop.
@immutable
final class TransferRecord {
  const TransferRecord({
    required this.transferId,
    required this.peerId,
    required this.peerName,
    required this.direction,
    required this.status,
    required this.files,
    required this.totalBytes,
    required this.transferredBytes,
    this.speedBytesPerSecond = 0.0,
    this.eta,
    required this.createdAt,
    this.completedAt,
    this.errorMessage,
  });

  final String transferId;
  final DeviceId peerId;
  final String peerName;
  final TransferDirection direction;
  final TransferStatus status;
  final List<TransferFileProgress> files;
  final int totalBytes;
  final int transferredBytes;
  final double speedBytesPerSecond;
  final Duration? eta;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? errorMessage;

  double get progress =>
      totalBytes > 0 ? (transferredBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  bool get isActive =>
      status == TransferStatus.inProgress ||
      status == TransferStatus.offered ||
      status == TransferStatus.prompting;

  bool get canCancel => isActive;

  bool get canRetry =>
      status == TransferStatus.failed ||
      status == TransferStatus.cancelled ||
      status == TransferStatus.declined;

  TransferRecord copyWith({
    TransferStatus? status,
    List<TransferFileProgress>? files,
    int? transferredBytes,
    double? speedBytesPerSecond,
    Duration? eta,
    DateTime? completedAt,
    String? errorMessage,
  }) =>
      TransferRecord(
        transferId: transferId,
        peerId: peerId,
        peerName: peerName,
        direction: direction,
        status: status ?? this.status,
        files: files ?? this.files,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        speedBytesPerSecond: speedBytesPerSecond ?? this.speedBytesPerSecond,
        eta: eta ?? this.eta,
        createdAt: createdAt,
        completedAt: completedAt ?? this.completedAt,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

/// An incoming transfer offer awaiting explicit user acceptance.
@immutable
final class PendingIncomingTransfer {
  const PendingIncomingTransfer({
    required this.transferId,
    required this.peerId,
    required this.peerName,
    required this.offer,
    required this.isFirstTransferFromDevice,
    required this.destinationPath,
  });

  final String transferId;
  final DeviceId peerId;
  final String peerName;
  final FileOffer offer;
  final bool isFirstTransferFromDevice;
  final String destinationPath;

  int get totalBytes => offer.files.fold(0, (total, file) => total + file.size);
}

/// Memory-backed outgoing file for strings, snippets, or in-memory buffers.
final class MemoryOutgoingFile implements OutgoingFile {
  MemoryOutgoingFile(this.bytes);

  final Uint8List bytes;

  @override
  int get size => bytes.length;

  @override
  Future<Uint8List> read(int offset, int length) async {
    if (offset < 0 || offset + length > bytes.length) {
      throw RangeError(
        'offset $offset length $length out of bounds for ${bytes.length}',
      );
    }
    return Uint8List.sublistView(bytes, offset, offset + length);
  }

  @override
  Stream<List<int>> readAll() => Stream<List<int>>.value(bytes);
}

/// Filesystem-backed outgoing file.
final class FileBackedOutgoingFile implements OutgoingFile {
  FileBackedOutgoingFile(this.file, this.size);

  final File file;
  @override
  final int size;

  @override
  Future<Uint8List> read(int offset, int length) async {
    final handle = await file.open(mode: FileMode.read);
    try {
      await handle.setPosition(offset);
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }

  @override
  Stream<List<int>> readAll() => file.openRead(0, size);
}

/// Generates a descriptive, safe filename for bare string transfers.
String generateTextSnippetFileName({DateTime? timestamp}) {
  final now = timestamp ?? DateTime.now().toUtc();
  final year = now.year.toString().padLeft(4, '0');
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  final second = now.second.toString().padLeft(2, '0');
  return 'snippet_$year$month${day}_$hour$minute$second.txt';
}

/// Tracks byte transfer rates and computes estimated time remaining.
final class TransferSpeedTracker {
  TransferSpeedTracker({this.windowDuration = const Duration(seconds: 2)});

  final Duration windowDuration;
  final List<(DateTime time, int bytes)> _samples = <(DateTime, int)>[];

  void record(int bytesTransferred, {DateTime? now}) {
    final current = now ?? DateTime.now();
    _samples.add((current, bytesTransferred));
    final cutoff = current.subtract(windowDuration);
    _samples.removeWhere((sample) => sample.$1.isBefore(cutoff));
  }

  double calculateSpeed({DateTime? now}) {
    if (_samples.length < 2) return 0.0;
    final oldest = _samples.first;
    final latest = _samples.last;
    final durationSec =
        latest.$1.difference(oldest.$1).inMicroseconds / 1000000.0;
    if (durationSec <= 0.05) return 0.0;
    final bytesDiff = latest.$2 - oldest.$2;
    if (bytesDiff <= 0) return 0.0;
    return bytesDiff / durationSec;
  }

  Duration? calculateEta(int totalBytes, int transferredBytes, double speed) {
    if (speed <= 0 || transferredBytes >= totalBytes) return null;
    final remainingBytes = totalBytes - transferredBytes;
    final seconds = (remainingBytes / speed).ceil();
    return Duration(seconds: seconds);
  }
}

/// Formats byte counts into human-readable strings.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Formats transfer speed into human-readable strings.
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond < 1024) {
    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }
  if (bytesPerSecond < 1024 * 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
  }
  return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
}

/// Formats an ETA duration into a concise string.
String formatEta(Duration? eta) {
  if (eta == null) return '--';
  final seconds = eta.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final remainingSec = seconds % 60;
  if (minutes < 60) return '${minutes}m ${remainingSec}s';
  final hours = minutes ~/ 60;
  final remainingMin = minutes % 60;
  return '${hours}h ${remainingMin}m';
}
