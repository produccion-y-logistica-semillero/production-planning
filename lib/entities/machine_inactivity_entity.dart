import 'package:flutter/material.dart';

enum Weekday { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

extension WeekdayLabels on Weekday {
  String get shortLabel {
    switch (this) {
      case Weekday.monday:
        return 'L';
      case Weekday.tuesday:
        return 'M';
      case Weekday.wednesday:
        return 'X';
      case Weekday.thursday:
        return 'J';
      case Weekday.friday:
        return 'V';
      case Weekday.saturday:
        return 'S';
      case Weekday.sunday:
        return 'D';
    }
  }

  String get fullLabel {
    switch (this) {
      case Weekday.monday:
        return 'Lunes';
      case Weekday.tuesday:
        return 'Martes';
      case Weekday.wednesday:
        return 'Miércoles';
      case Weekday.thursday:
        return 'Jueves';
      case Weekday.friday:
        return 'Viernes';
      case Weekday.saturday:
        return 'Sábado';
      case Weekday.sunday:
        return 'Domingo';
    }
  }
}

class MachineInactivityEntity {
  final int? id;
  final int machineId;
  final String name;
  final Set<Weekday> weekdays;
  final Duration startTime;
  final Duration duration;

  const MachineInactivityEntity({
    this.id,
    required this.machineId,
    required this.name,
    required this.weekdays,
    required this.startTime,
    required this.duration,
  });

  MachineInactivityEntity copyWith({
    int? id,
    int? machineId,
    String? name,
    Set<Weekday>? weekdays,
    Duration? startTime,
    Duration? duration,
  }) {
    return MachineInactivityEntity(
      id: id ?? this.id,
      machineId: machineId ?? this.machineId,
      name: name ?? this.name,
      weekdays: weekdays ?? this.weekdays,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
    );
  }

  Map<String, dynamic> toDatabaseMap() {
    final base = _durationToText(startTime);
    return {
      'machine_id': machineId,
      'name': name,
      'start_time': base,
      'duration_minutes': duration.inMinutes,
      'monday': weekdays.contains(Weekday.monday) ? 1 : 0,
      'tuesday': weekdays.contains(Weekday.tuesday) ? 1 : 0,
      'wednesday': weekdays.contains(Weekday.wednesday) ? 1 : 0,
      'thursday': weekdays.contains(Weekday.thursday) ? 1 : 0,
      'friday': weekdays.contains(Weekday.friday) ? 1 : 0,
      'saturday': weekdays.contains(Weekday.saturday) ? 1 : 0,
      'sunday': weekdays.contains(Weekday.sunday) ? 1 : 0,
    };
  }

  static MachineInactivityEntity fromDatabaseMap(Map<String, dynamic> map) {
    return MachineInactivityEntity(
      id: map['inactivity_id'] as int?,
      machineId: map['machine_id'] as int,
      name: map['name'] as String,
      startTime: _textToDuration(map['start_time'] as String),
      duration: Duration(minutes: map['duration_minutes'] as int),
      weekdays: Weekday.values
          .where((day) => _dayIsEnabled(day, map))
          .toSet(),
    );
  }

  static bool _dayIsEnabled(Weekday day, Map<String, dynamic> map) {
    final key = switch (day) {
      Weekday.monday => 'monday',
      Weekday.tuesday => 'tuesday',
      Weekday.wednesday => 'wednesday',
      Weekday.thursday => 'thursday',
      Weekday.friday => 'friday',
      Weekday.saturday => 'saturday',
      Weekday.sunday => 'sunday',
    };
    final value = map[key];
    if (value is int) return value != 0;
    if (value is bool) return value;
    return value?.toString() == '1';
  }

  static String _durationToText(Duration duration) {
    final hours = duration.inHours.remainder(24).toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  static Duration _textToDuration(String value) {
    final time = value.split(':');
    if (time.length < 2) {
      return const Duration();
    }
    final hours = int.tryParse(time[0]) ?? 0;
    final minutes = int.tryParse(time[1]) ?? 0;
    return Duration(hours: hours, minutes: minutes);
  }

  String formattedStartTime() {
    final hours = startTime.inHours.remainder(24).toString().padLeft(2, '0');
    final minutes = startTime.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  TimeOfDay get startTimeOfDay =>
      TimeOfDay(hour: startTime.inHours.remainder(24), minute: startTime.inMinutes.remainder(60));
}
