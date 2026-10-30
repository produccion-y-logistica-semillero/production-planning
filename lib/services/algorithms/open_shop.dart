import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/genetic_engine.dart';
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

  /// machineId → state letter (A-J) the machine starts this order in,
  /// before its first job. Used only when a machine has no prior job yet;
  /// once one has run, its own left-behind state takes over.
  final Map<int, String> initialMachineState;
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
    this.initialMachineState = const {},
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
      case "LWR":
        scheduleOpenShopLWR();
        break;
      case "CR":
        scheduleOpenShopCR();
        break;
      case "ATCS":
        scheduleOpenShopATCS();
        break;
      // Composite priority score (1/CR + w/p). It used to be offered as
      // "GENETICS", but it is a dispatching index, not a genetic algorithm.
      case "PRIORIDAD_COMPUESTA":
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
          final cmp = scoreB.compareTo(scoreA);
          if (cmp != 0) return cmp;
          // List.sort is not stable: settle ties so runs agree.
          final byJob = (a.job.jobId as int).compareTo(b.job.jobId as int);
          if (byJob != 0) return byJob;
          return (a.taskId as int).compareTo(b.taskId as int);
        });
        break;
      case "GENETICS":
        scheduleOpenShopGenetic();
        break;
      default:
        scheduleOpenShopSPT();
    }
    print('OpenShop: constructor finished (scheduling started/completed)');
  }

  /// Genetic algorithm with an operation-based chromosome (Prins, 2000;
  /// Bierwirth, 1995) plus a machine-assignment vector for Flexible Open
  /// Shop. Each chromosome is decoded with the same non-delay loop the rules
  /// use: among the operations that can start at t*, the one earlier in the
  /// chromosome goes first, on the machine its gene assigns. Fitness:
  /// makespan. See docs/diagnostico_genetics.md.
  void scheduleOpenShopGenetic({
    GeneticSettings settings = const GeneticSettings(),
  }) {
    final ops = <({OpenShopInput job, int taskId, List<int> machines})>[
      for (final job in inputJobs)
        for (final op in job.operations)
          (
            job: job,
            taskId: op.value1,
            machines: op.value2.keys.toList()..sort(),
          ),
    ];
    if (ops.isEmpty) return;
    final jobOf = [for (final op in ops) op.job.jobId];
    final machineCount = [for (final op in ops) op.machines.length];

    final availability0 = Map<int, DateTime>.of(machinesAvailability);
    final usage0 = Map<int, Duration>.of(_machineContinuousUsage);
    final lastJob0 = Map<int, int?>.of(_machineLastJob);
    final lastSequence0 = Map<int, int?>.of(_machineLastSequence);

    void decode(OperationChromosome c, {bool quiet = true}) {
      machinesAvailability
        ..clear()
        ..addAll(availability0);
      _machineContinuousUsage
        ..clear()
        ..addAll(usage0);
      _machineLastJob
        ..clear()
        ..addAll(lastJob0);
      _machineLastSequence
        ..clear()
        ..addAll(lastSequence0);
      output = [];
      final position = <(int, int), int>{};
      for (int i = 0; i < c.order.length; i++) {
        final op = ops[c.order[i]];
        position[(op.job.jobId, op.taskId)] = i;
      }
      final forced = <(int, int), int>{
        for (int i = 0; i < ops.length; i++)
          (ops[i].job.jobId, ops[i].taskId): ops[i].machines[c.machineChoice[i]],
      };
      _schedule(
        (a, b) => position[(a.job.jobId as int, a.taskId as int)]!
            .compareTo(position[(b.job.jobId as int, b.taskId as int)]!),
        forcedMachine: forced,
        quiet: quiet,
      );
    }

    double fitness(OperationChromosome c) {
      try {
        decode(c);
      } on SchedulingHorizonException {
        return double.infinity;
      }
      final done = output.fold<int>(0, (n, o) => n + o.scheduling.length);
      if (done < ops.length || output.isEmpty) return double.infinity;
      final end = output
          .map((o) => o.endTime)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      return end.difference(startDate).inSeconds / 60.0;
    }

    // Seed: operations in the order they were registered, each on its
    // fastest machine.
    final seed = OperationChromosome(
      List<int>.generate(ops.length, (i) => i),
      [
        for (final op in ops)
          () {
            final durations =
                op.job.operations.firstWhere((o) => o.value1 == op.taskId).value2;
            int best = 0;
            for (int k = 1; k < op.machines.length; k++) {
              if (durations[op.machines[k]]! < durations[op.machines[best]]!) {
                best = k;
              }
            }
            return best;
          }(),
      ],
    );

    final result = runGenetic<OperationChromosome>(
      seeds: [seed],
      randomIndividual: (r) => randomOperationChromosome(machineCount, r),
      fitness: fitness,
      crossover: (a, b, r) => poxCrossover(a, b, jobOf, r),
      mutate: (c, r) => operationMutation(c, machineCount, r),
      key: (c) => c.key,
      settings: settings,
    );
    decode(result.best, quiet: false);
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

  // ── Static rules ──────────────────────────────────────────────────────────
  //
  // Applied among the operations that can start (see _schedule), with the
  // operation's NOMINAL attributes as the index: its processing time on the
  // machine chosen for it, the job's due date, or when the operation joined
  // the queue. They used to build the conflict set on the nominal start and
  // let the job rule pick the machine too — LPT sent the operation to its
  // slowest machine. WSPT also divided by the raw minutes, so a zero-minute
  // operation divided by zero.

  void scheduleOpenShopFIFO() => _scheduleBy(DispatchCriterion.fifoArrival);

  void scheduleOpenShopSPT() => _scheduleBy(DispatchCriterion.sptNominal);

  void scheduleOpenShopLPT() => _scheduleBy(DispatchCriterion.lptNominal);

  void scheduleOpenShopEDD() => _scheduleBy(DispatchCriterion.edd);

  void scheduleOpenShopWSPT() => _scheduleBy(DispatchCriterion.wsptNominal);

  void scheduleOpenShopMS() => _scheduleBy(DispatchCriterion.ms);

  // LWR / MWR: nominal work the job still has — this operation plus every
  // operation not yet done (see _remainingWorkAfter). MWR is the classic
  // open-shop heuristic: start first the job with the most work left, so it
  // does not end up last on every machine. The previous MWR counted every
  // other operation of the job, including the ones already done.

  void scheduleOpenShopLWR() => _scheduleBy(DispatchCriterion.lwr);

  void scheduleOpenShopMWR() => _scheduleBy(DispatchCriterion.mwr);

  void scheduleOpenShopCR() => _scheduleBy(DispatchCriterion.cr);

  void scheduleOpenShopATCS() => _scheduleBy(DispatchCriterion.atcs);

  /// Critical ratio used only by the PRIORIDAD_COMPUESTA score, at [now] — the
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

  /// Runs the non-delay loop with one of the shared criteria — static,
  /// LWR/MWR or dynamic; they differ only in the index they read.
  void _scheduleBy(DispatchCriterion criterion) {
    final AtcsParameters? atcs =
        criterion == DispatchCriterion.atcs ? _atcsParameters() : null;
    _schedule(
      (a, b) {
        final int cmp = compareCandidates<OpenShopInput>(
          criterion,
          a.dispatch as DispatchCandidate<OpenShopInput>,
          b.dispatch as DispatchCandidate<OpenShopInput>,
          // The loop only consults the rule among candidates whose
          // EFFECTIVE start coincides, so that is the shared decision time.
          decisionTime:
              (a.dispatch as DispatchCandidate<OpenShopInput>).start,
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
    DateTime arrival,
  ) {
    final placed = _priceOperation(
      job: job,
      taskId: taskId,
      machineId: machineId,
      duration: duration,
      start: at,
    );
    final DateTime end = placed.schedule.completionTime;
    // Effective start: after every interruption the engine had to work
    // around (maintenance, rest cap, waiting for a window that fits a
    // non-interruptible block) — not just the shift-adjusted [at]. The
    // non-delay loop ranks on it, and the span is measured from it.
    final DateTime start = placed.setupSegments.isNotEmpty
        ? placed.setupSegments.first.start
        : placed.schedule.startDate;
    final Duration span = end.difference(start);
    return DispatchCandidate(
      job: job,
      start: start,
      end: end,
      span: span.isNegative ? Duration.zero : span,
      dueDate: job.dueDate,
      releaseDate: job.availableDate,
      priority: job.priority,
      jobId: job.jobId,
      setup: segmentsDuration(placed.setupSegments),
      remainingWork: _remainingWorkAfter(job, taskId, completed),
      processing: duration,
      arrival: arrival,
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
  /// job it ran left it in — or, if nothing has run on it yet, the
  /// machine's configured initial state for this order. Reads machine
  /// state only.
  Duration _setupFor(int machineId, OpenShopInput job) {
    if (stateSetupMatrix == null || jobStates == null) return Duration.zero;
    final int? previousJobId = _machineLastJob[machineId];
    String? previousState;
    if (previousJobId != null && previousJobId > 0) {
      previousState = jobStates![previousJobId]?[machineId];
    } else {
      previousState = initialMachineState[machineId];
    }
    if (previousState == null) return Duration.zero;
    final machineStates = stateSetupMatrix![machineId];
    if (machineStates == null) return Duration.zero;
    final currentState = jobStates![job.dbJobId]?[machineId];
    if (currentState == null) return Duration.zero;
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
    Duration usageAfter,
  }) _priceOperation({
    required OpenShopInput job,
    required int taskId,
    required int machineId,
    required Duration duration,
    required DateTime start,
  }) {
    // Setup then processing through the preemption engine. The task's
    // interruption flag governs the pair: interruptible → each may be split
    // by a shift end / maintenance / rest cap; not interruptible → one
    // contiguous block, processing starting the instant setup ends.
    final placed = _engineFor(machineId).computeSetupAndProcessing(
      earliestStart: start,
      setupDuration: _setupFor(machineId, job),
      processingDuration: duration,
      priorContinuousUsage:
          _machineContinuousUsage[machineId] ?? Duration.zero,
      interruptible: job.isTaskInterruptible(taskId),
    );

    return (
      setupSegments: placed.setupSegments,
      schedule: placed.processing,
      usageAfter: placed.continuousUsageAfter,
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
  /// Every contender — for every rule — is priced through the preemption
  /// engine on each of its eligible machines and carried as `dispatch`, so
  /// the conflict set is built on EFFECTIVE starts and the machine is chosen
  /// by earliest completion before the rule picks the operation (see
  /// nonDelayConflictSet).
  ///
  /// A job WITHOUT precedences is a true open-shop job: its operations can be
  /// done in any order, but the job is on one machine at a time. A job WITH
  /// precedences (an order that mixes both kinds) follows its graph, and is
  /// also on one machine at a time: a job is one physical piece.
  ///
  /// [forcedMachine] (job id, task id) → machine restricts each operation to
  /// one machine (the genetic algorithm's assignment gene); [quiet] silences
  /// the progress logs during the GA's many decodings.
  void _schedule(
    int Function(dynamic, dynamic) comparator, {
    Map<(int, int), int>? forcedMachine,
    bool quiet = false,
  }) {
    if (!quiet) {
      print(
          'OpenShop._schedule: entering main loop for ${inputJobs.length} jobs');
    }
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
        // Open shop: any operation not yet done may go next. It used to
        // wait for the operation listed before it, which imposed the order
        // the tasks were created in — a flow shop, not an open shop.
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
        // One machine at a time: free once its last operation ends.
        return jobAvailability[job.jobId] ?? job.availableDate;
      } else {
        // Its arrows, AND one machine at a time: a job is one physical
        // piece, so operations with no arrow between them still cannot
        // overlap.
        DateTime readyTime = jobAvailability[job.jobId] ?? job.availableDate;
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
      if (!quiet && iter % 10000 == 0) {
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
            DispatchCandidate<OpenShopInput> dispatch
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
          final int? onlyMachine = forcedMachine?[(job.jobId, taskId)];
          for (var entry in operation.value2.entries) {
            final machineId = entry.key;
            if (onlyMachine != null && machineId != onlyMachine) continue;
            final duration = entry.value;
            final machineAvailable =
                machinesAvailability[machineId] ?? startDate;
            final jobAvail = jobReadyTime;

            final earliestStart = machineAvailable.isAfter(jobAvail)
                ? machineAvailable
                : jobAvail;
            final adjustedStart = _adjustForWorkingSchedule(earliestStart);

            // What the operation really costs from here, priced through
            // the same code that commits it. One impossible machine must
            // not sink the operation's other options, so a failure only
            // drops this candidate.
            final DispatchCandidate<OpenShopInput> dispatch;
            try {
              dispatch = _dispatchCandidate(job, taskId, machineId, duration,
                  adjustedStart, completed, jobAvail);
            } on SchedulingHorizonException catch (e) {
              pricingFailure ??= e;
              continue;
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

      // Non-delay on the EFFECTIVE start (after changeover waits,
      // maintenance, rest caps and non-interruptible waits); if nothing can
      // start at the current instant, the clock effectively jumps to the
      // earliest effective start (Giffler & Thompson 1960, non-delay).
      //
      // Two decisions, kept apart (see nonDelayConflictSet): each operation
      // that can start at t* first gets its machine — earliest completion
      // among its machines available at t*, then cheapest changeover, then
      // lowest id — and only then does the rule choose among operations.
      final contenders = nonDelayConflictSet(
        candidates,
        operationKey: (c) => (c.job.jobId, c.taskId),
        candidate: (c) => c.dispatch,
        machineId: (c) => c.machineId,
      );
      contenders.sort(comparator);

      // Seleccionar el mejor candidato
      final selected = contenders.first;
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
      // A job with no state (A-J) registered for this machine leaves the
      // machine in the state it found it. Recording it as the last job
      // anyway made the NEXT changeover look up a null state and cost zero.
      if (jobStates == null ||
          jobStates![selected.job.dbJobId]?[selected.machineId] != null) {
        _machineLastJob[selected.machineId] = selected.job.dbJobId;
      }
      _machineContinuousUsage[selected.machineId] = placed.usageAfter;
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

  final initialMachineState = payload['initialMachineState'] == null
      ? const <int, String>{}
      : (payload['initialMachineState'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as String));

  final output = OpenShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
    initialMachineState: initialMachineState,
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
