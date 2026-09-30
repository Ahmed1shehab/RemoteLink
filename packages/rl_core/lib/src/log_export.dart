import 'crash_handler.dart';
import 'file_log_sink.dart';
import 'logging.dart';
import 'redaction.dart';

/// Formats and redacts diagnostic logs and crash reports for user export.
///
/// Diagnostic exports are scrubbed of all sensitive information (IP addresses,
/// MAC addresses, device IDs, cryptographic keys, home directory paths, file
/// names, and known peer names) before leaving the device, in line with the
/// project's strict no-cloud privacy posture.
///
/// The export includes:
/// 1. An optional [header] (e.g. diagnostic generation timestamp or section title).
/// 2. The most recent crash report from [lastCrashReport], if one occurred.
/// 3. Persistent on-disk logs via [fileSink] covering all rotated archive files
///    in chronological order (oldest first).
/// 4. If no [fileSink] exists, recent in-memory log records from [memoryRecords]
///    are used as a fallback, optionally filtered by [filterLevel].
String buildLogExport({
  FileLogSink? fileSink,
  List<LogRecord> memoryRecords = const <LogRecord>[],
  CrashReport? lastCrashReport,
  required LogRedactor redactor,
  LogLevel? filterLevel,
  String? header,
}) {
  final buffer = StringBuffer();

  if (header != null && header.isNotEmpty) {
    buffer.writeln(header);
    buffer.writeln();
  }

  if (lastCrashReport != null) {
    buffer.writeln(lastCrashReport.format());
    buffer.writeln();
  }

  if (fileSink != null) {
    final fileLogs = fileSink.readAllLogs();
    if (fileLogs.isNotEmpty) {
      buffer.write(fileLogs);
      if (!fileLogs.endsWith('\n')) {
        buffer.writeln();
      }
    }
  } else {
    final filtered = filterLevel == null
        ? memoryRecords
        : memoryRecords
            .where((r) => r.level.severity >= filterLevel.severity)
            .toList();
    for (final record in filtered) {
      buffer.writeln(record.toString());
    }
  }

  return redactor.redact(buffer.toString());
}
