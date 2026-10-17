// Every duration field can be typed and shown in hh:mm:ss or in minutes
// ("Formato de tiempos"). Storage stays in whole minutes, so seconds round
// to the nearest minute.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/shared/duration_input.dart';

void main() {
  tearDown(() => timeInputFormat.value = TimeInputFormat.minutes);

  group('parseDurationMinutes', () {
    test('plain minutes', () {
      expect(parseDurationMinutes('90'), 90);
      expect(parseDurationMinutes(' 0 '), 0);
    });

    test('hh:mm and hh:mm:ss', () {
      expect(parseDurationMinutes('1:30'), 90);
      expect(parseDurationMinutes('01:30:00'), 90);
      expect(parseDurationMinutes('25:00:00'), 1500);
    });

    test('seconds round to the nearest minute', () {
      expect(parseDurationMinutes('00:10:29'), 10);
      expect(parseDurationMinutes('00:10:30'), 11);
    });

    test('invalid text is rejected instead of becoming zero', () {
      expect(parseDurationMinutes(''), isNull);
      expect(parseDurationMinutes('abc'), isNull);
      expect(parseDurationMinutes('01:75:00'), isNull);
      expect(parseDurationMinutes('01:10:99'), isNull);
      expect(parseDurationMinutes('1:2:3:4'), isNull);
      expect(parseDurationMinutes('-5'), isNull);
    });
  });

  group('formatDurationMinutes', () {
    test('in each format', () {
      expect(formatDurationMinutes(90, TimeInputFormat.minutes), '90');
      expect(formatDurationMinutes(90, TimeInputFormat.hms), '01:30:00');
      expect(formatDurationMinutes(1500, TimeInputFormat.hms), '25:00:00');
    });

    test('round trip', () {
      for (final m in [0, 1, 59, 60, 61, 240, 1439]) {
        expect(parseDurationMinutes(formatDurationMinutes(m, TimeInputFormat.hms)), m);
        expect(parseDurationMinutes(formatDurationMinutes(m, TimeInputFormat.minutes)), m);
      }
    });
  });

  test('hh:mm:ss mask: only digits are typed, colons appear by themselves',
      () {
    expect(HmsMaskFormatter.mask('0'), '0');
    expect(HmsMaskFormatter.mask('01'), '01');
    expect(HmsMaskFormatter.mask('013'), '01:3');
    expect(HmsMaskFormatter.mask('01300'), '01:30:0');
    expect(HmsMaskFormatter.mask('013000'), '01:30:00');
    expect(HmsMaskFormatter.mask('0130009'), '01:30:00'); // at most 6 digits
    expect(HmsMaskFormatter.mask('01:30:00'), '01:30:00'); // pasted text
    expect(parseDurationMinutes(HmsMaskFormatter.mask('013000')), 90);
  });

  test('the setting is stored as hms / min', () {
    expect(timeFormatToStorage(TimeInputFormat.hms), 'hms');
    expect(timeFormatFromStorage('hms\n'), TimeInputFormat.hms);
    expect(timeFormatFromStorage('min'), TimeInputFormat.minutes);
    expect(timeFormatFromStorage(null), TimeInputFormat.minutes);
  });

  test('validator messages depend on the format', () {
    timeInputFormat.value = TimeInputFormat.hms;
    expect(validateDuration('01:75:00'), contains('hh:mm:ss'));
    timeInputFormat.value = TimeInputFormat.minutes;
    expect(validateDuration('x'), contains('minutos'));
    expect(validateDuration('0', allowZero: false), isNotNull);
    expect(validateDuration('', required: false), isNull);
  });

  for (final format in TimeInputFormat.values) {
    testWidgets('DurationField labels and validates in ${format.name}',
        (tester) async {
      timeInputFormat.value = format;
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DurationField(controller: controller, label: 'Descanso'),
        ),
      ));
      expect(find.text('Descanso (${timeFormatLabel(format)})'), findsOneWidget);

      // In hh:mm:ss the user types digits only; the mask adds the colons.
      final valid = format == TimeInputFormat.hms ? '001500' : '15';
      await tester.enterText(find.byType(TextFormField), valid);
      await tester.pump();
      expect(parseDurationMinutes(controller.text), 15);
      expect(find.textContaining('Use '), findsNothing);
    });
  }
}
