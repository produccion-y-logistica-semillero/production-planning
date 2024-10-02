import 'package:dartz/dartz.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/get_order_environment.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/schedule_order_use_case.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_state.dart';

class GanttBloc extends Bloc<GanttEvent, GanttState>{

 final  GetOrderEnvironment _getOrderEnvironment;
 final ScheduleOrderUseCase _scheduleOrderUseCase;

  GanttBloc(
    this._getOrderEnvironment,
    this._scheduleOrderUseCase,
  ):super(GanttInitialState(null, null))
  {
    on<AssignOrderId>(
      (event, emit)async {
        final response = await _getOrderEnvironment(p: event.id);
        response.fold(
          (f)=> emit(GanttOrderRetrieveError(null, null))
          ,(env)=> emit(GanttOrderRetrieved(event.id, env)));
      }
    );

    on<SelectRule>((event, emit) async{
      emit(GanttPlanningLoading(state.orderId, state.enviroment));

      final response = await _scheduleOrderUseCase(p: Tuple3(state.orderId!, event.id, state.enviroment!.environmentId));

      response.fold((f)=>emit(GanttPlanningError(state.orderId, state.enviroment)), 
      (plan)=> emit(GanttPlanningSuccess(state.orderId, state.enviroment, plan)));
      
    },);
  }

}