import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/task_dependency_dao.dart';
import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/presentation/2_orders/request_models/new_order_request_model.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/flexible_flow_shop_adapter.dart';
import 'package:production_planning/services/adapters/flexible_job_shop_adapter.dart';
import 'package:production_planning/services/adapters/flow_shop_Adapter.dart';
import 'package:production_planning/services/adapters/parallel_machine_adapter.dart';
import 'package:production_planning/services/adapters/single_machine_adapter.dart';


class OrdersService {
  final OrderRepository orderRepo;
  final MachineRepository machineRepo;

  OrdersService(this.orderRepo, this.machineRepo);

  Future<Either<Failure, bool>> addOrder(List<NewOrderRequestModel> model) async {
    // new order list become job entity list
    final List<JobEntity> jobs = model
        .map((jobModel) => JobEntity(
            null,
            SequenceEntity(jobModel.sequenceId, null, "",/*--*/ null),
            jobModel.amount,
            jobModel.dueDate,
            jobModel.priority,
            jobModel.availableDate)
          )
        .toList();

    print("Creando orden con los siguientes jobs:");
    for (final job in jobs) {
      print("Job: ${job.jobId}, SequenceId: ${job.sequence?.id}");
    }

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
    (failure) => fail = failure,
    (success) => order = success,
  );
  if (fail != null) return Left(fail!);

  print("Analizando orden ${order.orderId}");
  for (final job in order.orderJobs ?? []) {
    print("Job ${job.jobId} - Secuencia ${job.sequence?.id}:");
    final deps = job.sequence?.dependencies;
    if (deps == null || deps.isEmpty) {
      print("  Sin dependencias");
    } else {
      for (final dep in deps) {
        print("  Dependencia: ${dep.predecessor_id} -> ${dep.successor_id}");
      }
    }
  }

  // Validación básica
  if (order.orderJobs == null || order.orderJobs!.isEmpty) {
    print("La orden no tiene trabajos asociados");
  }
  if (order.orderJobs!.any((job) => job.sequence == null || job.sequence!.tasks == null || job.sequence!.tasks!.isEmpty)) {
    print("Al menos un trabajo no tiene tareas asociadas");

  }

  // Matriz de tipos de máquina por job
  final List<List<int>> machineTypesId = order.orderJobs!
      .map((job) => job.sequence!.tasks!.map((task) => task.machineTypeId).toList())
      .toList();

  bool differentMachine = false;
  int max = 0;
  for (var row in machineTypesId) {
    if (row.length > max) max = row.length;
  }
  List<int> commonMachinesId = [];
  for (int i = 0; i < max; i++) {
    for (final row in machineTypesId) {
      if (row.length >= i + 1) {
        if (commonMachinesId.length <= i) {
          commonMachinesId.add(row[i]);
        } else {
          if (row[i] != commonMachinesId[i]) {
            differentMachine = true;
            break;
          }
        }
      } else {
        differentMachine = true;
        break;
      }
    }
    if (differentMachine) break;
  }

  bool allOne = true;
  for (final row in machineTypesId) {
    for (final machineType in row) {
      final response = await machineRepo.countMachinesOf(machineType);
      response.fold((f) => allOne = false, (number) {
        if (number != 1) allOne = false;
      });
    }
  }

  bool hasPrecedence = false;
  for (var job in order.orderJobs!) {
    final dependencies = job.sequence?.dependencies ?? [];
    final taskIds = job.sequence?.tasks?.map((t) => t.id).toSet() ?? {};

    for (final dep in dependencies) {
      
      if (dep.predecessor_id != null &&
          dep.successor_id != null &&
          dep.predecessor_id != dep.successor_id &&
          taskIds.contains(dep.predecessor_id) &&
          taskIds.contains(dep.successor_id)) {
        hasPrecedence = true;
        print("Precedencia detectada: ${dep.predecessor_id} -> ${dep.successor_id}");
        break;
      }
    }

    if (hasPrecedence) break;
  }



  //Detectar Open Shop: más de un job, cada job con más de una tarea, y SIN precedencia
  bool isOpenShop = !hasPrecedence &&
      order.orderJobs!.length > 1 &&
      
      order.orderJobs!.every((job) => job.sequence != null && job.sequence!.tasks != null && job.sequence!.tasks!.length > 1);
  //Detectar Single Machine y Parallel Machines
  bool isSingleMachine = !differentMachine && max == 1 && allOne;
  bool isParallelMachines = !differentMachine && max == 1 && !allOne;

  //Detectar Flow Shop y Flexible Flow Shop (no requieren precedencias explícitas)
  bool isFlowShop = !differentMachine && max > 1 && allOne && hasPrecedence;
  bool isFlexibleFlowShop = !differentMachine && max > 1 && !allOne && hasPrecedence;

  // Detectar Job Shop y Flexible Job Shop (requieren precedencias)
  bool isJobShop = differentMachine && allOne && hasPrecedence;
  bool isFlexibleJobShop = differentMachine && !allOne && hasPrecedence;

  String enviroment;

  if (isOpenShop) {
    enviroment = 'OPEN SHOP';
  } else if (isJobShop) {
    enviroment = 'JOB SHOP';
  } else if (isFlexibleJobShop) {
    enviroment = 'FLEXIBLE JOB SHOP';
  } else if (isFlowShop) {
    enviroment = 'FLOW SHOP';
  } else if (isFlexibleFlowShop) {
    enviroment = 'FLEXIBLE FLOW SHOP';
  } else if (isSingleMachine) {
    enviroment = 'SINGLE MACHINE';
  } else if (isParallelMachines) {
    enviroment = 'PARALLEL MACHINES';
  } else {
    enviroment = 'OPEN SHOP'; // fallback
  }

  print('Ambiente detectado: $enviroment');
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