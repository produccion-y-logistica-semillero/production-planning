import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/low_order/task_states.dart';

class TaskBloc extends Cubit<TaskState>{

  final OrderRepository repo;

  TaskBloc(this.repo): super(TaskInitialState());


  void getTaskInfo(int orderId) async{
    await Future.delayed(Duration.zero);

    final response = await repo.getFullOrder(orderId);

    emit(response.fold((_)=>TaskErrorState(), (o)=> TaskRetrievedState(o)));
  }
  
}