import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/task_dependency_dao.dart';
import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/machine_times.dart';
import 'package:production_planning/entities/metrics.dart';
import 'package:production_planning/entities/planning_machine_entity.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/presentation/2_orders/request_models/new_order_request_model.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';
import 'package:production_planning/services/adapters/flexible_flow_shop_adapter.dart';
import 'package:production_planning/services/adapters/flexible_job_shop_adapter.dart';
import 'package:production_planning/services/adapters/flow_shop_Adapter.dart';
import 'package:production_planning/services/adapters/parallel_machine_adapter.dart';
import 'package:production_planning/services/adapters/single_machine_adapter.dart';
import 'package:production_planning/services/adapters/open_shop_adapter.dart';
import 'package:production_planning/services/setup_time_service.dart';

class OrdersService {
  final OrderRepository orderRepo;
  final MachineRepository machineRepo;
  final SetupTimeService setupTimeService;

  OrdersService(this.orderRepo, this.machineRepo, this.setupTimeService);

  Future<Either<Failure, bool>> addOrder(
      List<NewOrderRequestModel> model) async {
    final List<JobEntity> jobs = model.map((jobModel) {
      Map<int, Map<int, MachineTimes>>? taskMachineTimes;
      if (jobModel.taskMachineTimesMinutes != null) {
        taskMachineTimes = {};
        jobModel.taskMachineTimesMinutes!.forEach((taskId, mm) {
          final inner = <int, MachineTimes>{};
          mm.forEach((machineId, timesMap) {
            inner[machineId] = MachineTimes(
              processing: Duration(minutes: timesMap['processing'] ?? 0),
              preparation: Duration(minutes: timesMap['preparation'] ?? 0),
              rest: Duration(minutes: timesMap['rest'] ?? 0),
            );
          });
          taskMachineTimes![taskId] = inner;
        });
      }

      return JobEntity(
        null,
        SequenceEntity(jobModel.sequenceId, null, "", null),
        jobModel.amount,
        jobModel.dueDate,
        jobModel.priority,
        jobModel.availableDate,
        preemptionMatrix: jobModel.preemptionMatrix,
        taskMachineTimes: taskMachineTimes,
      );
    }).toList();

    for (var m in model) {
      print(
          'OrdersService.addOrder: sequence=${m.sequenceId} taskMachineTimesMinutes=${m.taskMachineTimesMinutes}');
    }

    final OrderEntity newOrder = OrderEntity(null, DateTime.now(), jobs);
    return await orderRepo.createOrder(newOrder);
  }

  Future<Either<Failure, bool>> deleteOrder(int id) async {
    return await orderRepo.deleteOrder(id);
  }

  Future<Either<Failure, List<OrderEntity>>> getOrders() async {
    return orderRepo.getAllOrders();
  }

  // ------------------------------------------------------------------------
  // ------------------ AMBIENTE (FUSIONADO COMPLETO) ------------------------
  // ------------------------------------------------------------------------

  Future<Either<Failure, EnvironmentEntity>> getOrderEnvironment(
      int orderId) async {
    final response = await orderRepo.getFullOrder(orderId);
    Failure? fail;
    late OrderEntity order;

    response.fold((failure) => fail = failure, (success) => order = success);
    if (fail != null) return Left(fail!);

    print("\n=== ANALIZANDO ORDEN ${order.orderId} ===");

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

    if (order.orderJobs == null || order.orderJobs!.isEmpty) {
      print("La orden no tiene trabajos asociados");
      return Left(LocalStorageFailure());
    }
    if (order.orderJobs!.any((job) =>
        job.sequence == null ||
        job.sequence!.tasks == null ||
        job.sequence!.tasks!.isEmpty)) {
      print("Al menos un trabajo no tiene tareas asociadas");
      return Left(LocalStorageFailure());
    }

    final List<List<int>> machineTypesId = order.orderJobs!
        .map((job) =>
            job.sequence!.tasks!.map((task) => task.machineTypeId).toList())
        .toList();

    bool differentMachine = false;
    int max = 0;

    for (var row in machineTypesId) {
      if (row.length > max) max = row.length;
    }

    List<int> commonMachinesId = [];
    for (int i = 0; i < max; i++) {
      for (final row in machineTypesId) {
        if (row.length <= i) {
          differentMachine = true;
          break;
        }
        if (commonMachinesId.length <= i) {
          commonMachinesId.add(row[i]);
        } else {
          if (row[i] != commonMachinesId[i]) {
            differentMachine = true;
            break;
          }
        }
      }
      if (differentMachine) break;
    }

    bool allOne = true;
    for (final row in machineTypesId) {
      for (final machineType in row) {
        final r = await machineRepo.countMachinesOf(machineType);
        r.fold((_) => allOne = false, (n) {
          if (n != 1) allOne = false;
        });
      }
    }

    bool hasExplicitPrecedence = false;
    for (var job in order.orderJobs!) {
      final dependencies = job.sequence?.dependencies ?? [];
      final taskIds = job.sequence?.tasks?.map((t) => t.id).toSet() ?? {};

      for (final dep in dependencies) {
        if (dep.predecessor_id != null &&
            dep.successor_id != null &&
            dep.predecessor_id != dep.successor_id &&
            taskIds.contains(dep.predecessor_id) &&
            taskIds.contains(dep.successor_id)) {
          hasExplicitPrecedence = true;
          print(
              "Precedencia detectada: ${dep.predecessor_id} -> ${dep.successor_id}");
          break;
        }
      }
      if (hasExplicitPrecedence) break;
    }

    final bool hasPrecedence = hasExplicitPrecedence;

    bool isOpenShop = !hasExplicitPrecedence &&
        order.orderJobs!.length > 1 &&
        order.orderJobs!.every((job) =>
            job.sequence != null &&
            job.sequence!.tasks != null &&
            job.sequence!.tasks!.length > 1);

    bool isSingleMachine = !differentMachine && max == 1 && allOne;
    bool isParallelMachines = !differentMachine && max == 1 && !allOne;

    bool isFlowShop = !differentMachine && max > 1 && allOne && hasPrecedence;
    bool isFlexibleFlowShop =
        !differentMachine && max > 1 && !allOne && hasPrecedence;

    bool isJobShop = differentMachine && allOne && hasPrecedence;
    bool isFlexibleJobShop = differentMachine && !allOne && hasPrecedence;

    String enviroment;

    if (isOpenShop) {
      print("DEBUG: Detectado OPEN SHOP");
      enviroment = "OPEN SHOP";
    } else if (isJobShop) {
      enviroment = "JOB SHOP";
    } else if (isFlexibleJobShop) {
      enviroment = "FLEXIBLE JOB SHOP";
    } else if (isFlowShop) {
      enviroment = "FLOW SHOP";
    } else if (isFlexibleFlowShop) {
      enviroment = "FLEXIBLE FLOW SHOP";
    } else if (isSingleMachine) {
      enviroment = "SINGLE MACHINE";
    } else if (isParallelMachines) {
      enviroment = "PARALLEL MACHINES";
    } else {
      enviroment = "OPEN SHOP";
      print(
          "DEBUG: FALLBACK a OPEN SHOP - differentMachine=$differentMachine max=$max allOne=$allOne precedence=$hasPrecedence");
    }

    print("DEBUG: Ambiente detectado: $enviroment\n");
    return orderRepo.getEnvironmentByName(enviroment);
  }

  // ------------------------------------------------------------------------
  // --------------------------- SCHEDULER ----------------------------------
  // ------------------------------------------------------------------------

  Future<Either<Failure, Tuple2<List<PlanningMachineEntity>, Metrics>?>>
      scheduleOrder(Tuple3<int, String, String> sch) async {
    return switch (sch.value3) {
      'SINGLE MACHINE' => Right(await SingleMachineAdapter(
              orderRepository: orderRepo, machineRepository: machineRepo)
          .singleMachineAdapter(sch.value1, sch.value2)),

      'PARALLEL MACHINES' => Right(await ParallelMachineAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo)
          .parallelMachineAdapter(sch.value1, sch.value2)),

      'FLOW SHOP' => Right(await FlowShopAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo)
          .flowShopAdapter(sch.value1, sch.value2)),

      'FLEXIBLE FLOW SHOP' => Right(await FlexibleFlowShopAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo)
          .flexibleFlowShopAdapter(sch.value1, sch.value2)),

      'FLEXIBLE JOB SHOP' => Right(await FlexibleJobShopAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo)
          .flexibleJobShopAdapter(sch.value1, sch.value2)),

      'OPEN SHOP' => Right(await OpenShopAdapter(
              machineRepository: machineRepo,
              orderRepository: orderRepo,
              setupTimeService: setupTimeService)
          .openShopAdapter(sch.value1, sch.value2)),

      String() => Left(EnviromentNotCorrectFailure()),
    };
  }
}
