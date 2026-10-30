// lib/shared/duration_input.dart
//
// One way to type and show every duration the user enters (processing time,
// setup matrix, continuous use, rest, maintenance), in the format chosen in
// the "Formato de tiempos" setting: all in hh:mm:ss or all in minutes.
//
// Storage does not change: durations are still saved in whole minutes, so
// seconds typed in hh:mm:ss are rounded to the nearest minute.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum TimeInputFormat { hms, minutes }

/// Current format for every duration field. Read at start-up from
/// [timeFormatFileName] (main.dart) and changed from the side menu.
final ValueNotifier<TimeInputFormat> timeInputFormat =
    ValueNotifier(TimeInputFormat.minutes);

/// File in the app-support folder that persists the setting.
const String timeFormatFileName = 'time_format.txt';

String timeFormatToStorage(TimeInputFormat f) =>
    f == TimeInputFormat.hms ? 'hms' : 'min';

TimeInputFormat timeFormatFromStorage(String? text) =>
    text?.trim() == 'hms' ? TimeInputFormat.hms : TimeInputFormat.minutes;

String timeFormatLabel(TimeInputFormat f) =>
    f == TimeInputFormat.hms ? 'hh:mm:ss' : 'minutos';

/// Minutes in [text], or null if it is empty or not a valid duration.
///
/// Accepted in either format: a plain number of minutes ("90"), "hh:mm"
/// ("1:30") or "hh:mm:ss" ("01:30:20"). Seconds are rounded to the nearest
/// minute because durations are stored in whole minutes.
int? parseDurationMinutes(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (!t.contains(':')) {
    final m = int.tryParse(t);
    return (m == null || m < 0) ? null : m;
  }
  final parts = t.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final values = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p.trim());
    if (v == null || v < 0) return null;
    values.add(v);
  }
  final hours = values[0];
  final minutes = values[1];
  final seconds = values.length == 3 ? values[2] : 0;
  if (minutes > 59 || seconds > 59) return null;
  final totalSeconds = hours * 3600 + minutes * 60 + seconds;
  return (totalSeconds + 30) ~/ 60;
}

/// [minutes] written in format [f]: "01:30:00" or "90".
String formatDurationMinutes(int minutes, [TimeInputFormat? f]) {
  final format = f ?? timeInputFormat.value;
  if (format == TimeInputFormat.minutes) return '$minutes';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:00';
}

/// Short hint shown in the field.
String durationHint([TimeInputFormat? f]) =>
    (f ?? timeInputFormat.value) == TimeInputFormat.hms ? 'hh:mm:ss' : 'minutos';

/// hh:mm:ss mask: the user types only digits and the colons appear by
/// themselves after the hours and the minutes ("013000" → "01:30:00").
/// Up to 6 digits (99:59:59).
class HmsMaskFormatter extends TextInputFormatter {
  const HmsMaskFormatter();

  static String mask(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 6; i++) {
      if (i == 2 || i == 4) buffer.write(':');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final masked = mask(newValue.text);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

/// Input each format accepts while typing: a self-filling hh:mm:ss mask, or
/// whole minutes.
List<TextInputFormatter> durationInputFormatters([TimeInputFormat? f]) =>
    (f ?? timeInputFormat.value) == TimeInputFormat.hms
        ? const [HmsMaskFormatter()]
        : [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ];

/// Validator for a duration field: an error message, or null if valid.
String? validateDuration(
  String? text, {
  bool required = true,
  bool allowZero = true,
}) {
  final t = text?.trim() ?? '';
  if (t.isEmpty) return required ? 'Ingrese una duración' : null;
  final m = parseDurationMinutes(t);
  if (m == null) {
    return timeInputFormat.value == TimeInputFormat.hms
        ? 'Use hh:mm:ss (minutos y segundos menores a 60)'
        : 'Use un número entero de minutos';
  }
  if (!allowZero && m == 0) return 'Debe ser mayor que cero';
  return null;
}

/// A text field for a duration in the configured format. Its text is read
/// back with [parseDurationMinutes].
class DurationField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required;
  final bool allowZero;
  final bool enabled;
  final bool dense;
  final ValueChanged<String>? onChanged;
  final InputDecoration? decoration;

  const DurationField({
    super.key,
    required this.controller,
    required this.label,
    this.required = true,
    this.allowZero = true,
    this.enabled = true,
    this.dense = false,
    this.onChanged,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    final f = timeInputFormat.value;
    final base =
        decoration ?? const InputDecoration(border: OutlineInputBorder());
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: durationInputFormatters(f),
      decoration: base.copyWith(
        labelText: label.isEmpty ? null : '$label (${timeFormatLabel(f)})',
        hintText: durationHint(f),
        isDense: dense,
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) =>
          validateDuration(v, required: required, allowZero: allowZero),
      onChanged: onChanged,
    );
  }
}
