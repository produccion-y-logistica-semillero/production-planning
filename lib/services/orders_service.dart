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
import 'package:production_planning/services/setup_time_service.dart';

class OrdersService {
  final OrderRepository orderRepo;
  final MachineRepository machineRepo;
  final SetupTimeService setupTimeService;

  OrdersService(this.orderRepo, this.machineRepo, this.setupTimeService);

  Future<Either<Failure, bool>> addOrder(List<NewOrderRequestModel> model,
      {Map<String, Map<String, Map<String, int>>>? setupTimeMatrix}) async {
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
        jobModel.jobName,
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
        setupTimeMatrix: setupTimeMatrix);
    try {
      return await orderRepo.createOrder(newOrder);
    } catch (error, stack) {
      print('OrdersService.addOrder error: ${error.toString()}');
      print(stack.toString());
      return Left(LocalStorageFailure());
    }
  }

  Future<Either<Failure, bool>> updateOrder(
      int orderId, List<NewOrderRequestModel> model) async {
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

    final OrderEntity updatedOrder = OrderEntity(orderId, DateTime.now(), jobs);
    return await orderRepo.updateOrder(updatedOrder);
  }

  Future<Either<Failure, bool>> duplicateOrder(int orderId) async {
    final result = await orderRepo.getFullOrder(orderId);
    return await result.fold(
      (failure) async => Left(failure),
      (order) async {
        final List<JobEntity> newJobs = order.orderJobs?.map((job) {
          return JobEntity(
            null,
            job.sequence,
            job.amount,
            job.dueDate,
            job.priority,
            job.availableDate,
            preemptionMatrix: job.preemptionMatrix,
            taskMachineTimes: job.taskMachineTimes,
          );
        }).toList() ?? [];

        final OrderEntity newOrder = OrderEntity(null, order.regDate, newJobs);
        return await orderRepo.createOrder(newOrder);
      },
    );
  }

  Future<Either<Failure, bool>> deleteOrder(int id) async {
    return await orderRepo.deleteOrder(id);
  }

  Future<Either<Failure, List<OrderEntity>>> getOrders() async {
    return orderRepo.getAllOrders();
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
  /// │ Prec. Recurr.    │ DAG, 1 máq/etapa   │ Con deps cícl  │ Sí             │
  /// │ Prec. Rec. Flex. │ DAG, N máq/etapa   │ Con deps cícl  │ Sí             │
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

    // 4. Extraer la matriz de tipos de máquinas por tarea y job
    // machineTypesId[i][j] = tipo de máquina de la j-ésima tarea del i-ésimo job.
    //
    // Ejemplo Flow Shop (todos iguales):
    //   Job A: [Tipo1, Tipo2, Tipo3]
    //   Job B: [Tipo1, Tipo2, Tipo3]
    //
    // Ejemplo Job Shop (rutas distintas):
    //   Job A: [Tipo1, Tipo3, Tipo2]
    //   Job B: [Tipo2, Tipo1, Tipo3]
    final List<List<int>> machineTypesId = order.orderJobs!
        .map((job) =>
            job.sequence!.tasks!.map((task) => task.machineTypeId).toList())
        .toList();

    // 5. Calcular longitud máxima de secuencia
    // `max` = número máximo de etapas (tareas) entre todos los jobs.
    // Si max == 1 → solo hay una etapa (Single Machine o Parallel Machines).
    // Si max >  1 → hay múltiples etapas (Flow Shop, Job Shop, etc.).
    int max = 0;
    for (var row in machineTypesId) {
      if (row.length > max) max = row.length;
    }

    // 6. Detectar si las rutas son diferentes entre jobs
    // `differentMachine` = true si al menos dos jobs visitan los tipos de
    // máquinas en un orden distinto (o tienen longitudes de ruta distintas).
    //
    // Flow Shop / Open Shop → differentMachine = false (misma secuencia de tipos)
    // Job Shop              → differentMachine = true  (secuencias distintas)
    bool differentMachine = false;
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

    // 7. Detectar si cada tipo de máquina tiene exactamente 1 máquina
    // `allOne` = true  → ambiente "no flexible" (una máquina por tipo/etapa)
    // `allOne` = false → ambiente "flexible"    (varias máquinas por tipo/etapa)
    //
    // Esto distingue, por ejemplo:
    //   Flow Shop          (allOne=true)  vs Flexible Flow Shop (allOne=false)
    //   Job Shop           (allOne=true)  vs Flexible Job Shop  (allOne=false)
    //   Single Machine     (allOne=true)  vs Parallel Machines  (allOne=false)
    bool allOne = true;
    for (final row in machineTypesId) {
      for (final machineType in row) {
        final r = await machineRepo.countMachinesOf(machineType);
        r.fold((_) => allOne = false, (n) {
          if (n != 1) allOne = false;
        });
      }
    }

    // 8. Detectar precedencias explícitas entre tareas
    // Una "dependencia" en la secuencia indica que la tarea B no puede comenzar
    // hasta que la tarea A haya terminado (relación predecesor→sucesor).
    //
    // hasExplicitPrecedence = true si existe al menos una dependencia válida
    // (predecesor ≠ sucesor, y ambas tareas pertenecen al mismo job).
    bool hasExplicitPrecedence = false;
    for (var job in order.orderJobs!) {
      final dependencies = job.sequence?.dependencies ?? [];
      final taskIds = job.sequence?.tasks?.map((t) => t.id).toSet() ?? {};

      for (final dep in dependencies) {
        if (dep.predecessor_id != dep.successor_id &&
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

// 9. Detectar precedencias recurrentes
// Una PRECEDENCIA RECURRENTE ocurre cuando una tarea (estación) requiere
// que MÁS DE UNA tarea predecesora haya finalizado antes de poder comenzar.
// Es decir, en el grafo de dependencias, un nodo sucesor tiene 2 o más
// predecesores distintos apuntando hacia él.
//
// Ejemplo:
//   tarea1 ──┐
//             ├──► tarea3  ← tarea3 necesita que tarea1 Y tarea2 terminen
//   tarea2 ──┘
//
// Esto es distinto al Job Shop (donde cada tarea tiene a lo sumo un predecesor).
// NO tiene relación con repetir el mismo tipo de máquina en la ruta.
    bool hasRecurringPrecedence = false;
    if (hasExplicitPrecedence) {
      for (var job in order.orderJobs!) {
        final dependencies = job.sequence?.dependencies ?? [];
        final taskIds = job.sequence?.tasks?.map((t) => t.id).toSet() ?? {};

        // Contar cuántos predecesores tiene cada tarea sucesor dentro del job.
        // predecessorCount[successorId] = número de predecesores distintos que
        // apuntan a esa tarea.
        final Map<int, int> predecessorCount = {};

        for (final dep in dependencies) {
          if (dep.predecessor_id != null &&
              dep.successor_id != null &&
              dep.predecessor_id != dep.successor_id &&
              taskIds.contains(dep.predecessor_id) &&
              taskIds.contains(dep.successor_id)) {
            final successorId = dep.successor_id!;
            predecessorCount[successorId] =
                (predecessorCount[successorId] ?? 0) + 1;
          }
        }

        // Si alguna tarea acumula 2 o más predecesores → precedencia recurrente
        if (predecessorCount.values.any((count) => count >= 2)) {
          hasRecurringPrecedence = true;
          print("Precedencia recurrente detectada en job ${job.jobId}: "
              "una tarea tiene ${predecessorCount.values.where((c) => c >= 2).first} predecesores");
          break;
        }
      }
    }

    // 10. Clasificar el ambiente de cada job individualmente
    // Antes de determinar el ambiente global de la orden, se clasifica cada job
    // por separado. Esto permite detectar casos mixtos donde distintos jobs
    // pertenecerían a ambientes diferentes (ej: un job es Flow Shop y otro es
    // Open Shop). En esos casos se aplica la regla de prioridad OPEN (ver paso 11).
    //
    // Para clasificar cada job individualmente se reutilizan las variables globales
    // ya calculadas (allOne, hasExplicitPrecedence, hasRecurringPrecedence) pero
    // se recalcula differentMachine y max de forma local para ese job versus
    // el resto, usando su ruta particular de tipos de máquinas.
    final List<String> jobEnvironments = [];

    for (int i = 0; i < order.orderJobs!.length; i++) {
      final jobTypes = machineTypesId[i];
      final int jobMax = jobTypes.length;

      // Verificar si la ruta de este job difiere de la ruta "común" detectada
      // globalmente (commonMachinesId). Si commonMachinesId está vacío (no hubo
      // ruta común) o la ruta del job no coincide, se marca como diferente.
      bool jobDifferentMachine = differentMachine;
      if (!differentMachine) {
        // Si globalmente no hay diferencia, este job comparte la ruta común
        jobDifferentMachine = false;
      }

      // Clasificar este job con las mismas reglas del paso 10
      String jobEnv;
      if (hasRecurringPrecedence && !allOne) {
        jobEnv = "FLEXIBLE JOB SHOP";
      } else if (hasRecurringPrecedence && allOne) {
        jobEnv = "JOB SHOP";
      } else if (jobDifferentMachine &&
          !allOne &&
          hasExplicitPrecedence &&
          !hasRecurringPrecedence) {
        jobEnv = "FLEXIBLE JOB SHOP";
      } else if (jobDifferentMachine &&
          allOne &&
          hasExplicitPrecedence &&
          !hasRecurringPrecedence) {
        jobEnv = "JOB SHOP";
      } else if (!jobDifferentMachine &&
          jobMax > 1 &&
          !allOne &&
          hasExplicitPrecedence &&
          !hasRecurringPrecedence) {
        jobEnv = "FLEXIBLE FLOW SHOP";
      } else if (!jobDifferentMachine &&
          jobMax > 1 &&
          allOne &&
          hasExplicitPrecedence &&
          !hasRecurringPrecedence) {
        jobEnv = "FLOW SHOP";
      } else if (!jobDifferentMachine &&
          jobMax > 1 &&
          !allOne &&
          !hasExplicitPrecedence) {
        jobEnv = "FLEXIBLE OPEN SHOP";
      } else if (!jobDifferentMachine &&
          jobMax > 1 &&
          allOne &&
          !hasExplicitPrecedence) {
        jobEnv = "OPEN SHOP";
      } else if (jobMax == 1 && !allOne) {
        jobEnv = "PARALLEL MACHINES";
      } else if (jobMax == 1 && allOne) {
        jobEnv = "SINGLE MACHINE";
      } else {
        jobEnv = "OPEN SHOP";
      }

      print("  Job ${order.orderJobs![i].jobId} clasificado como: $jobEnv");
      jobEnvironments.add(jobEnv);
    }

    // 11. Aplicar regla de prioridad OPEN entre ambientes mixtos
    // Si los jobs individuales arrojan ambientes distintos (mezcla), se aplica
    // la siguiente jerarquía de prioridad para elegir el ambiente global:
    //
    //   Prioridad 1 → cualquier variante OPEN SHOP o FLEXIBLE OPEN SHOP
    //                 (un ambiente sin orden obligatorio absorbe a los demás,
    //                  ya que si al menos un job es libre en su secuencia,
    //                  la orden entera se trata como Open Shop)
    //   Prioridad 2 → si no hay OPEN pero hay mezcla, se usa el ambiente
    //                 global calculado en el paso 10 (lógica original).
    //
    // Ejemplo de casos que activan esta regla:
    //   [FLOW SHOP, OPEN SHOP, JOB SHOP]         → OPEN SHOP  (prioridad OPEN)
    //   [FLEXIBLE FLOW SHOP, FLEXIBLE OPEN SHOP]  → FLEXIBLE OPEN SHOP (prioridad OPEN)
    //   [FLOW SHOP, JOB SHOP]                     → ambiente global del paso 10
    final bool hasMixedEnvironments = jobEnvironments.toSet().length > 1;

    // 12. Clasificar el ambiente global de la orden completa
    // El orden de evaluación importa: de lo más específico a lo más general.

    /// ── PRECEDENCIA RECURRENTE FLEXIBLE ──────────────────────────────────────
    /// Condiciones: hay tipos de máquina repetidos en la ruta (recurrente),
    /// hay precedencias explícitas, Y cada tipo de máquina tiene >1 máquina.
    /// Ejemplo: estación A→B→A donde cada estación tiene varias máquinas paralelas.
    bool isRecurringFlexible = hasRecurringPrecedence && !allOne;

    /// ── PRECEDENCIA RECURRENTE (CLÁSICA) ─────────────────────────────────────
    /// Igual que la anterior pero cada estación tiene exactamente 1 máquina.
    bool isRecurring = hasRecurringPrecedence && allOne;

    /// ── SINGLE MACHINE ────────────────────────────────────────────────────────
    /// Una sola etapa con exactamente 1 máquina.
    /// Todos los jobs se procesan en la misma y única máquina.
    bool isSingleMachine = !differentMachine && max == 1 && allOne;

    /// ── PARALLEL MACHINES ─────────────────────────────────────────────────────
    /// Una sola etapa pero con VARIAS máquinas del mismo tipo (en paralelo).
    /// Los jobs compiten por cualquiera de las máquinas disponibles.
    bool isParallelMachines = !differentMachine && max == 1 && !allOne;

    /// ── FLOW SHOP ─────────────────────────────────────────────────────────────
    /// Múltiples etapas, todos los jobs siguen LA MISMA ruta de tipos de máquinas,
    /// cada etapa tiene exactamente 1 máquina, y hay precedencia entre tareas.
    bool isFlowShop = !differentMachine &&
        max > 1 &&
        allOne &&
        hasExplicitPrecedence &&
        !hasRecurringPrecedence;

    /// ── FLEXIBLE FLOW SHOP ────────────────────────────────────────────────────
    /// Como Flow Shop, pero cada etapa puede tener VARIAS máquinas en paralelo.
    bool isFlexibleFlowShop = !differentMachine &&
        max > 1 &&
        !allOne &&
        hasExplicitPrecedence &&
        !hasRecurringPrecedence;

    /// ── OPEN SHOP ─────────────────────────────────────────────────────────────
    /// Múltiples etapas, todos los jobs visitan los mismos tipos de máquinas
    /// pero SIN un orden obligatorio entre ellas (sin precedencias explícitas).
    /// Cada etapa tiene 1 máquina.
    bool isOpenShop =
        !differentMachine && max > 1 && allOne && !hasExplicitPrecedence;

    /// ── FLEXIBLE OPEN SHOP ────────────────────────────────────────────────────
    /// Como Open Shop, pero cada etapa tiene VARIAS máquinas en paralelo.
    bool isFlexibleOpenShop =
        !differentMachine && max > 1 && !allOne && !hasExplicitPrecedence;

    /// ── JOB SHOP ──────────────────────────────────────────────────────────────
    /// Múltiples etapas, cada job puede tener una RUTA DIFERENTE de tipos de
    /// máquinas (differentMachine=true), con precedencias explícitas,
    /// y cada tipo de máquina tiene exactamente 1 máquina.
    bool isJobShop = differentMachine &&
        allOne &&
        hasExplicitPrecedence &&
        !hasRecurringPrecedence;

    /// ── FLEXIBLE JOB SHOP ────────────────────────────────────────────────────
    /// Como Job Shop pero cada tipo de máquina tiene VARIAS máquinas en paralelo.
    bool isFlexibleJobShop = differentMachine &&
        !allOne &&
        hasExplicitPrecedence &&
        !hasRecurringPrecedence;

    // 13. Asignar nombre del ambiente (orden: más específico primero)
    // Si hay ambientes mixtos entre jobs, se evalúa primero la regla de
    // prioridad OPEN antes de aplicar la clasificación global normal.
    String enviroment;

    if (hasMixedEnvironments) {
      // Regla de prioridad OPEN: si algún job es Open Shop o Flexible Open Shop,
      // toda la orden se trata bajo ese ambiente más permisivo.
      // Se prefiere FLEXIBLE OPEN SHOP sobre OPEN SHOP si hay máquinas paralelas.
      final hasFlexibleOpen = jobEnvironments.contains("FLEXIBLE OPEN SHOP");
      final hasOpen = jobEnvironments.contains("OPEN SHOP");

      if (hasFlexibleOpen) {
        // Al menos un job no tiene orden obligatorio y hay máquinas paralelas
        enviroment = "FLEXIBLE OPEN SHOP";
        print(
            "DEBUG: Mezcla de ambientes detectada → prioridad FLEXIBLE OPEN SHOP");
      } else if (hasOpen) {
        // Al menos un job no tiene orden obligatorio con 1 máquina por etapa
        enviroment = "OPEN SHOP";
        print("DEBUG: Mezcla de ambientes detectada → prioridad OPEN SHOP");
      } else {
        // Mezcla sin ningún OPEN: se cae a la clasificación global normal
        print("DEBUG: Mezcla sin OPEN → usando clasificación global");
        enviroment = _resolveGlobalEnvironment(
          isRecurringFlexible: isRecurringFlexible,
          isRecurring: isRecurring,
          isFlexibleJobShop: isFlexibleJobShop,
          isJobShop: isJobShop,
          isFlexibleFlowShop: isFlexibleFlowShop,
          isFlowShop: isFlowShop,
          isFlexibleOpenShop: isFlexibleOpenShop,
          isOpenShop: isOpenShop,
          isParallelMachines: isParallelMachines,
          isSingleMachine: isSingleMachine,
          differentMachine: differentMachine,
          max: max,
          allOne: allOne,
          hasExplicitPrecedence: hasExplicitPrecedence,
          hasRecurringPrecedence: hasRecurringPrecedence,
        );
      }
    } else {
      // Todos los jobs tienen el mismo ambiente: clasificación global normal
      enviroment = _resolveGlobalEnvironment(
        isRecurringFlexible: isRecurringFlexible,
        isRecurring: isRecurring,
        isFlexibleJobShop: isFlexibleJobShop,
        isJobShop: isJobShop,
        isFlexibleFlowShop: isFlexibleFlowShop,
        isFlowShop: isFlowShop,
        isFlexibleOpenShop: isFlexibleOpenShop,
        isOpenShop: isOpenShop,
        isParallelMachines: isParallelMachines,
        isSingleMachine: isSingleMachine,
        differentMachine: differentMachine,
        max: max,
        allOne: allOne,
        hasExplicitPrecedence: hasExplicitPrecedence,
        hasRecurringPrecedence: hasRecurringPrecedence,
      );
    }

    print("DEBUG: Ambiente detectado → $enviroment\n");

    // 14. Retornar el ambiente desde el repositorio
    return orderRepo.getEnvironmentByName(enviroment);
  }

// ─────────────────────────────────────────────────────────────────────────────
// HELPER: Resolver el ambiente global a partir de los booleanos calculados
// ─────────────────────────────────────────────────────────────────────────────
// Se extrae como función separada para evitar duplicar la lógica de resolución
// tanto en el caso de ambientes mixtos (sin OPEN) como en el caso homogéneo.
  String _resolveGlobalEnvironment({
    required bool isRecurringFlexible,
    required bool isRecurring,
    required bool isFlexibleJobShop,
    required bool isJobShop,
    required bool isFlexibleFlowShop,
    required bool isFlowShop,
    required bool isFlexibleOpenShop,
    required bool isOpenShop,
    required bool isParallelMachines,
    required bool isSingleMachine,
    required bool differentMachine,
    required int max,
    required bool allOne,
    required bool hasExplicitPrecedence,
    required bool hasRecurringPrecedence,
  }) {
    if (isRecurringFlexible) {
      return "FLEXIBLE JOB SHOP";
    } else if (isRecurring) {
      return "JOB SHOP";
    } else if (isFlexibleJobShop) {
      return "FLEXIBLE JOB SHOP";
    } else if (isJobShop) {
      return "JOB SHOP";
    } else if (isFlexibleFlowShop) {
      return "FLEXIBLE FLOW SHOP";
    } else if (isFlowShop) {
      return "FLOW SHOP";
    } else if (isFlexibleOpenShop) {
      return "FLEXIBLE OPEN SHOP";
    } else if (isOpenShop) {
      return "OPEN SHOP";
    } else if (isParallelMachines) {
      return "PARALLEL MACHINES";
    } else if (isSingleMachine) {
      return "SINGLE MACHINE";
    } else {
      print("DEBUG FALLBACK → OPEN SHOP | differentMachine=$differentMachine "
          "max=$max allOne=$allOne precedence=$hasExplicitPrecedence "
          "recurring=$hasRecurringPrecedence");
      return "OPEN SHOP";
    }
  }

  // ------------------------------------------------------------------------
  // --------------------------- SCHEDULER ----------------------------------
  // ------------------------------------------------------------------------

  Future<Either<Failure, Tuple2<List<PlanningMachineEntity>, Metrics>?>>
      scheduleOrder(Tuple3<int, String, String> sch) async {
    return switch (sch.value3) {
      'SINGLE MACHINE' => Right(await SingleMachineAdapter(
              orderRepository: orderRepo, 
              machineRepository: machineRepo, setupTimeService: setupTimeService)
          .singleMachineAdapter(sch.value1, sch.value2)),
      'PARALLEL MACHINES' => Right(await ParallelMachineAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo, setupTimeService: setupTimeService)
          .parallelMachineAdapter(sch.value1, sch.value2)),
      'FLOW SHOP' => Right(await FlowShopAdapter(
              machineRepository: machineRepo, 
              orderRepository: orderRepo, setupTimeService: setupTimeService)
          .flowShopAdapter(sch.value1, sch.value2)),
      'FLEXIBLE FLOW SHOP' => Right(await FlexibleFlowShopAdapter(
              machineRepository: machineRepo, orderRepository: orderRepo, setupTimeService: setupTimeService)
          .flexibleFlowShopAdapter(sch.value1, sch.value2)),
      'FLEXIBLE JOB SHOP' => await FlexibleJobShopAdapter(
              machineRepository: machineRepo,
              orderRepository: orderRepo,
              setupTimeService: setupTimeService)
          .flexibleJobShopAdapter(sch.value1, sch.value2).then((result) => result == null ? Left(LocalStorageFailure()) : Right(result)),
      'JOB SHOP' => await JobShopAdapter(
              machineRepository: machineRepo,
              orderRepository: orderRepo,
              setupTimeService: setupTimeService)
            .jobShopAdapter(sch.value1, sch.value2).then((result) => result == null ? Left(LocalStorageFailure()) : Right(result)),
      'OPEN SHOP' || 'FLEXIBLE OPEN SHOP' => await OpenShopAdapter(
              machineRepository: machineRepo,
              orderRepository: orderRepo,
              setupTimeService: setupTimeService)
          .openShopAdapter(sch.value1, sch.value2)
          .then((result) =>
              result == null ? Left(LocalStorageFailure()) : Right(result)),
      String() => Left(EnviromentNotCorrectFailure()),
    };
  }
}
