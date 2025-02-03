import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/get_order_environment.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/schedule_order_use_case.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_state.dart';

class GanttBloc extends Cubit<GanttState>{

 final  GetOrderEnvironment _getOrderEnvironment;
 final ScheduleOrderUseCase _scheduleOrderUseCase;

  GanttBloc(
    this._getOrderEnvironment,
    this._scheduleOrderUseCase,
  ):super(GanttInitialState(null, null, null));

  void assignOrderId(int id) async{
    final response = await _getOrderEnvironment(p: id);
    response.fold(
      (f)=> emit(GanttOrderRetrieveError(null, null, null))
      ,(env)=> emit(GanttOrderRetrieved(id, env, null)));
  }

  void selectRule(int id) async{
    emit(GanttPlanningLoading(state.orderId, state.enviroment, id));

    final response = await _scheduleOrderUseCase(
      p: Tuple3(
        state.orderId!, 
        state.enviroment!.rules.where((rule)=> rule.value1 == id).first.value2, 
        state.enviroment!.name
      )
    );
    response.fold((f)=>emit(GanttPlanningError(state.orderId, state.enviroment, state.selectedRule)), 
    (result)=> emit(GanttPlanningSuccess(state.orderId, state.enviroment, result!.value1, result.value2, state.selectedRule)));
  }
}