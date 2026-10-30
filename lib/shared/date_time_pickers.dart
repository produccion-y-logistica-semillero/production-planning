// lib/shared/date_time_pickers.dart
//
// One way to enter and show a clock time or a date-time everywhere in the
// app: release and due dates of the program, machine start, maintenance
// start and the work shift. The hour is typed (HH:mm, 24 h) instead of
// picked on a dial, and dates read dd/MM/yyyy HH:mm.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// How a date-time is shown and typed: 31/10/2026 14:30.
final DateFormat kDateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

/// How a date is shown: 31/10/2026.
final DateFormat kDateFormat = DateFormat('dd/MM/yyyy');

/// [time] as HH:mm (24 h).
String formatTimeOfDay(TimeOfDay time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

/// Asks for a clock time, typed as HH:mm in 24-hour format.
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  TimeOfDay? initial,
  String helpText = 'Escriba la hora (HH:mm)',
}) {
  return showTimePicker(
    context: context,
    initialTime: initial ?? TimeOfDay.now(),
    initialEntryMode: TimePickerEntryMode.input,
    helpText: helpText,
    hourLabelText: 'Hora',
    minuteLabelText: 'Minuto',
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
}

/// Asks for a date and then its hour (typed, see [pickTime]).
Future<DateTime?> pickDateTime(
  BuildContext context, {
  DateTime? initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: firstDate ?? DateTime(2000),
    lastDate: lastDate ?? DateTime(2100),
  );
  if (date == null || !context.mounted) return null;
  final time = await pickTime(
    context,
    initial: initial == null ? null : TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// Parses a date-time typed or shown by the app: dd/MM/yyyy HH:mm, or the
/// ISO form (yyyy-MM-dd HH:mm) older screens wrote. Throws [FormatException]
/// if it is neither.
DateTime parseDateTimeInput(String text) {
  final t = text.trim();
  try {
    return kDateTimeFormat.parseStrict(t);
  } on FormatException {
    return DateTime.parse(t);
  }
}
