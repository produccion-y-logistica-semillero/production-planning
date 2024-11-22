import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/low_order/task_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/low_order/task_states.dart';

class TaskDialog extends StatelessWidget{
  
  final PlanningTaskEntity task;

  TaskDialog({
    super.key,
    required this.task,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        child: BlocBuilder<TaskBloc, TaskState>(builder: (context, state) {
          if(state is TaskInitialState){
            BlocProvider.of<TaskBloc>(context).getTaskInfo(task.taskId);
          }
          return switch(state){
            TaskRetrievingState()=>Center(child: CircularProgressIndicator(),),
            TaskErrorState() => Center(child: Text("Hubo un error"),),
            TaskRetrievedState(order: final order )=> _printInfo(order),
            TaskState()=>SizedBox()
          };
        },),
      ),
    );
  }


  Widget _printInfo(OrderEntity order){
    return Column(
      children: [
        Text("Order ID: ${order.orderId!}"),
        Text("La orden esta compuesta por: \n ${
          order.orderJobs!.map((j)=>j.sequence!.name).reduce((p, c)=>p+ " " +c)
        }}"),
        Text("ID tarea: ${task.taskId}"),
        Text("Secuencia: ${task.sequenceName}"),
        Text("${task.startDate}  -  ${task.endDate}")
      ],
    );
  }
}