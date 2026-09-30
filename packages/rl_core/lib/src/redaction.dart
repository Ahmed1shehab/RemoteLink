import 'device.dart';
import 'logging.dart';
import 'mac_address.dart';

/// Redacts sensitive information from log output prior to export.
///
/// Under the product's no-cloud privacy posture, logs must be scrubbed of
/// identifying information before leaving the device. This covers:
/// - IP addresses (both IPv4 and IPv6)
/// - Hardware MAC addresses
/// - Device IDs (full 26-character Crockford base32 and short forms)
/// - Cryptographic keys, secrets, and session tickets
/// - User file paths under the home directory
/// - User file names (transferred documents, pictures, videos, archives)
/// - Known peer device names
/// - Inlined clipboard contents
final class LogRedactor {
  LogRedactor({
    Iterable<String> knownPeerNames = const <String>[],
    Iterable<String> homeDirectories = const <String>[],
  })  : knownPeerNames = Set<String>.unmodifiable(
          knownPeerNames.map((s) => s.trim()).where((s) => s.isNotEmpty),
        ),
        homeDirectories = List<String>.unmodifiable(
          homeDirectories
              .map((s) => s.trim().replaceAll(RegExp(r'[/\\]+$'), ''))
              .where((s) => s.isNotEmpty),
        );

  /// User-visible peer names to sanitize (e.g. "Ahmed's MacBook Pro").
  final Set<String> knownPeerNames;

  /// User home directories whose subpaths must be masked (e.g. `/Users/ahmed`).
  final List<String> homeDirectories;

  static const String redactedIp = '[REDACTED_IP]';
  static const String redactedMac = '[REDACTED_MAC]';
  static const String redactedDeviceId = '[REDACTED_DEVICE_ID]';
  static const String redactedKey = '[REDACTED_KEY]';
  static const String redactedPath = '[REDACTED_PATH]';
  static const String redactedFile = '[REDACTED_FILE]';
  static const String redactedPeerName = '[REDACTED_PEER_NAME]';
  static const String redactedClipboard = '[REDACTED_CLIPBOARD]';

  // 1. Home directory patterns (POSIX, Windows, and ~)
  // Spaces inside directories are allowed only when followed by a path separator.
  static final RegExp _genericHomePathPattern = RegExp(
    r'(?:/(?:Users|home)/[a-zA-Z0-9_.-]+(?:/(?:[a-zA-Z0-9_.-]+(?: [a-zA-Z0-9_.-]+)*(?=/)|[a-zA-Z0-9_.-]+))*)|'
    r'(?:[a-zA-Z]:\\Users\\[a-zA-Z0-9_.-]+(?:\\[a-zA-Z0-9_.-]+(?: [a-zA-Z0-9_.-]+)*(?=\\)|\\(?:[a-zA-Z0-9_.-]+))*)|'
    r'(?:~/[a-zA-Z0-9_.-]+(?:/(?:[a-zA-Z0-9_.-]+(?: [a-zA-Z0-9_.-]+)*(?=/)|[a-zA-Z0-9_.-]+))*)',
  );

  // 2. MAC addresses: 6 hex pairs separated by : or -, or 3 groups of 4 separated by .
  static final RegExp _macPattern = RegExp(
    r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b|'
    r'\b[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\.[0-9A-Fa-f]{4}\b',
  );

  // 3. Device IDs: 26 Crockford base32 characters, or short forms (5 chars … 5 chars)
  static final RegExp _deviceIdPattern = RegExp(
    r'\b[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{26}\b',
  );
  static final RegExp _shortDeviceIdPattern = RegExp(
    r'\b[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{5}[…\.]{1,3}[0-9A-HJKMNP-TV-Za-hjkmnp-tv-z]{5}\b',
  );

  // 4. Cryptographic keys and tokens:
  // - 64 hex characters (32-byte binary keys / SHA-256 digests)
  // - 43-44 character base64/base64url strings (e.g. Ed25519/X25519 public keys)
  // - Explicit key / token / ticket / secret fields
  static final RegExp _hexKeyPattern = RegExp(r'\b[0-9a-fA-F]{64}\b');
  static final RegExp _base64KeyPattern = RegExp(r'(?<=[\s=:"'
      r"'(\[<]|^)[A-Za-z0-9+/_-]{43,44}={0,2}(?=[\s"
      r"'\),\]>]|$)");
  static final RegExp _explicitKeyPattern = RegExp(
    r'''((?<=[\s,(\[<]|^)(?:staticPublicKey|publicKey|key|token|ticket|auth|secret)\s*[:=]\s*)(?:(["'])(.*?)\2|([A-Za-z0-9+/=_-]{16,}))''',
    caseSensitive: false,
  );

  // 5. IP addresses: IPv4 (dotted quad with 0-255 bounds) and IPv6 forms
  static final RegExp _ipv4Pattern = RegExp(
    r'\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b',
  );

  // IPv6: bracketed forms or unbracketed with :: compression or 7 colons
  static final RegExp _bracketedIpv6Pattern = RegExp(
    r'\[(?:[0-9a-fA-F:.]+(?:%[0-9a-zA-Z]+)?)\]',
  );
  static final RegExp _unbracketedIpv6Pattern = RegExp(
    r'(?:(?<=[\s,(\[<]|^)(?:[0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{0,4}::[0-9a-fA-F:]*(?:%[0-9a-zA-Z]+)?(?=[\s,)\]>]|$))|'
    r'(?:(?<=[\s,(\[<]|^)(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}(?:%[0-9a-zA-Z]+)?(?=[\s,)\]>]|$))',
  );

  // 6. User file names: common transfer extensions (excluding source code like .dart)
  static final RegExp _quotedFileNamePattern = RegExp(
    r'''(["'])([^"']+\.(?:pdf|docx?|xlsx?|pptx?|txt|csv|png|jpe?g|gif|webp|svg|mp4|mov|avi|mkv|mp3|wav|zip|tar|gz|7z|dmg|pkg|exe|apk|bin|iso))\1''',
    caseSensitive: false,
  );
  static final RegExp _unquotedFileNamePattern = RegExp(
    r'\b[a-zA-Z0-9_.-]+\.(?:pdf|docx?|xlsx?|pptx?|txt|csv|png|jpe?g|gif|webp|svg|mp4|mov|avi|mkv|mp3|wav|zip|tar|gz|7z|dmg|pkg|exe|apk|bin|iso)\b',
    caseSensitive: false,
  );
  static final RegExp _explicitFilePattern = RegExp(
    r'''((?<=[\s,(\[<]|^)(?:fileName|file)\s*[:=]\s*)(?:(["'])(.*?)\2|([^\s"',)]+))''',
    caseSensitive: false,
  );

  // 7. Clipboard contents
  static final RegExp _explicitClipboardPattern = RegExp(
    r'''((?<=[\s,(\[<]|^)(?:clipboard|clipboardText)\s*[:=]\s*)(?:(["'])(.*?)\2|([^\s"',)]+))''',
    caseSensitive: false,
  );
  static final RegExp _clipboardTextLinePattern = RegExp(
    r'(\bclipboard text:\s*)(.*)$',
    caseSensitive: false,
  );

  // 8. Explicit peerName field
  static final RegExp _explicitPeerNamePattern = RegExp(
    r'''((?<=[\s,(\[<]|^)peerName\s*[:=]\s*)(?:(["'])(.*?)\2|([^\s"',)]+))''',
    caseSensitive: false,
  );

  /// Redacts all sensitive patterns from [input].
  String redact(String input) {
    if (input.isEmpty) return input;
    var result = input;

    // 1. Explicit configured home directories first (POSIX and Windows separators)
    for (final home in homeDirectories) {
      final escaped = RegExp.escape(home);
      final pattern = RegExp(
        '$escaped(?:[\\\\/](?:[a-zA-Z0-9_.-]+(?: [a-zA-Z0-9_.-]+)*(?=[\\\\/])|[a-zA-Z0-9_.-]+))*',
      );
      result = result.replaceAll(pattern, redactedPath);
    }

    // 2. Generic home directory patterns
    result = result.replaceAll(_genericHomePathPattern, redactedPath);

    // 3. Known peer names (sorted longest first to prevent prefix shadowing)
    final sortedPeers = knownPeerNames.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final peer in sortedPeers) {
      final pattern = RegExp(RegExp.escape(peer), caseSensitive: false);
      result = result.replaceAll(pattern, redactedPeerName);
    }
    result = result.replaceAllMapped(_explicitPeerNamePattern, (m) {
      final quote = m[2] ?? '';
      return '${m[1]}$quote$redactedPeerName$quote';
    });

    // 4. Clipboard contents
    result = result.replaceAllMapped(_explicitClipboardPattern, (m) {
      final quote = m[2] ?? '';
      return '${m[1]}$quote$redactedClipboard$quote';
    });
    result = result.replaceAllMapped(_clipboardTextLinePattern, (m) {
      return '${m[1]}$redactedClipboard';
    });

    // 5. Hardware MAC addresses
    result = result.replaceAll(_macPattern, redactedMac);

    // 6. Device IDs
    result = result.replaceAll(_deviceIdPattern, redactedDeviceId);
    result = result.replaceAll(_shortDeviceIdPattern, redactedDeviceId);

    // 7. Keys and tokens
    result = result.replaceAllMapped(_explicitKeyPattern, (m) {
      final quote = m[2] ?? '';
      return '${m[1]}$quote$redactedKey$quote';
    });
    result = result.replaceAll(_hexKeyPattern, redactedKey);
    result = result.replaceAll(_base64KeyPattern, redactedKey);

    // 8. IP addresses
    result = result.replaceAll(_ipv4Pattern, redactedIp);
    result = result.replaceAll(_bracketedIpv6Pattern, redactedIp);
    result = result.replaceAll(_unbracketedIpv6Pattern, redactedIp);

    // 9. File names
    result = result.replaceAllMapped(_explicitFilePattern, (m) {
      final quote = m[2] ?? '';
      return '${m[1]}$quote$redactedFile$quote';
    });
    result = result.replaceAllMapped(_quotedFileNamePattern, (m) {
      return '${m[1]}$redactedFile${m[1]}';
    });
    result = result.replaceAll(_unquotedFileNamePattern, redactedFile);

    return result;
  }

  /// Returns a copy of [record] with all message strings, string fields,
  /// errors, and stack traces redacted.
  LogRecord redactRecord(LogRecord record) {
    final redactedMessage = redact(record.message);
    final redactedFields = <String, Object?>{};

    for (final entry in record.fields.entries) {
      final value = entry.value;
      if (value is String) {
        redactedFields[entry.key] = redact(value);
      } else if (value is DeviceId || value is MacAddress) {
        redactedFields[entry.key] = redact(value.toString());
      } else {
        redactedFields[entry.key] = value;
      }
    }

    final redactedError =
        record.error != null ? redact(record.error.toString()) : null;
    final redactedStack = record.stackTrace != null
        ? StackTrace.fromString(redact(record.stackTrace.toString()))
        : null;

    return LogRecord(
      level: record.level,
      scope: record.scope,
      message: redactedMessage,
      time: record.time,
      fields: redactedFields,
      error: redactedError,
      stackTrace: redactedStack,
    );
  }
}
