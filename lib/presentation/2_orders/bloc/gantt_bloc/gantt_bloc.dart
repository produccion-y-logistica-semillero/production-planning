import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/services/orders_service.dart';

class GanttBloc extends Cubit<GanttState>{

  final OrdersService service;

  GanttBloc(
    this.service,
  ):super(GanttInitialState(null, null, null));

  void assignOrderId(int id) async{
    final response = await service.getOrderEnvironment(id);
    response.fold(
      (f)=> emit(GanttOrderRetrieveError(null, null, null))
      ,(env)=> emit(GanttOrderRetrieved(id, env, null)));
  }

  void selectRule(int id) async{
    emit(GanttPlanningLoading(state.orderId, state.enviroment, id));

    final response = await service.scheduleOrder(Tuple3(
        state.orderId!, 
        state.enviroment!.rules.where((rule)=> rule.value1 == id).first.value2, 
        state.enviroment!.name
      )
    );
    response.fold((f)=>emit(GanttPlanningError(state.orderId, state.enviroment, state.selectedRule)), 
    (result)=> emit(GanttPlanningSuccess(state.orderId, state.enviroment, result!.value1, result.value2, state.selectedRule)));
  }
}