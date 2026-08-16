import 'dart:convert';

import '../stats/comparison.dart';
import '../stats/latency_result.dart';

/// Formats and parses benchmark data to and from JSON.
abstract final class JsonFormatter {
  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');
  static const JsonEncoder _compactEncoder = JsonEncoder();

  /// Serializes [result] to JSON string.
  static String formatResult(LatencyResult result, {bool pretty = true}) {
    final encoder = pretty ? _prettyEncoder : _compactEncoder;
    return encoder.convert(result.toJson());
  }

  /// Serializes [comparison] to JSON string.
  static String formatComparison(
    BaselineComparison comparison, {
    bool pretty = true,
  }) {
    final encoder = pretty ? _prettyEncoder : _compactEncoder;
    return encoder.convert(comparison.toJson());
  }

  /// Parses a [LatencyResult] from a JSON string.
  static LatencyResult parseResult(String jsonString) {
    final dynamic decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Expected JSON object for LatencyResult');
    }
    return LatencyResult.fromJson(decoded);
  }
}
