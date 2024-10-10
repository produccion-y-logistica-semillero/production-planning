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
    Failure? fail;
    late OrderEntity order;
    response.fold(
      (failure)=> fail = failure,
      (success) => order = success,
    );
    if(fail != null) return Left(fail!);

    //this stores some kind of matrix of the machine types id's of each job
    final List<List<int>> machineTypesId = order.orderJobs!
      .map(
        (job)=> job.sequence!.tasks!.map(
          (task)=> task.machineTypeId
        ).toList()
      ).toList();
    
    bool differentMachine = false;
    int max = 0;
    for (var row in machineTypesId) {
      print('dist: ${row.length}');
      if(row.length > max) max = row.length;
    }
    List<int> commonMachinesId = [];
    //we will iterate over the max lenght of machines of 1 job found
    for(int i = 0; i < max; i++){
      //for each iteration, we will iterate over all the jobs, to check if this 
      //positions (in sequence) machineId is the same for all of them
      for(final row in machineTypesId){
        //if the lenght of the row is lower than the index, then just with this we know that not all the jobs share the machines
        if(row.length >= i+1){

          if(commonMachinesId.length <= i){
            //if we are the first ones of this index, we add the new item with our machine id
            commonMachinesId.add(row[i]);
          }
          else{
            //if there's already a machine in this position, we check if we have the same one, if not, then we don't share machines, therefore job shop
            if(row[i] != commonMachinesId[i]){
              differentMachine = true;
              break;
            }
          }
        }else{
          differentMachine = true;
          break;
        }
      }
      if(differentMachine) break;
    }

    bool allOne = true;
    for(final row in machineTypesId){
      for(final machineType in row){
        final response = await machineRepo.countMachinesOf(machineType);
        response.fold((f) => allOne = false, (number){if(number != 1) allOne = false;});
      }
    }

    String enviroment;


    if(differentMachine && !allOne) enviroment = 'FLEXIBLE JOB SHOP';
    else if(differentMachine && allOne) enviroment = 'JOB SHOP';
    else if(!differentMachine && max > 1 && !allOne) enviroment = 'FLEXIBLE FLOW SHOP';
    else if(!differentMachine && max > 1 && allOne) enviroment = 'FLOW SHOP';
    else if(!differentMachine && max == 1 && !allOne) enviroment = 'PARALLEL MACHINES';
    else enviroment = 'SINGLE MACHINE';

    return orderRepo.getEnvironmentByName(enviroment);
  }

}