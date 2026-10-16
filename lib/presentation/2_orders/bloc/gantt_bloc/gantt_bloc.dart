import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/entities/tabu_params.dart';

class GanttBloc extends Cubit<GanttState> {
  final OrdersService service;

  /// Parámetros de TABU con los que se entró a esta sesión del Gantt.
  /// El desplegable del Gantt llama a selectRule(id) sin parámetros; sin esto
  /// cada cambio de algoritmo volvía a los valores por defecto de TABU
  /// (4 s de presupuesto), y el horario dejaba de coincidir con la tabla.
  TabuParams? _tabuParams;

  GanttBloc(

      this.service,
      ) : super(GanttInitialState(null, null, null));


  /// Asigna un orderId y obtiene el environment
  void assignOrderId(int id) async {
    try {
      final response = await service.getOrderEnvironment(id);
      response.fold(
            (failure) {
          print("ERROR: No se pudo obtener el environment para la orden $id");
          emit(GanttOrderRetrieveError(id, null, null));
        },
            (env) {
          print("SUCCESS: Environment obtenido para orden $id: ${env.name}");
              print("DEBUG: Environment rules count=${env.rules.length} -> ${env.rules}");

          emit(GanttOrderRetrieved(id, env, null));
        },
      );
    } catch (e) {

      print("EXCEPTION en assignOrderId: $e");

      emit(GanttOrderRetrieveError(id, null, null));
    }
  }

  /// Selecciona una regla por su ID
  void selectRule(int ruleId ,{TabuParams? tabuParams}) async {
    if (state.orderId == null || state.enviroment == null) {
      print("ERROR: No se puede seleccionar regla sin orderId o environment");
      return;
    }

    // Si llegan parámetros se recuerdan; si no (p. ej. el desplegable del
    // Gantt) se reutilizan los de la entrada a esta sesión.
    if (tabuParams != null) _tabuParams = tabuParams;
    final TabuParams? effectiveTabuParams = tabuParams ?? _tabuParams;

    try {
      emit(GanttPlanningLoading(state.orderId, state.enviroment, ruleId));

      // Buscar la regla por su ID
      final selectedRule = state.enviroment!.rules
          .where((rule) => rule.value1 == ruleId)
          .firstOrNull;

      if (selectedRule == null) {
        print("ERROR: No se encontró regla con ID $ruleId");

        emit(GanttPlanningError(state.orderId, state.enviroment, ruleId));
        return;
      }

      final response = await service.scheduleOrder(Tuple3(
        state.orderId!,
        selectedRule.value2,
        state.enviroment!.name,
      ),
      tabuParams: effectiveTabuParams,);
      response.fold(
            (failure) {
          print("ERROR: Fallo en la planificación para regla $ruleId");
          emit(GanttPlanningError(
            state.orderId,
            state.enviroment,
            ruleId,
            // An unschedulable calendar is the user's to fix, so pass the
            // reason through instead of the generic message.
            message: failure is UnschedulableOrderFailure
                ? failure.reason
                : null,
          ));
        },
            (result) {
          if (result == null) {
            print("ERROR: scheduling returned null for regla $ruleId");
            emit(GanttPlanningError(state.orderId, state.enviroment, ruleId));
            return;
          }
          print("SUCCESS: Planificación exitosa para regla $ruleId");

          emit(GanttPlanningSuccess(
            state.orderId,
            state.enviroment,
            result.value1,
            result.value2,
            ruleId,
          ));
        },
      );
    } catch (e) {

      print("EXCEPTION en selectRule: $e");

      emit(GanttPlanningError(state.orderId, state.enviroment, ruleId));
    }
  }

  /// Selecciona una regla por su índice en la lista de reglas
  void selectRuleByIndex(int index) {
    final env = state.enviroment;
    if (env == null) {

      print("ERROR: No hay environment disponible");

      return;
    }

    if (index < 0 || index >= env.rules.length) {

      print("ERROR: Índice $index fuera de rango (0-${env.rules.length - 1})");

      return;
    }

    final ruleId = env.rules[index].value1;

    print("INFO: Seleccionando regla en índice $index con ID $ruleId");

    selectRule(ruleId);
  }

  /// Asigna una orden y selecciona una regla por índice en una sola operación
  Future<void> assignOrderAndSelectRuleByIndex(int orderId, int index,   {TabuParams? tabuParams}) async {
    try {
      _tabuParams = tabuParams; // la entrada fija los parámetros de esta sesión
      print("INFO: Asignando orden $orderId y seleccionando regla índice $index");

      final response = await service.getOrderEnvironment(orderId);
      response.fold(
            (failure) {
          print("ERROR: No se pudo obtener environment para orden $orderId");
          emit(GanttOrderRetrieveError(orderId, null, null));
        },
            (env) {
          print("SUCCESS: Environment obtenido, seleccionando regla índice $index");

          emit(GanttOrderRetrieved(orderId, env, null));

          // Validar índice y seleccionar regla
          if (index >= 0 && index < env.rules.length) {
            final ruleId = env.rules[index].value1;
            print("INFO: Regla encontrada con ID $ruleId");
            selectRule(ruleId,tabuParams: tabuParams,);
          } else {
            print("ERROR: Índice $index fuera de rango para ${env.rules.length} reglas");

          }
        },
      );
    } catch (e) {
      print("EXCEPTION en assignOrderAndSelectRuleByIndex: $e");

      emit(GanttOrderRetrieveError(orderId, null, null));
    }
  }

  /// Muestra un horario que YA se calculó (el de la tabla de métricas) sin
  /// volver a planificar. TABU para por reloj, así que planificar otra vez
  /// daría otro horario y el Gantt dejaría de coincidir con el número de la
  /// tabla. [ruleId] es el id de la regla (value1 de las reglas del entorno).
  Future<void> showSchedule(
    int orderId,
    int ruleId,
    List<PlanningMachineEntity> planningMachines,
    Metrics metrics, {
    TabuParams? tabuParams,
  }) async {
    // El desplegable del Gantt usará estos parámetros si se cambia de regla.
    _tabuParams = tabuParams;
    try {
      // Si ya hay entorno de esta orden se reutiliza; si no, se consulta.
      EnvironmentEntity? env = state.orderId == orderId ? state.enviroment : null;
      if (env == null) {
        final response = await service.getOrderEnvironment(orderId);
        env = response.fold((failure) => null, (e) => e);
      }
      if (env == null) {
        print("ERROR: No se pudo obtener environment para orden $orderId");
        emit(GanttOrderRetrieveError(orderId, null, null));
        return;
      }
      print("INFO: Mostrando horario ya calculado de la regla $ruleId (orden $orderId)");
      emit(GanttPlanningSuccess(orderId, env, planningMachines, metrics, ruleId));
    } catch (e) {
      print("EXCEPTION en showSchedule: $e");
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