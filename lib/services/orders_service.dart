import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/machine_times.dart';
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
import 'package:production_planning/services/adapters/job_shop_adapter.dart';
import 'package:production_planning/services/adapters/flow_shop_Adapter.dart';
import 'package:production_planning/services/adapters/parallel_machine_adapter.dart';
import 'package:production_planning/services/adapters/single_machine_adapter.dart';
import 'package:production_planning/services/adapters/open_shop_adapter.dart';
import 'package:production_planning/services/environment_detection.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';

class OrdersService {
  final OrderRepository orderRepo;
  final MachineRepository machineRepo;

  OrdersService(this.orderRepo, this.machineRepo);

  /// Ensures every job gets a human-readable name, so downstream UI never
  /// has to fall back to displaying a raw numeric job ID.
  String _resolveJobName(String? jobName, int indexInOrder) {
    if (jobName != null && jobName.trim().isNotEmpty) return jobName;
    return 'Trabajo ${indexInOrder + 1}';
  }

  Future<Either<Failure, bool>> addOrder(List<NewOrderRequestModel> model,
      {Map<String, Map<String, Map<String, int>>>? setupTimeMatrix,
      Map<String, String>? machineInitialStates}) async {
    final List<JobEntity> jobs = model.asMap().entries.map((entry) {
      final jobModel = entry.value;
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
        _resolveJobName(jobModel.jobName, entry.key),
        jobModel.dueDate,
        jobModel.priority,
        jobModel.availableDate,
        preemptionMatrix: jobModel.preemptionMatrix,
        taskMachineTimes: taskMachineTimes,
        machineFinalStates: jobModel.machineFinalStates,
      );
    }).toList();

    for (var m in model) {
      print(
          'OrdersService.addOrder: sequence=${m.sequenceId} taskMachineTimesMinutes=${m.taskMachineTimesMinutes}');
    }

    final OrderEntity newOrder = OrderEntity(null, DateTime.now(), jobs,
        setupTimeMatrix: setupTimeMatrix,
        machineInitialStates: machineInitialStates);
    try {
      return await orderRepo.createOrder(newOrder);
    } catch (error, stack) {
      print('OrdersService.addOrder error: ${error.toString()}');
      print(stack.toString());
      return Left(LocalStorageFailure());
    }
  }

  Future<Either<Failure, bool>> deleteOrder(int id) async {
    return await orderRepo.deleteOrder(id);
  }

  Future<Either<Failure, bool>> updateOrder(
      int orderId, List<NewOrderRequestModel> model,
      {Map<String, Map<String, Map<String, int>>>? setupTimeMatrix,
      Map<String, String>? machineInitialStates}) async {
    final List<JobEntity> jobs = model.asMap().entries.map((entry) {
      final jobModel = entry.value;
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
        _resolveJobName(jobModel.jobName, entry.key),
        jobModel.dueDate,
        jobModel.priority,
        jobModel.availableDate,
        preemptionMatrix: jobModel.preemptionMatrix,
        taskMachineTimes: taskMachineTimes,
        machineFinalStates: jobModel.machineFinalStates,
      );
    }).toList();

    final OrderEntity updatedOrder = OrderEntity(orderId, DateTime.now(), jobs,
        setupTimeMatrix: setupTimeMatrix,
        machineInitialStates: machineInitialStates);
    try {
      return await orderRepo.updateOrder(updatedOrder);
    } catch (error, stack) {
      print('OrdersService.updateOrder error: ${error.toString()}');
      print(stack.toString());
      return Left(LocalStorageFailure());
    }
  }

  Future<Either<Failure, bool>> duplicateOrder(int orderId) async {
    final response = await orderRepo.getFullOrder(orderId);
    return response.fold(
      (failure) => Left(failure),
      (order) async {
        // Create a copy of the order with a new ID (null for insert)
        final newOrder =
            OrderEntity(null, DateTime.now(), order.orderJobs ?? []);
        return await orderRepo.createOrder(newOrder);
      },
    );
  }

  Future<Either<Failure, List<OrderEntity>>> getOrders() async {
    return orderRepo.getAllOrders();
  }

  /// The program with its jobs and each job's route.
  Future<Either<Failure, OrderEntity>> getFullOrder(int orderId) {
    return orderRepo.getFullOrder(orderId);
  }

  /// ═══════════════════════════════════════════════════════════════════════════
  /// DETECCIÓN DE AMBIENTE DE PROGRAMACIÓN DE PRODUCCIÓN
  /// ═══════════════════════════════════════════════════════════════════════════
  ///
  /// TEORÍA DE AMBIENTES:
  ///
  /// ┌─────────────────────────────────────────────────────────────────────────┐
  /// │ AMBIENTE         │ Máquinas por etapa │ Secuencia fija │ Jobs múltiples │
  /// ├─────────────────────────────────────────────────────────────────────────┤
  /// │ Single Machine   │ 1 etapa, 1 máq     │ N/A            │ Sí             │
  /// │ Parallel Mach.   │ 1 etapa, N máq     │ N/A            │ Sí             │
  /// │ Flow Shop        │ M etapas, 1 máq    │ Igual p/ todos │ Sí             │
  /// │ Flexible FS      │ M etapas, N máq    │ Igual p/ todos │ Sí             │
  /// │ Open Shop        │ M etapas, 1 máq    │ Libre          │ Sí             │
  /// │ Flexible OS      │ M etapas, N máq    │ Libre          │ Sí             │
  /// │ Job Shop         │ M etapas, 1 máq    │ Distinta c/job │ Sí             │
  /// │ Flexible JS      │ M etapas, N máq    │ Distinta c/job │ Sí             │
  /// │ Recurrente       │ Grafo, 1 máq/etapa │ Grafo (A,B→C)  │ Sí             │
  /// │ Flex. Recurrente │ Grafo, N máq/etapa │ Grafo (A,B→C)  │ Sí             │
  /// └─────────────────────────────────────────────────────────────────────────┘

// IMPORTANTE: POR DECISIÓN CONJUNTA, SI TENEMOS DISTINTOS JOBS CON DINSTINTAS SECUENCIAS Y UNA ES DE TIPO OPEN, PRIORIZAMOS EL TIPO OPEN
  Future<Either<Failure, EnvironmentEntity>> getOrderEnvironment(
      int orderId) async {
    //1. Obtener la orden
    final response = await orderRepo.getFullOrder(orderId);
    Failure? fail;
    late OrderEntity order;

    response.fold((failure) => fail = failure, (success) => order = success);
    if (fail != null) return Left(fail!);

    print("\n=== ANALIZANDO ORDEN ${order.orderId} ===");

    //2. Logging de dependencias (depuración)
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

    // 3. Validar que la orden tenga trabajos y tareas asociadas
    if (order.orderJobs == null || order.orderJobs!.isEmpty) {
      print("La orden no tiene trabajos asociados");
      return Left(LocalStorageFailure());
    }
    final emptyJob = order.orderJobs!.where((job) =>
        job.sequence == null ||
        job.sequence!.tasks == null ||
        job.sequence!.tasks!.isEmpty);
    if (emptyJob.isNotEmpty) {
      for (final job in emptyJob) {
        print("El job ${job.jobId} (secuencia ${job.sequence?.id}) no tiene "
            "tareas asociadas: la secuencia está vacía o no existe en la BD.");
      }
      return Left(LocalStorageFailure());
    }

    // 4. Rutas de los jobs y número de máquinas por estación.
    final routes = [
      for (final job in order.orderJobs!) JobRoute.fromSequence(job.sequence!),
    ];
    final Map<int, int> machineCountByType = {};
    for (final route in routes) {
      for (final task in route.tasks) {
        if (machineCountByType.containsKey(task.machineTypeId)) continue;
        final r = await machineRepo.countMachinesOf(task.machineTypeId);
        machineCountByType[task.machineTypeId] = r.fold((_) => 0, (n) => n);
      }
    }

    // 5. Clasificar (ver classifyOrderEnvironment en environment_detection.dart).
    //
    // Antes la clasificación vivía aquí y tenía cuatro fallas:
    //   * comparaba las rutas en el ORDEN DE LA LISTA de tareas (el orden en
    //     que se crearon los nodos en el editor), no en el de las flechas;
    //   * la clasificación "por job" usaba las banderas de toda la orden, así
    //     que la regla de prioridad OPEN entre jobs mezclados nunca actuaba;
    //   * las precedencias recurrentes salían como JOB SHOP / FLEXIBLE JOB
    //     SHOP, sin ambiente propio, y las bifurcaciones como Flow/Job Shop;
    //   * jobs sin precedencias con tareas en distinto orden de lista caían
    //     en OPEN SHOP aunque hubiera máquinas paralelas.
    for (int i = 0; i < routes.length; i++) {
      print("  Job ${order.orderJobs![i].jobId}: ruta ${routeShape(routes[i]).name}");
    }
    final String enviroment;
    try {
      enviroment = classifyOrderEnvironment(routes, machineCountByType);
    } on StationWithoutMachinesException catch (e) {
      print("DEBUG: $e");
      return Left(LocalStorageFailure());
    }

    print("DEBUG: Ambiente detectado → $enviroment");

    // 14. Retornar el ambiente desde el repositorio
    return orderRepo.getEnvironmentByName(enviroment);
  }

  // ------------------------------------------------------------------------
  // --------------------------- SCHEDULER ----------------------------------
  // ------------------------------------------------------------------------

  Future<Either<Failure, Tuple2<List<PlanningMachineEntity>, Metrics>?>>
      scheduleOrder(Tuple3<int, String, String> sch) async {
    // The preemption engine refuses to search forever when a machine's
    // calendar admits no schedule (see SchedulingHorizonException). Turn
    // that into a Failure carrying the reason, so the user is told what to
    // fix instead of watching a spinner — or, in the five environments that
    // run on the UI isolate, a frozen app.
    try {
      return await _dispatchSchedule(sch);
    } on SchedulingHorizonException catch (e) {
      print('scheduleOrder: orden imposible de planificar → $e');
      return Left(UnschedulableOrderFailure(e.reason));
    }
  }

  Future<Either<Failure, Tuple2<List<PlanningMachineEntity>, Metrics>?>>
      _dispatchSchedule(Tuple3<int, String, String> sch) async {
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
      'FLEXIBLE JOB SHOP' || 'FLEXIBLE RECURRENTE' => await FlexibleJobShopAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo)
          .flexibleJobShopAdapter(sch.value1, sch.value2)
          .then((result) =>
              result == null ? Left(LocalStorageFailure()) : Right(result)),
      'JOB SHOP' || 'RECURRENTE' => await JobShopAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo)
          .jobShopAdapter(sch.value1, sch.value2)
          .then((result) =>
              result == null ? Left(LocalStorageFailure()) : Right(result)),
      'OPEN SHOP' || 'FLEXIBLE OPEN SHOP' => await OpenShopAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo)
          .openShopAdapter(sch.value1, sch.value2)
          .then((result) =>
              result == null ? Left(LocalStorageFailure()) : Right(result)),
      String() => Left(EnviromentNotCorrectFailure()),
    };
  }
}
