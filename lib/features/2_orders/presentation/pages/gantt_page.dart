import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/domain/entities/environment_entity.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_state.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/gantt_chart.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class GanttPage extends StatelessWidget {
  const GanttPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    PlanningMachineEntity machine1 = PlanningMachineEntity(1, 'Horno');
    PlanningMachineEntity machine2 = PlanningMachineEntity(2, 'Estufa');
    PlanningMachineEntity machine3 = PlanningMachineEntity(3, 'Liquadora');
    PlanningMachineEntity machine4 = PlanningMachineEntity(4, 'Nevera');

    //adding 1 unit of sequence galleta
    machine1.tasks.add(PlanningTaskEntity(
        sequenceId: 1,
        sequenceName: 'Galleta',
        taskId: 1,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 8),
        endDate: DateTime(2023, 9, 1, 17)));
    machine2.tasks.add(PlanningTaskEntity(
        sequenceId: 1,
        sequenceName: 'Galleta',
        taskId: 2,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 17),
        endDate: DateTime(2023, 9, 1, 22)));
    machine3.tasks.add(PlanningTaskEntity(
        sequenceId: 1,
        sequenceName: 'Galleta',
        taskId: 3,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 22),
        endDate: DateTime(2023, 9, 2, 10)));

    //adding 1 unit of sequence Pan
    machine4.tasks.add(PlanningTaskEntity(
        sequenceId: 2,
        sequenceName: 'Pan',
        taskId: 1,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 8),
        endDate: DateTime(2023, 9, 2, 13)));
    machine1.tasks.add(PlanningTaskEntity(
        sequenceId: 2,
        sequenceName: 'Pan',
        taskId: 2,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 13),
        endDate: DateTime(2023, 9, 2, 16)));
    machine2.tasks.add(PlanningTaskEntity(
        sequenceId: 2,
        sequenceName: 'Pan',
        taskId: 3,
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 16),
        endDate: DateTime(2023, 9, 2, 21)));

    return Scaffold(
      appBar: getAppBar(),
      body: BlocBuilder<GanttBloc, GanttState>(
        builder: (context, state) {
          if(state is GanttOrderRetrieveError){
            return Text("Hubo un error encontrando la orden");
          }
          if(state.orderId == null){
            return Text("Loading");
          }


          if(state is GanttOrderRetrieved){
            DropdownButton<int>(
              value: null,
              hint: Text('Selecciona una opción'),
              icon: Icon(Icons.arrow_downward),
              iconSize: 24,
              elevation: 16,
              style: TextStyle(color: Colors.deepPurple),
              underline: Container(
                height: 2,
                color: Colors.deepPurpleAccent,
              ),
              onChanged: (int? id) {
                if(id != null) BlocProvider.of<GanttBloc>(context).add(SelectRule(id));
              },
              items: state.enviroment!.rules.map((value) => DropdownMenuItem(
                  value: value.value1,
                  child: Text(value.value2),
                )
              ).toList(),
            );
          }

          return Column(children: [
            GanttChart(
              machines: [
                machine1,
                machine2,
                machine3,
                machine4,
              ],
            ),
          ]);
        },
      ),
    );
  }
}
