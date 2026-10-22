// lib/shared/duration_format.dart
//
// Durations for people: "1 d 13 h 15 min" instead of "37:15:00.000000".
//
// A column of values (one per algorithm) is shown at a single precision: the
// coarsest unit at which every pair of DIFFERENT values still reads as
// different. Normally that is the minute; if two algorithms only differ by
// seconds (or less), that column shows seconds (or ms / µs), so no
// difference is ever hidden by rounding.

/// Smallest unit shown.
enum DurationPrecision { minute, second, millisecond, microsecond }

const _unitMicros = {
  DurationPrecision.minute: Duration.microsecondsPerMinute,
  DurationPrecision.second: Duration.microsecondsPerSecond,
  DurationPrecision.millisecond: Duration.microsecondsPerMillisecond,
  DurationPrecision.microsecond: 1,
};

/// [d] truncated to [precision].
int _truncated(Duration d, DurationPrecision precision) {
  final unit = _unitMicros[precision]!;
  return d.inMicroseconds ~/ unit;
}

/// The coarsest precision at which all distinct values of [values] stay
/// distinct.
DurationPrecision columnPrecision(Iterable<Duration> values) {
  final distinct = values.map((d) => d.inMicroseconds).toSet();
  for (final p in DurationPrecision.values) {
    final shown = distinct
        .map((us) => _truncated(Duration(microseconds: us), p))
        .toSet();
    if (shown.length == distinct.length) return p;
  }
  return DurationPrecision.microsecond;
}

/// "1 d 13 h 15 min", down to [precision]. Leading zero units are skipped;
/// once a unit is shown, the smaller ones down to [precision] are shown too
/// ("2 h 0 min"). Zero is "0 min" (or "0 s", ...).
String formatDuration(Duration d,
    [DurationPrecision precision = DurationPrecision.minute]) {
  final negative = d.isNegative;
  int us = d.inMicroseconds.abs();

  final parts = <(int, String)>[
    (Duration.microsecondsPerDay, 'd'),
    (Duration.microsecondsPerHour, 'h'),
    (Duration.microsecondsPerMinute, 'min'),
    if (precision.index >= DurationPrecision.second.index)
      (Duration.microsecondsPerSecond, 's'),
    if (precision.index >= DurationPrecision.millisecond.index)
      (Duration.microsecondsPerMillisecond, 'ms'),
    if (precision.index >= DurationPrecision.microsecond.index) (1, 'µs'),
  ];

  final out = <String>[];
  for (final (size, label) in parts) {
    final n = us ~/ size;
    us -= n * size;
    if (n > 0 || out.isNotEmpty) out.add('$n $label');
  }
  final text = out.isEmpty ? '0 ${parts.last.$2}' : out.join(' ');
  return negative ? '−$text' : text;
}
