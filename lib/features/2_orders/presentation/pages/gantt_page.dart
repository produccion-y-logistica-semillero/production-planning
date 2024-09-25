import 'package:flutter/material.dart';
import 'package:production_planning/features/2_orders/presentation/dtos/gantt_machine_dto.dart';
import 'package:production_planning/features/2_orders/presentation/dtos/gantt_task_dto.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/gantt_chart.dart';
import 'package:production_planning/shared/widgets/custom_app_bar.dart';

class GanttPage extends StatelessWidget {
  const GanttPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {

    GanttMachineDTO machine1 = GanttMachineDTO(1, 'Horno');
    GanttMachineDTO machine2 = GanttMachineDTO(2, 'Estufa');
    GanttMachineDTO machine3 = GanttMachineDTO(3, 'Liquadora');
    GanttMachineDTO machine4 = GanttMachineDTO(4, 'Nevera');
    
    //adding 1 unit of sequence galleta
    machine1.tasks.add(
      GanttTaskDTO(
        sequenceId: 1, 
        sequenceName: 'Galleta', 
        taskId: 1, 
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 8), 
        endDate: DateTime(2023, 9, 1, 17)
      )
    );
    machine2.tasks.add(
      GanttTaskDTO(
        sequenceId: 1, 
        sequenceName: 'Galleta', 
        taskId: 2, 
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 17), 
        endDate: DateTime(2023, 9, 1, 22)
      )
    );
    machine3.tasks.add(
      GanttTaskDTO(
        sequenceId: 1, 
        sequenceName: 'Galleta', 
        taskId: 3, 
        numberProcess: 1,
        startDate: DateTime(2023, 9, 1, 22), 
        endDate: DateTime(2023, 9, 2, 10)
      )
    );


    //adding 1 unit of sequence Pan
    machine4.tasks.add(
      GanttTaskDTO(
        sequenceId: 2, 
        sequenceName: 'Pan', 
        taskId: 1, 
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 8), 
        endDate: DateTime(2023, 9, 2, 13)
      )
    );
    machine1.tasks.add(
      GanttTaskDTO(
        sequenceId: 2, 
        sequenceName: 'Pan', 
        taskId: 2, 
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 13), 
        endDate: DateTime(2023, 9, 2, 16)
      )
    );
    machine2.tasks.add(
      GanttTaskDTO(
        sequenceId: 2, 
        sequenceName: 'Pan', 
        taskId: 3, 
        numberProcess: 1,
        startDate: DateTime(2023, 9, 2, 16), 
        endDate: DateTime(2023, 9, 2, 21)
      )
    );


    return Scaffold(
      appBar: getAppBar(),
      body: Column(
        children: [
          GanttChart(
            machines: [
              machine1,
              machine2,
              machine3,
              machine4,
            ],
          ),
        ]
      ),
    );
  }
}