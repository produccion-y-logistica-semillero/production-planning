import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_task_entity.dart';

class ScheduleOrderUseCase implements UseCase<List<PlanningMachineEntity>, Tuple3<int, int, int>>{

  @override
  Future<Either<Failure, List<PlanningMachineEntity>>> call({required Tuple3<int, int, int> p}) async{  //tuple < orderid, ruleid, envId>
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
        return Right([
                machine1,
                machine2,
                machine3,
                machine4,
              ]);
  }
}