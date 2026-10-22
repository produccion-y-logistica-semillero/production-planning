import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';

abstract class MetricsState {}

class MetricsInitialState extends MetricsState {}

class MetricsLoadingState extends MetricsState {}

class MetricsLoadedState extends MetricsState {
  final List<Metrics> metrics;
  final List<String> ruleNames;
  final List<List<PlanningMachineEntity>> schedules;

  /// Id de cada regla (value1 de EnvironmentEntity.rules), alineado con
  /// [metrics]. Evita depender de que el índice de la tabla coincida con el
  /// de la lista de reglas si alguna regla falló.
  final List<int> ruleIds;

  MetricsLoadedState(
    this.metrics,
    this.ruleNames, {
    this.schedules = const [],
    this.ruleIds = const [],
  });
}

class MetricsErrorState extends MetricsState {
  final String message;
  MetricsErrorState(this.message);
}
