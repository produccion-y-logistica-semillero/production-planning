import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class OpenShopInput {
  final int jobId;
  final int dbJobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  // Lista de operaciones sin orden específico: <taskId, Map<machineId, Duration>>
  final List<Tuple2<int, Map<int, Duration>>> operations;
  final List<TaskDependencyEntity> dependencies;

  /// Whether each task (keyed by task id) may be split by a work-shift
  /// boundary, the continuous-use rest cap, or a maintenance window.
  /// Missing entries default to interruptible.
  final Map<int, bool> interruptibleByTask;

  OpenShopInput(
    this.jobId,
    this.dbJobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.operations, {
    this.dependencies = const [],
    this.interruptibleByTask = const {},
  });

  bool isTaskInterruptible(int taskId) => interruptibleByTask[taskId] ?? true;
}

class OpenShopOutput {
  final int jobId;
  final int dbJobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  // Scheduling: taskId -> (machineId, Range)
  final Map<int, Tuple2<int, Range>> scheduling;

  /// Processing segments per task (taskId → segments), for tasks that were
  /// preempted mid-processing.
  final Map<int, List<ProcessingSegment>> segmentsByTask;

  /// Setup/changeover segments per task (taskId → segments), if any.
  final Map<int, List<ProcessingSegment>> setupSegmentsByTask;

  OpenShopOutput(
    this.jobId,
    this.dbJobId,
    this.dueDate,
    this.startDate,
    this.endTime,
    this.scheduling, {
    Map<int, List<ProcessingSegment>>? segmentsByTask,
    this.setupSegmentsByTask = const {},
  }) : segmentsByTask = segmentsByTask ??
            scheduling.map((taskId, entry) => MapEntry(taskId,
                [ProcessingSegment(entry.value2.start, entry.value2.end)]));
}

class OpenShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<OpenShopInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  Map<int, List<MachineInactivityEntity>> machineInactivities;
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count.
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;

  /// How long each machine has run continuously since its last pause.
  final Map<int, Duration> _machineContinuousUsage = {};
  final Map<int, PreemptionEngine> _engineByMachine = {};

  PreemptionEngine _engineFor(int machineId) {
    return _engineByMachine.putIfAbsent(machineId, () {
      final capacityMinutes = machineContinueCapacity[machineId] ?? 0;
      return PreemptionEngine(
        workingSchedule: workingSchedule,
        maintenanceWindows: machineInactivities[machineId] ?? const [],
        continuousUseCap: capacityMinutes > 0
            ? Duration(minutes: capacityMinutes)
            : Duration.zero,
        restDuration: machineRestTime[machineId] ?? Duration.zero,
      );
    });
  }

  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;
  final Map<int, int?> _machineLastSequence = {};
  final Map<int, int?> _machineLastJob = {};
  List<OpenShopOutput> output = [];

  OpenShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
    this.stateSetupMatrix,
    this.jobStates,
  }) {
    _initializeMachineLastSequence();
    final r = rule.toUpperCase();
    print('OpenShop: starting scheduling rule=$r for ${inputJobs.length} jobs');
    switch (r) {
      case "FIFO":
        scheduleOpenShopFIFO();
        break;
      case "SPT":
        scheduleOpenShopSPT();
        break;
      case "LPT":
        scheduleOpenShopLPT();
        break;
      case "EDD":
        scheduleOpenShopEDD();
        break;
      case "WSPT":
        scheduleOpenShopWSPT();
        break;
      // The database grants MINSLACK (rule id 11) to Open Shop and Flexible
      // Open Shop, but only "MS" was handled — so picking Minimum Slack fell
      // through to `default:` and silently ran SPT instead. Same rule, two
      // names across environments.
      case "MINSLACK":
      case "MS":
        scheduleOpenShopMS();
        break;
      case "MWR":
        scheduleOpenShopMWR();
        break;
      case "CR":
        scheduleOpenShopCR();
        break;
      case "ATCS":
        scheduleOpenShopATCS();
        break;
      case "GENETICS":
        // Simple genetics-like ordering based on CR and WSPT
        _schedule((a, b) {
          final crA = _calculateCR(a.job as OpenShopInput,
              a.duration as Duration, a.earliestStart as DateTime);
          final crB = _calculateCR(b.job as OpenShopInput,
              b.duration as Duration, b.earliestStart as DateTime);
          final durationMinutesA = (a.duration as Duration).inMinutes;
          final durationMinutesB = (b.duration as Duration).inMinutes;
          final wsptA = a.job.priority / max(1, durationMinutesA);
          final wsptB = b.job.priority / max(1, durationMinutesB);
          final scoreA = (1 / max(crA, 0.0001)) + wsptA;
          final scoreB = (1 / max(crB, 0.0001)) + wsptB;
          return scoreB.compareTo(scoreA);
        });
        break;
      default:
        scheduleOpenShopSPT();
    }
    print('OpenShop: constructor finished (scheduling started/completed)');
  }

  void _initializeMachineLastSequence() {
    for (final machineId in machinesAvailability.keys) {
      _machineLastSequence.putIfAbsent(machineId, () => null);
      _machineLastJob.putIfAbsent(machineId, () => null);
    }
  }

  DateTime _adjustForWorkingSchedule(DateTime dt) {
    final hour = dt.hour;
    final minute = dt.minute;
    final currentMinutes = hour * 60 + minute;
    final startMinutes =
        workingSchedule.value1.hour * 60 + workingSchedule.value1.minute;
    final endMinutes =
        workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;

    if (currentMinutes < startMinutes) {
      return DateTime(
        dt.year,
        dt.month,
        dt.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
    } else if (currentMinutes >= endMinutes) {
      final nextDay = dt.add(const Duration(days: 1));
      return DateTime(
        nextDay.year,
        nextDay.month,
        nextDay.day,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      );
    }
    return dt;
  }

  void scheduleOpenShopFIFO() {
    _schedule((a, b) => a.job.availableDate.compareTo(b.job.availableDate));
  }

  void scheduleOpenShopSPT() {
    _schedule((a, b) => a.duration.compareTo(b.duration));
  }

  void scheduleOpenShopLPT() {
    _schedule((a, b) => b.duration.compareTo(a.duration));
  }

  void scheduleOpenShopEDD() {
    _schedule((a, b) => a.job.dueDate.compareTo(b.job.dueDate));
  }

  void scheduleOpenShopWSPT() {
    _schedule((a, b) {
      final wsptA = a.job.priority / a.duration.inMinutes;
      final wsptB = b.job.priority / b.duration.inMinutes;
      return wsptB.compareTo(wsptA);
    });
  }

  void scheduleOpenShopMS() => _scheduleDynamic(DispatchCriterion.ms);

  void scheduleOpenShopMWR() {
    _schedule((a, b) {
      final remainingA =
          _remainingWork(a.job as OpenShopInput, a.taskId as int);
      final remainingB =
          _remainingWork(b.job as OpenShopInput, b.taskId as int);
      return remainingB.compareTo(remainingA);
    });
  }

  void scheduleOpenShopCR() => _scheduleDynamic(DispatchCriterion.cr);

  void scheduleOpenShopATCS() => _scheduleDynamic(DispatchCriterion.atcs);

  int _remainingWork(OpenShopInput job, int currentTaskId) {
    // Calcula el trabajo restante para un job (excluyendo la tarea actual)
    int totalMinutes = 0;
    for (var operation in job.operations) {
      if (operation.value1 != currentTaskId) {
        if (operation.value2.isEmpty) continue;
        final sum = operation.value2.values
            .map((d) => d.inMinutes)
            .fold<int>(0, (a, b) => a + b);
        final avgDuration = sum ~/ operation.value2.length;
        totalMinutes += avgDuration;
      }
    }
    return totalMinutes;
  }

  /// Critical ratio used only by the GENETICS score, at [now] — the
  /// schedule's clock, never the wall clock.
  double _calculateCR(OpenShopInput job, Duration duration, DateTime now) {
    final cr =
        job.dueDate.difference(now).inMinutes / max(duration.inMinutes, 1);
    return cr < 0 ? 0 : cr;
  }

  // ── Dynamic literature rules (MS, CR, ATCS) ───────────────────────────────
  //
  // The literature defines all three in terms of the clock t. They used to
  // read DateTime.now() — the wall clock when the button was pressed — so
  // the same order could schedule differently from one minute to the next,
  // and against any plan dated in the past every job looked late and tied
  // at zero. They also charged the operation's NOMINAL duration, blind to
  // changeovers and interruptions.
  //
  // Now each contending operation is priced through the preemption engine
  // from the schedule's own clock — the instant it can start, which is the
  // decision point of this non-delay loop — and compared with the shared
  // criteria in dynamic_dispatch.dart. The job's other pending operations
  // are charged against its due date as nominal work still to do.

  void _scheduleDynamic(DispatchCriterion criterion) {
    final AtcsParameters? atcs =
        criterion == DispatchCriterion.atcs ? _atcsParameters() : null;
    _schedule(
      (a, b) {
        final int cmp = compareCandidates<OpenShopInput>(
          criterion,
          a.dispatch as DispatchCandidate<OpenShopInput>,
          b.dispatch as DispatchCandidate<OpenShopInput>,
          // The loop only consults the rule among candidates that can start
          // at the same instant, so this is the shared decision time.
          decisionTime: a.earliestStart as DateTime,
          atcs: atcs,
        );
        if (cmp != 0) return cmp;
        // Operations of one job share its jobId, the last tie-break
        // compareCandidates has; settle those too, since List.sort is not
        // stable and two runs could otherwise disagree.
        final int byTask = (a.taskId as int).compareTo(b.taskId as int);
        if (byTask != 0) return byTask;
        return (a.machineId as int).compareTo(b.machineId as int);
      },
      priceCandidates: true,
    );
  }

  /// Prices one operation of [job] on [machineId] from [at] as a
  /// [DispatchCandidate], without committing anything.
  DispatchCandidate<OpenShopInput> _dispatchCandidate(
    OpenShopInput job,
    int taskId,
    int machineId,
    Duration duration,
    DateTime at,
    Set<int> completed,
  ) {
    final placed = _priceOperation(
      job: job,
      taskId: taskId,
      machineId: machineId,
      duration: duration,
      start: at,
    );
    final DateTime end = placed.schedule.completionTime;
    final Duration span = end.difference(at);
    return DispatchCandidate(
      job: job,
      start: placed.setupSegments.isNotEmpty
          ? placed.setupSegments.first.start
          : placed.schedule.startDate,
      end: end,
      span: span.isNegative ? Duration.zero : span,
      dueDate: job.dueDate,
      releaseDate: job.availableDate,
      priority: job.priority,
      jobId: job.jobId,
      setup: segmentsDuration(placed.setupSegments),
      remainingWork: _remainingWorkAfter(job, taskId, completed),
    );
  }

  /// Nominal work [job] still has after [taskId]: every other operation not
  /// yet completed, each at its mean duration over the machines that can run
  /// it.
  Duration _remainingWorkAfter(
      OpenShopInput job, int taskId, Set<int> completed) {
    Duration total = Duration.zero;
    for (final operation in job.operations) {
      if (operation.value1 == taskId || completed.contains(operation.value1)) {
        continue;
      }
      if (operation.value2.isEmpty) continue;
      total +=
          operation.value2.values.fold(Duration.zero, (sum, d) => sum + d) ~/
              operation.value2.length;
    }
    return total;
  }

  /// Changeover [machineId] needs before [job], out of the state the last
  /// job it ran left it in. Reads machine state only.
  Duration _setupFor(int machineId, OpenShopInput job) {
    final int? previousJobId = _machineLastJob[machineId];
    if (previousJobId == null ||
        previousJobId <= 0 ||
        stateSetupMatrix == null ||
        jobStates == null) {
      return Duration.zero;
    }
    final machineStates = stateSetupMatrix![machineId];
    if (machineStates == null) return Duration.zero;
    final previousState = jobStates![previousJobId]?[machineId];
    final currentState = jobStates![job.dbJobId]?[machineId];
    if (previousState == null || currentState == null) return Duration.zero;
    final setupMinutes = machineStates[previousState]?[currentState];
    return setupMinutes != null
        ? Duration(minutes: setupMinutes)
        : Duration.zero;
  }

  /// Schedules one operation — setup out of the machine's current state,
  /// then processing — through the preemption engine, WITHOUT committing
  /// anything. The dynamic rules price every contender with it and the loop
  /// commits the winner with it, so the two cannot disagree.
  ({
    List<ProcessingSegment> setupSegments,
    SegmentedSchedule schedule,
    Duration usageAfterSetup,
  }) _priceOperation({
    required OpenShopInput job,
    required int taskId,
    required int machineId,
    required Duration duration,
    required DateTime start,
  }) {
    final Duration setupDuration = _setupFor(machineId, job);

    // Setup is its own segmented block, as sensitive to work-shift, rest and
    // maintenance boundaries as processing is; processing starts after it.
    List<ProcessingSegment> setupSegments = const [];
    DateTime processStart = start;
    Duration continuousUsage =
        _machineContinuousUsage[machineId] ?? Duration.zero;
    if (setupDuration > Duration.zero) {
      final setupSchedule = _engineFor(machineId).computeSegments(
        earliestStart: start,
        totalDuration: setupDuration,
        priorContinuousUsage: continuousUsage,
      );
      setupSegments = setupSchedule.segments;
      processStart = setupSchedule.completionTime;
      continuousUsage = setupSegments.length > 1
          ? setupSegments.last.duration
          : continuousUsage + setupSegments.single.duration;
    }

    // Split processing wherever the work-shift end, a maintenance window or
    // the continuous-use rest cap falls inside it.
    final schedule = _engineFor(machineId).computeSegments(
      earliestStart: processStart,
      totalDuration: duration,
      priorContinuousUsage: continuousUsage,
      interruptible: job.isTaskInterruptible(taskId),
    );

    return (
      setupSegments: setupSegments,
      schedule: schedule,
      usageAfterSetup: continuousUsage,
    );
  }

  /// Fits the ATCS parameters to this instance (see
  /// [AtcsParameters.calibrate]). A candidate here is one operation, so p̄
  /// is the mean operation time and s̄ the mean changeover between two
  /// distinct jobs on a machine they share. The makespan estimate is the
  /// larger of the busiest machine's expected load and the longest job —
  /// the shop can finish no sooner than either.
  AtcsParameters _atcsParameters() {
    final Map<int, double> load = {};
    double longestJob = 0;
    int operationCount = 0;
    for (final job in inputJobs) {
      double jobTotal = 0;
      for (final operation in job.operations) {
        final machines = operation.value2;
        if (machines.isEmpty) continue;
        final double mean = machines.values
                .fold<double>(0, (sum, d) => sum + d.inSeconds / 60.0) /
            machines.length;
        jobTotal += mean;
        operationCount++;
        // Spread the operation evenly over the machines that can run it.
        for (final machineId in machines.keys) {
          load[machineId] = (load[machineId] ?? 0) + mean / machines.length;
        }
      }
      longestJob = max(longestJob, jobTotal);
    }

    final double meanSetup = _meanSetupMinutes(load.keys);
    final int machineCount = max(load.length, 1);
    final double bottleneck = load.values.fold(0.0, (a, b) => max(a, b)) +
        operationCount * meanSetup / machineCount;
    final double workMinutes = max(bottleneck, longestJob);

    return AtcsParameters.calibrate(
      start: startDate,
      dueDates: inputJobs.map((job) => job.dueDate),
      meanProcessingMinutes: _averageProcessingTime(),
      meanSetupMinutes: meanSetup,
      makespanMinutes: calendarMinutes(
        PreemptionEngine(workingSchedule: workingSchedule),
        startDate,
        Duration(minutes: workMinutes.round()),
      ),
    );
  }

  /// s̄ at operation level: the mean changeover over every machine and every
  /// ordered pair of distinct jobs that both have a state on it.
  double _meanSetupMinutes(Iterable<int> machineIds) {
    if (stateSetupMatrix == null || jobStates == null) return 0;
    double total = 0;
    int count = 0;
    for (final machineId in machineIds) {
      final matrix = stateSetupMatrix![machineId];
      if (matrix == null) continue;
      final onMachine = inputJobs
          .where((job) =>
              job.operations.any((op) => op.value2.containsKey(machineId)))
          .toList();
      for (final from in onMachine) {
        final fromState = jobStates![from.dbJobId]?[machineId];
        if (fromState == null) continue;
        for (final to in onMachine) {
          if (identical(from, to)) continue;
          final toState = jobStates![to.dbJobId]?[machineId];
          final minutes = toState == null ? null : matrix[fromState]?[toState];
          if (minutes == null) continue;
          total += minutes;
          count++;
        }
      }
    }
    return count == 0 ? 0 : total / count;
  }

  double _averageProcessingTime() {
    double totalProcessingTime = 0;
    int taskCount = 0;

    for (var job in inputJobs) {
      for (var operation in job.operations) {
        for (var duration in operation.value2.values) {
          totalProcessingTime += duration.inMinutes.toDouble();
          taskCount++;
        }
      }
    }
    return taskCount > 0 ? totalProcessingTime / taskCount : 1;
  }

  /// Non-delay list scheduler: each round, the ready operations that can
  /// start earliest compete and [comparator] picks among them.
  ///
  /// [priceCandidates] prices every contender through the preemption engine
  /// and attaches it as `dispatch` — needed by the dynamic rules, skipped for
  /// the static ones, which only read nominal fields.
  void _schedule(int Function(dynamic, dynamic) comparator,
      {bool priceCandidates = false}) {
    print(
        'OpenShop._schedule: entering main loop for ${inputJobs.length} jobs');
    // Rastrear qué operaciones ya se completaron por job
    Map<int, Set<int>> completedOperations = {
      for (var job in inputJobs) job.jobId: <int>{},
    };

    Map<int, Map<int, Tuple2<int, Range>>> jobSchedulings = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, Map<int, List<ProcessingSegment>>> jobSegments = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, Map<int, List<ProcessingSegment>>> jobSetupSegments = {
      for (var job in inputJobs) job.jobId: {},
    };

    Map<int, DateTime> jobAvailability = {
      for (var job in inputJobs) job.jobId: job.availableDate,
    };

    Map<int, Map<int, DateTime>> taskCompletionTimes = {
      for (var job in inputJobs) job.jobId: {},
    };

    bool isTaskReady(OpenShopInput job, int taskId, Set<int> completed) {
      if (job.dependencies.isEmpty) {
        // Treat operations as unordered; allow first operation if no predecessor defined
        final idx = job.operations.indexWhere((t) => t.value1 == taskId);
        if (idx > 0) {
          final predId = job.operations[idx - 1].value1;
          return completed.contains(predId);
        }
        return true;
      } else {
        for (final dep in job.dependencies) {
          if (dep.successor_id == taskId) {
            if (!completed.contains(dep.predecessor_id)) return false;
          }
        }
        return true;
      }
    }

    DateTime getJobReadyTime(
        OpenShopInput job, int taskId, Map<int, DateTime> compTimes) {
      if (job.dependencies.isEmpty) {
        final idx = job.operations.indexWhere((t) => t.value1 == taskId);
        if (idx > 0) {
          final predId = job.operations[idx - 1].value1;
          return compTimes[predId] ?? job.availableDate;
        }
        return job.availableDate;
      } else {
        DateTime readyTime = job.availableDate;
        for (final dep in job.dependencies) {
          if (dep.successor_id == taskId) {
            final predEndTime = compTimes[dep.predecessor_id];
            if (predEndTime != null && predEndTime.isAfter(readyTime)) {
              readyTime = predEndTime;
            }
          }
        }
        return readyTime;
      }
    }

    int iter = 0;
    const int maxIter = 1000000;

    // Mientras haya operaciones sin completar
    while (completedOperations.entries.any((entry) {
      final job = inputJobs.firstWhere((j) => j.jobId == entry.key);
      return entry.value.length < job.operations.length;
    })) {
      iter++;
      if (iter % 10000 == 0) {
        print('OpenShop._schedule: iter=$iter');
      }
      if (iter > maxIter) {
        print(
            'OpenShop._schedule: reached max iterations ($maxIter), aborting loop');
        break;
      }
      List<
          ({
            OpenShopInput job,
            int taskId,
            int machineId,
            Duration duration,
            DateTime earliestStart,
            DispatchCandidate<OpenShopInput>? dispatch
          })> candidates = [];
      // First pricing failure this round, rethrown only if it leaves no
      // candidate at all — same policy as selectNext in dynamic_dispatch.dart.
      SchedulingHorizonException? pricingFailure;

      // Recopilar todas las operaciones candidatas (no completadas)
      for (var job in inputJobs) {
        final completed = completedOperations[job.jobId]!;
        final compTimes = taskCompletionTimes[job.jobId]!;

        for (var operation in job.operations) {
          final taskId = operation.value1;

          // Si ya se completó esta operación, skip
          if (completed.contains(taskId)) continue;

          if (!isTaskReady(job, taskId, completed)) continue;

          final jobReadyTime = getJobReadyTime(job, taskId, compTimes);

          // Verificar cada máquina posible para esta operación
          for (var entry in operation.value2.entries) {
            final machineId = entry.key;
            final duration = entry.value;
            final machineAvailable =
                machinesAvailability[machineId] ?? startDate;
            final jobAvail = jobReadyTime;

            final earliestStart = machineAvailable.isAfter(jobAvail)
                ? machineAvailable
                : jobAvail;
            final adjustedStart = _adjustForWorkingSchedule(earliestStart);

            // Dynamic rules compare what the operation really costs from
            // here, priced through the same code that commits it. One
            // impossible machine must not sink the operation's other
            // options, so a failure only drops this candidate.
            DispatchCandidate<OpenShopInput>? dispatch;
            if (priceCandidates) {
              try {
                dispatch = _dispatchCandidate(
                    job, taskId, machineId, duration, adjustedStart, completed);
              } on SchedulingHorizonException catch (e) {
                pricingFailure ??= e;
                continue;
              }
            }

            candidates.add((
              job: job,
              taskId: taskId,
              machineId: machineId,
              duration: duration,
              earliestStart: adjustedStart,
              dispatch: dispatch,
            ));
          }
        }
      }

      if (candidates.isEmpty) {
        // Every ready operation was unplaceable on every machine: that is
        // the calendar's fault, and the user has to hear about it.
        if (pricingFailure != null) throw pricingFailure;
        break;
      }

      // Ordenar candidatos según earliestStart primero (Non-delay), luego por la regla de despacho
      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        return comparator(a, b);
      });

      // Seleccionar el mejor candidato
      final selected = candidates.first;
      // Placed through the same code the dynamic rules priced candidates
      // with, so what gets committed is exactly what was judged.
      final placed = _priceOperation(
        job: selected.job,
        taskId: selected.taskId,
        machineId: selected.machineId,
        duration: selected.duration,
        start: selected.earliestStart,
      );
      final List<ProcessingSegment> setupSegments = placed.setupSegments;
      final SegmentedSchedule schedule = placed.schedule;
      final Duration continuousUsage = placed.usageAfterSetup;
      final DateTime taskStart = schedule.startDate;
      final DateTime adjustedEnd = schedule.completionTime;

      // Programar la operación con taskStart (así queda el gap de alistamiento)
      jobSchedulings[selected.job.jobId]![selected.taskId] =
          Tuple2(selected.machineId, Range(taskStart, adjustedEnd));
      jobSegments[selected.job.jobId]![selected.taskId] = schedule.segments;
      jobSetupSegments[selected.job.jobId]![selected.taskId] = setupSegments;

      // Actualizar disponibilidades
      machinesAvailability[selected.machineId] = adjustedEnd;
      jobAvailability[selected.job.jobId] = adjustedEnd;
      completedOperations[selected.job.jobId]!.add(selected.taskId);
      taskCompletionTimes[selected.job.jobId]![selected.taskId] = adjustedEnd;
      _machineLastSequence[selected.machineId] = selected.job.sequenceId;
      _machineLastJob[selected.machineId] = selected.job.dbJobId;
      _machineContinuousUsage[selected.machineId] = schedule.segments.length > 1
          ? schedule.segments.last.duration
          : continuousUsage + schedule.segments.single.duration;
    }

    // Generar outputs
    for (var job in inputJobs) {
      final scheduling = jobSchedulings[job.jobId]!;
      if (scheduling.isEmpty) continue;

      DateTime? startDate;
      DateTime? endDate;

      for (var entry in scheduling.values) {
        final range = entry.value2;
        if (startDate == null || range.start.isBefore(startDate)) {
          startDate = range.start;
        }
        if (endDate == null || range.end.isAfter(endDate)) {
          endDate = range.end;
        }
      }

      output.add(OpenShopOutput(
        job.jobId,
        job.dbJobId,
        job.dueDate,
        startDate ?? job.availableDate,
        endDate ?? job.availableDate,
        scheduling,
        segmentsByTask: jobSegments[job.jobId],
        setupSegmentsByTask: jobSetupSegments[job.jobId] ?? const {},
      ));
    }
  }

  int calcularCmax(List<OpenShopOutput> outputs) {
    if (outputs.isEmpty) return 0;

    DateTime maxEndTime = outputs.first.endTime;
    for (var output in outputs) {
      if (output.endTime.isAfter(maxEndTime)) {
        maxEndTime = output.endTime;
      }
    }

    return maxEndTime.difference(startDate).inMinutes;
  }
}

List<Map<String, dynamic>> openShopSchedule(Map<String, dynamic> payload) {
  final startDate =
      DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(
        hour: payload['workingStartHour'] as int,
        minute: payload['workingStartMinute'] as int),
    TimeOfDay(
        hour: payload['workingEndHour'] as int,
        minute: payload['workingEndMinute'] as int),
  );

  final List<OpenShopInput> inputJobs =
      (payload['inputJobs'] as List<dynamic>).map((jobData) {
    final jd = Map<String, dynamic>.from(jobData as Map);
    final Map<int, bool> interruptibleByTask = {};
    final operations = (jd['operations'] as List<dynamic>).map((opData) {
      final od = Map<String, dynamic>.from(opData as Map);
      final machineDurations =
          (od['machineDurations'] as Map<dynamic, dynamic>).map(
        (key, value) =>
            MapEntry(key as int, Duration(milliseconds: value as int)),
      );
      final taskId = od['taskId'] as int;
      interruptibleByTask[taskId] = (od['interruptible'] as bool?) ?? true;
      return Tuple2(taskId, machineDurations);
    }).toList();

    final dependencies = (jd['dependencies'] as List<dynamic>)
        .map((depData) {
          final depMap = Map<String, dynamic>.from(depData as Map);
          return TaskDependencyEntity(
            predecessor_id: depMap['predecessor_id'] as int,
            successor_id: depMap['successor_id'] as int,
            sequenceId: depMap['sequenceId'] as int,
          );
        })
        .cast<TaskDependencyEntity>()
        .toList();

    return OpenShopInput(
      jd['jobId'] as int,
      jd['dbJobId'] as int,
      jd['sequenceId'] as int,
      DateTime.fromMillisecondsSinceEpoch(jd['dueDate'] as int),
      jd['priority'] as int,
      DateTime.fromMillisecondsSinceEpoch(jd['availableDate'] as int),
      operations,
      dependencies: dependencies,
      interruptibleByTask: interruptibleByTask,
    );
  }).toList();

  final machinesAvailability =
      (payload['machinesAvailability'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
              key as int, DateTime.fromMillisecondsSinceEpoch(value as int)));

  final machineInactivities = <int, List<MachineInactivityEntity>>{};
  for (final entry
      in (payload['machineInactivities'] as Map<dynamic, dynamic>).entries) {
    final machineId = entry.key as int;
    final list = (entry.value as List<dynamic>);
    machineInactivities[machineId] = list
        .map((item) {
          final map = Map<String, dynamic>.from(item as Map);
          return MachineInactivityEntity(
            machineId: map['machineId'] as int,
            name: map['name'] as String,
            weekdays: (map['weekdays'] as List<dynamic>)
                .map((w) => Weekday.values[w as int])
                .toSet(),
            startTime: Duration(minutes: map['startTimeMinutes'] as int),
            duration: Duration(minutes: map['durationMinutes'] as int),
          );
        })
        .cast<MachineInactivityEntity>()
        .toList();
  }

  final machineContinueCapacity =
      (payload['machineContinueCapacity'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as int));

  final machineRestTime = <int, Duration?>{};
  for (final entry
      in (payload['machineRestTime'] as Map<dynamic, dynamic>).entries) {
    machineRestTime[entry.key as int] =
        entry.value == null ? null : Duration(milliseconds: entry.value as int);
  }

  final stateSetupMatrix = payload['stateSetupMatrix'] == null
      ? null
      : (payload['stateSetupMatrix'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
            key as int,
            (Map<dynamic, dynamic>.from(value as Map)).map(
              (prev, curr) => MapEntry(
                prev as String,
                (Map<dynamic, dynamic>.from(curr as Map)).map((next, minutes) =>
                    MapEntry(next as String, minutes as int)),
              ),
            ),
          ),
        );

  final jobStates = payload['jobStates'] == null
      ? null
      : (payload['jobStates'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
            key as int,
            (Map<dynamic, dynamic>.from(value as Map))
                .map((mKey, state) => MapEntry(mKey as int, state as String)),
          ),
        );

  final output = OpenShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
  ).output;

  return output.map((out) {
    return {
      'jobId': out.jobId,
      'dbJobId': out.dbJobId,
      'dueDate': out.dueDate.millisecondsSinceEpoch,
      'startDate': out.startDate.millisecondsSinceEpoch,
      'endTime': out.endTime.millisecondsSinceEpoch,
      'scheduling':
          out.scheduling.map((key, value) => MapEntry(key.toString(), {
                'machineId': value.value1,
                'start': value.value2.startDate.millisecondsSinceEpoch,
                'end': value.value2.endDate.millisecondsSinceEpoch,
              })),
      'segmentsByTask': out.segmentsByTask.map((taskId, segments) => MapEntry(
            taskId.toString(),
            segments
                .map((s) => {
                      'start': s.start.millisecondsSinceEpoch,
                      'end': s.end.millisecondsSinceEpoch,
                    })
                .toList(),
          )),
      'setupSegmentsByTask':
          out.setupSegmentsByTask.map((taskId, segments) => MapEntry(
                taskId.toString(),
                segments
                    .map((s) => {
                          'start': s.start.millisecondsSinceEpoch,
                          'end': s.end.millisecondsSinceEpoch,
                        })
                    .toList(),
              )),
    };
  }).toList();
}
