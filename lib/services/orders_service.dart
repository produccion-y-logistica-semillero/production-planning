import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/presentation/2_orders/request_models/new_order_request_model.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/flexible_flow_shop_adapter.dart';
import 'package:production_planning/services/adapters/flexible_job_shop_adapter.dart';
import 'package:production_planning/services/adapters/flow_shop_Adapter.dart';
import 'package:production_planning/services/adapters/parallel_machine_adapter.dart';
import 'package:production_planning/services/adapters/single_machine_adapter.dart';

import 'adapters/flexible_job_shop_adapter.dart';

class OrdersService {
  final OrderRepository orderRepo;
  final MachineRepository machineRepo;

  OrdersService(this.orderRepo, this.machineRepo);

  Future<Either<Failure, bool>> addOrder(List<NewOrderRequestModel> model) async {
    // new order list become job entity list
    final List<JobEntity> jobs = model
        .map((jobModel) => JobEntity(
            null,
            SequenceEntity(jobModel.sequenceId, null, ""),
            jobModel.amount,
            jobModel.dueDate,
            jobModel.priority,
            jobModel.availableDate)
          )
        .toList();

    // order entity.
    final OrderEntity newOrder = OrderEntity(null, DateTime.now(), jobs);

    // call repository to create order.
    return await orderRepo.createOrder(newOrder);
  }

  Future<Either<Failure, bool>> deleteOrder(int id) async{
    return await orderRepo.deleteOrder(id);
  }

  Future<Either<Failure, List<OrderEntity>>> getOrders() async {
    return orderRepo.getAllOrders();
  }

  Future<Either<Failure, EnvironmentEntity>> getOrderEnvironment(int orderId) async {
    final response = await orderRepo.getFullOrder(orderId);
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
    if(differentMachine && !allOne) {
      enviroment = 'FLEXIBLE JOB SHOP';
    } else if(differentMachine && allOne) enviroment = 'JOB SHOP';
    else if(!differentMachine && max > 1 && !allOne) enviroment = 'FLEXIBLE FLOW SHOP';
    else if(!differentMachine && max > 1 && allOne) enviroment = 'FLOW SHOP';
    else if(!differentMachine && max == 1 && !allOne) enviroment = 'PARALLEL MACHINES';
    else enviroment = 'SINGLE MACHINE';

    return orderRepo.getEnvironmentByName(enviroment);
  }


  Future<Either<Failure, Tuple2<List<PlanningMachineEntity>, Metrics>?>> scheduleOrder(Tuple3<int, String, String> sch) async{  //tuple < orderid, rule name, enviroment name>
    return switch(sch.value3){
      'SINGLE MACHINE' => Right(await SingleMachineAdapter(orderRepository: orderRepo, machineRepository: machineRepo).singleMachineAdapter(sch.value1, sch.value2)),
      'PARALLEL MACHINES' => Right(await ParallelMachineAdapter(machineRepository: machineRepo, orderRepository: orderRepo).parallelMachineAdapter(sch.value1, sch.value2)),
      'FLOW SHOP' => Right(await FlowShopAdapter(machineRepository: machineRepo, orderRepository: orderRepo).flowShopAdapter(sch.value1, sch.value2)),
      'FLEXIBLE FLOW SHOP' => Right(await FlexibleFlowShopAdapter(machineRepository: machineRepo, orderRepository: orderRepo).flexibleFlowShopAdapter(sch.value1, sch.value2)),
      'FLEXIBLE JOB SHOP' => Right(await FlexibleJobShopAdapter(machineRepository: machineRepo, orderRepository: orderRepo).flexibleJobShopAdapter(sch.value1, sch.value2)),
      String() => Left(EnviromentNotCorrectFailure()),

      
      
    };
  }


}