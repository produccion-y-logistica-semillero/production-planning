import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/services/orders_service.dart';

class GanttBloc extends Cubit<GanttState> {
  final OrdersService service;

  GanttBloc(
    this.service,
  ) : super(GanttInitialState(null, null, null));

  /// Asigna un orderId y obtiene el environment
  void assignOrderId(int id) async {
    try {
      final response = await service.getOrderEnvironment(id);
      response.fold(
        (failure) {
          emit(GanttOrderRetrieveError(id, null, null));
        },
        (env) {
          emit(GanttOrderRetrieved(id, env, null));
        },
      );
    } catch (e) {
      emit(GanttOrderRetrieveError(id, null, null));
    }
  }

  /// Selecciona una regla por su ID
  void selectRule(int ruleId) async {
    if (state.orderId == null || state.enviroment == null) {
      return;
    }

    try {
      emit(GanttPlanningLoading(state.orderId, state.enviroment, ruleId));

      // Buscar la regla por su ID
      final selectedRule = state.enviroment!.rules
          .where((rule) => rule.value1 == ruleId)
          .firstOrNull;

      if (selectedRule == null) {
        emit(GanttPlanningError(state.orderId, state.enviroment, ruleId));
        return;
      }

      final response = await service.scheduleOrder(Tuple3(
        state.orderId!,
        selectedRule.value2,
        state.enviroment!.name,
      ));

      response.fold(
        (failure) {
          emit(GanttPlanningError(state.orderId, state.enviroment, ruleId));
        },
        (result) {
          emit(GanttPlanningSuccess(
            state.orderId,
            state.enviroment,
            result!.value1,
            result.value2,
            ruleId,
          ));
        },
      );
    } catch (e) {
      emit(GanttPlanningError(state.orderId, state.enviroment, ruleId));
    }
  }

  /// Selecciona una regla por su índice en la lista de reglas
  void selectRuleByIndex(int index) {
    final env = state.enviroment;
    if (env == null) {
      return;
    }

    if (index < 0 || index >= env.rules.length) {
      return;
    }

    final ruleId = env.rules[index].value1;
    selectRule(ruleId);
  }

  /// Asigna una orden y selecciona una regla por índice en una sola operación
  Future<void> assignOrderAndSelectRuleByIndex(int orderId, int index) async {
    try {
      final response = await service.getOrderEnvironment(orderId);
      response.fold(
        (failure) {
          emit(GanttOrderRetrieveError(orderId, null, null));
        },
        (env) {
          emit(GanttOrderRetrieved(orderId, env, null));

          // Validar índice y seleccionar regla
          if (index >= 0 && index < env.rules.length) {
            final ruleId = env.rules[index].value1;
            selectRule(ruleId);
          }
        },
      );
    } catch (e) {
      emit(GanttOrderRetrieveError(orderId, null, null));
    }
  }

  /// Limpia el estado actual
  void clearState() {
    emit(GanttInitialState(null, null, null));
  }

  /// Reinicia el estado para una nueva orden
  void reset() {
    clearState();
  }
}
