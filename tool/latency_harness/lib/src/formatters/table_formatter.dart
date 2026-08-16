import '../stats/comparison.dart';
import '../stats/latency_result.dart';

/// Formats benchmark results and baseline comparisons as ASCII/Unicode tables.
abstract final class TableFormatter {
  static const int _tableWidth = 78;

  /// Formats a [LatencyResult] as a human-readable table.
  static String formatResult(LatencyResult result) {
    final buffer = StringBuffer();
    final divider = '=' * _tableWidth;
    final thinDivider = '-' * _tableWidth;

    buffer.writeln(divider);
    buffer.writeln(' RemoteLink Latency Harness Benchmark Report');
    buffer.writeln(
      ' Mode: ${result.mode.toUpperCase()} | '
      'Samples: ${_formatInt(result.sampleCount)} | '
      'Rate: ${result.targetRateHz} Hz | '
      'Load: ${result.loadProfile}',
    );
    if (result.calibration != null) {
      final cal = result.calibration!;
      buffer.writeln(
        ' Calibration Overhead: '
        '${cal.overheadMillis.toStringAsFixed(3)} ms '
        '(${cal.overheadMicros.toStringAsFixed(1)} µs subtracted)',
      );
    }
    buffer.writeln(divider);

    if (result.rawPercentiles != null) {
      buffer.writeln(
        ' ${_pad('Percentile', 18)}'
        '${_pad('Raw Latency', 20, alignRight: true)}'
        '${_pad('Calibrated Latency', 24, alignRight: true)}',
      );
      buffer.writeln(thinDivider);

      final raw = result.rawPercentiles!;
      final cal = result.percentiles;

      buffer.writeln(
        ' ${_pad('p50 (Median)', 18)}'
        '${_pad('${raw.p50Millis.toStringAsFixed(3)} ms', 20, alignRight: true)}'
        '${_pad('${cal.p50Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('p95', 18)}'
        '${_pad('${raw.p95Millis.toStringAsFixed(3)} ms', 20, alignRight: true)}'
        '${_pad('${cal.p95Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('p99', 18)}'
        '${_pad('${raw.p99Millis.toStringAsFixed(3)} ms', 20, alignRight: true)}'
        '${_pad('${cal.p99Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('p99.9', 18)}'
        '${_pad('${raw.p999Millis.toStringAsFixed(3)} ms', 20, alignRight: true)}'
        '${_pad('${cal.p999Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('Max', 18)}'
        '${_pad('${raw.maxMillis.toStringAsFixed(3)} ms', 20, alignRight: true)}'
        '${_pad('${cal.maxMillis.toStringAsFixed(3)} ms', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('Min', 18)}'
        '${_pad('${raw.minMillis.toStringAsFixed(3)} ms', 20, alignRight: true)}'
        '${_pad('${cal.minMillis.toStringAsFixed(3)} ms', 24, alignRight: true)}',
      );
    } else {
      buffer.writeln(
        ' ${_pad('Percentile', 24)}'
        '${_pad('Latency (ms)', 24, alignRight: true)}'
        '${_pad('Latency (µs)', 24, alignRight: true)}',
      );
      buffer.writeln(thinDivider);

      final p = result.percentiles;

      buffer.writeln(
        ' ${_pad('p50 (Median)', 24)}'
        '${_pad('${p.p50Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}'
        '${_pad('${p.p50.toStringAsFixed(1)} µs', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('p95', 24)}'
        '${_pad('${p.p95Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}'
        '${_pad('${p.p95.toStringAsFixed(1)} µs', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('p99', 24)}'
        '${_pad('${p.p99Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}'
        '${_pad('${p.p99.toStringAsFixed(1)} µs', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('p99.9', 24)}'
        '${_pad('${p.p999Millis.toStringAsFixed(3)} ms', 24, alignRight: true)}'
        '${_pad('${p.p999.toStringAsFixed(1)} µs', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('Max', 24)}'
        '${_pad('${p.maxMillis.toStringAsFixed(3)} ms', 24, alignRight: true)}'
        '${_pad('${p.max.toStringAsFixed(1)} µs', 24, alignRight: true)}',
      );
      buffer.writeln(
        ' ${_pad('Min', 24)}'
        '${_pad('${p.minMillis.toStringAsFixed(3)} ms', 24, alignRight: true)}'
        '${_pad('${p.min.toStringAsFixed(1)} µs', 24, alignRight: true)}',
      );
    }

    buffer.writeln(divider);
    return buffer.toString();
  }

  /// Formats a [BaselineComparison] as a human-readable comparison table.
  static String formatComparison(BaselineComparison comparison) {
    final buffer = StringBuffer();
    final divider = '=' * _tableWidth;
    final thinDivider = '-' * _tableWidth;

    buffer.writeln(divider);
    buffer.writeln(
      ' Baseline Comparison '
      '(Regression Threshold: +${comparison.thresholdPercent.toStringAsFixed(1)}%)',
    );
    buffer.writeln(divider);

    buffer.writeln(
      ' ${_pad('Metric', 10)}'
      '${_pad('Baseline', 14, alignRight: true)}'
      '${_pad('Current', 14, alignRight: true)}'
      '${_pad('Delta', 14, alignRight: true)}'
      '${_pad('% Change', 12, alignRight: true)}'
      '${_pad('Status', 12, alignRight: true)}',
    );
    buffer.writeln(thinDivider);

    for (final m in comparison.metrics) {
      final sign = m.deltaMillis >= 0 ? '+' : '';
      final pctSign = m.percentageChange >= 0 ? '+' : '';
      final statusLabel = switch (m.status) {
        ComparisonStatus.pass => 'PASS',
        ComparisonStatus.regression => 'FAIL (REG)',
      };

      buffer.writeln(
        ' ${_pad(m.metricName, 10)}'
        '${_pad('${m.baselineMillis.toStringAsFixed(3)} ms', 14, alignRight: true)}'
        '${_pad('${m.currentMillis.toStringAsFixed(3)} ms', 14, alignRight: true)}'
        '${_pad('$sign${m.deltaMillis.toStringAsFixed(3)} ms', 14, alignRight: true)}'
        '${_pad('$pctSign${m.percentageChange.toStringAsFixed(2)}%', 12, alignRight: true)}'
        '${_pad(statusLabel, 12, alignRight: true)}',
      );
    }

    buffer.writeln(divider);
    if (comparison.hasRegressions) {
      buffer.writeln(
        ' RESULT: FAILED - ${comparison.regressionCount} metric(s) '
        'regressed beyond +${comparison.thresholdPercent.toStringAsFixed(1)}% threshold.',
      );
    } else {
      buffer.writeln(
        ' RESULT: PASSED - All percentiles within +${comparison.thresholdPercent.toStringAsFixed(1)}% threshold.',
      );
    }
    buffer.writeln(divider);

    return buffer.toString();
  }

  static String _pad(String text, int width, {bool alignRight = false}) {
    if (text.length >= width) return text;
    final padding = ' ' * (width - text.length);
    return alignRight ? '$padding$text' : '$text$padding';
  }

  static String _formatInt(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    var count = 0;
    for (var i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i != 0) {
        buffer.write(',');
      }
    }
    return buffer.toString().split('').reversed.join();
  }
}
