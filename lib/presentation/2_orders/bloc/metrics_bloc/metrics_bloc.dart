import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/presentation/2_orders/bloc/metrics_bloc/metrics_state.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/entities/algorithm_params.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';

class MetricsBloc extends Cubit<MetricsState> {
  final OrdersService service;

  MetricsBloc(this.service) : super(MetricsInitialState());

  /// Programa la orden con las reglas elegidas ([ruleIndexes], posiciones
  /// en environment.rules; null = todas) y, si el usuario definio una
  /// secuencia propia, tambien con ella. Cada fila guarda el nombre y el id
  /// de SU regla: si una regla falla, las demas no se desplazan.
  void getTable(int id,
      {List<int>? ruleIndexes,
      AlgorithmParams params = const AlgorithmParams()}) async {
    emit(MetricsLoadingState());

    final response = await service.getOrderEnvironment(id);

    if (response.isLeft()) {
      emit(MetricsErrorState('Error al cargar métricas'));
      return;
    }

    final environment = response.getOrElse(() => throw Exception());

    final List<Metrics> metrics = [];
    final List<String> ruleNames = [];
    final List<List<PlanningMachineEntity>> schedules = [];
    final List<int> ruleIds = [];

    final rules = <Tuple2<int, String>>[
      if (ruleIndexes == null)
        ...environment.rules
      else
        for (final i in ruleIndexes)
          if (i >= 0 && i < environment.rules.length) environment.rules[i],
      if (params.hasUserSequence)
        const Tuple2(kUserSequenceRuleId, kUserSequenceRule),
    ];

    for (final ev in rules) {
      final ruleName = ev.value2;
      final ruleValue = ev.value2;

      final resp = await service.scheduleOrder(
          Tuple3(id, ruleValue, environment.name),
          params: params);

      if (resp.isRight()) {
        final result = resp.getOrElse(() => null);
        if (result != null) {
          metrics.add(result.value2);
          ruleNames.add(ruleName);
          // Se conserva el horario que produjo estas métricas para que el
          // Gantt lo muestre tal cual, sin volver a planificar.
          schedules.add(result.value1);
          ruleIds.add(ev.value1);
        }
      }
    }
    emit(MetricsLoadedState(metrics, ruleNames,
        schedules: schedules, ruleIds: ruleIds));
  }
}
