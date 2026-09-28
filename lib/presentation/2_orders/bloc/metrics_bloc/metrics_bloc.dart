import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/presentation/2_orders/bloc/metrics_bloc/metrics_state.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/entities/tabu_params.dart';


class MetricsBloc extends Cubit<MetricsState> {
  final OrdersService service;

  MetricsBloc(this.service) : super(MetricsInitialState());

  void getTable(int id, {TabuParams? tabuParams}) async {
    emit(MetricsLoadingState());

    final response = await service.getOrderEnvironment(id);

    if (response.isLeft()) {
      emit(MetricsErrorState('Error al cargar métricas'));
      return;
    }

    final environment = response.getOrElse(() => throw Exception());

    final List<Metrics> metrics = [];
    final List<String> ruleNames = [];

    for (final ev in environment.rules) {
      final ruleName = ev.value1.toString();
      final ruleValue = ev.value2;

      final resp = await service.scheduleOrder(Tuple3(id, ruleValue, environment.name),tabuParams: tabuParams);


      if (resp.isRight()) {
        final result = resp.getOrElse(() => null);
        if (result != null) {
          metrics.add(result.value2);
          ruleNames.add(ruleName);
        }
      }
    }
    emit(MetricsLoadedState(metrics, ruleNames));
  }
}
