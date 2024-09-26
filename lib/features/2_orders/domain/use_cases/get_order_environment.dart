import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/2_orders/domain/entities/environment_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';

class GetOrderEnvironment implements UseCase<EnvironmentEntity, int>{

  final OrderRepository orderRepo;
  final MachineRepository machineRepo;

  GetOrderEnvironment(this.orderRepo, this.machineRepo);

  @override
  //being p the orders id
  Future<Either<Failure, EnvironmentEntity>> call({required int p}) async {
    final response = await orderRepo.getFullOrder(p);
    Failure? fail = null;
    OrderEntity? order = null;
    response.fold((f)=> fail = f, (s) => order = s);
    if( fail != null) return Left(fail!);

    //
    //LOGIC OF CHECKING TWHAT WOULD BE THE ORDER'S ENVIRONMENT
    //


    //BY NOW I JUST WRITE IT
    return orderRepo.getEnvironmentByName('SINGLE MACHINE');

  }

}