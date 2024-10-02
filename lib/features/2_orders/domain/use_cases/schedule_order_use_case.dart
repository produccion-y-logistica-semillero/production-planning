import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/2_orders/domain/entities/planning_machine_entity.dart';

class ScheduleOrderUseCase implements UseCase<List<PlanningMachineEntity>, Tuple3<int, int, int>>{

  @override
  Future<Either<Failure, List<PlanningMachineEntity>>> call({required Tuple3<int, int, int> p}) {  //tuple < orderid, ruleid, envId>
    // TODO: implement call
    throw UnimplementedError();
  }
}