import 'package:production_planning/entities/machine_entity.dart';

/// Stores the standard times configured for a machine type.
class MachineStandardTimes {
  static const Duration _defaultUnit = Duration(hours: 1);

  final Duration processing;
  final Duration? preparation;
  final Duration? rest;

  const MachineStandardTimes({
    required this.processing,
    this.preparation,
    this.rest,
  });

  /// Returns a default configuration that mimics the previous behaviour
  /// where one hour was considered the base time for every station.
  factory MachineStandardTimes.defaults() =>
      const MachineStandardTimes(processing: _defaultUnit);

  /// Creates a configuration starting from the values of a [MachineEntity].
  factory MachineStandardTimes.fromMachine(
    MachineEntity machine, {
    MachineStandardTimes? fallback,
  }) {
    final base = fallback ?? MachineStandardTimes.defaults();
    return MachineStandardTimes(
      processing: machine.processingTime,
      preparation: machine.preparationTime ?? base.preparation,
      rest: machine.restTime ?? base.rest,
    );
  }

  MachineStandardTimes copyWith({
    Duration? processing,
    Duration? preparation,
    Duration? rest,
  }) {
    return MachineStandardTimes(
      processing: processing ?? this.processing,
      preparation: preparation ?? this.preparation,
      rest: rest ?? this.rest,
    );
  }

  Duration get preparationOrDefault => preparation ?? _defaultUnit;

  Duration get restOrDefault => rest ?? _defaultUnit;
}
