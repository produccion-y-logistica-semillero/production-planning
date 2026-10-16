// Times in the metrics views: days, hours and minutes, with a finer unit in
// a column only when two algorithms would otherwise look identical.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/shared/duration_format.dart';

void main() {
  test('days, hours and minutes', () {
    expect(formatDuration(const Duration(hours: 37, minutes: 15)),
        '1 d 13 h 15 min');
    expect(formatDuration(const Duration(hours: 2)), '2 h 0 min');
    expect(formatDuration(const Duration(minutes: 5)), '5 min');
    expect(formatDuration(Duration.zero), '0 min');
  });

  test('finer units only when asked for', () {
    const d = Duration(hours: 2, seconds: 30, milliseconds: 4);
    expect(formatDuration(d), '2 h 0 min');
    expect(formatDuration(d, DurationPrecision.second), '2 h 0 min 30 s');
    expect(formatDuration(d, DurationPrecision.millisecond),
        '2 h 0 min 30 s 4 ms');
  });

  test('negative values keep their sign', () {
    expect(formatDuration(const Duration(minutes: -90)), '−1 h 30 min');
  });

  test('a column stays in minutes when that already tells values apart', () {
    expect(
      columnPrecision(const [
        Duration(hours: 2),
        Duration(hours: 2),
        Duration(hours: 3, minutes: 10),
      ]),
      DurationPrecision.minute,
    );
  });

  test('a column goes finer when two values only differ below a minute', () {
    expect(
      columnPrecision(const [
        Duration(hours: 2),
        Duration(hours: 2, seconds: 20),
      ]),
      DurationPrecision.second,
    );
    expect(
      columnPrecision(const [
        Duration(hours: 2),
        Duration(hours: 2, microseconds: 1),
      ]),
      DurationPrecision.microsecond,
    );
  });
}
