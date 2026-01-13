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
    // Calculate duration from percentage (100% = 1 hour base)
    return MachineStandardTimes(
      processing:
          Duration(minutes: (60 * machine.processingPercentage / 100).round()),
      preparation:
          Duration(minutes: (60 * machine.preparationPercentage / 100).round()),
      rest: Duration(minutes: (60 * machine.restPercentage / 100).round()),
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
