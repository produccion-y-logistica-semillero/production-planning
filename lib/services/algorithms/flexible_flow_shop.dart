import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class FlexibleFlowInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  //tuple2 <task id, Map<machineId, Duration of task in machine>>
  final List<Tuple2<int, Map<int, Duration>>> taskSequence;

  /// Whether each task (keyed by task id) may be split by a work-shift
  /// boundary, the continuous-use rest cap, or a maintenance window.
  /// Missing entries default to interruptible.
  final Map<int, bool> interruptibleByTask;

  FlexibleFlowInput(this.jobId, this.dueDate, this.priority, this.availableDate,
      this.taskSequence,
      {this.interruptibleByTask = const {}});

  bool isTaskInterruptible(int taskId) => interruptibleByTask[taskId] ?? true;
}

class FlexibleFlowOutput {
  final int jobId;
  final DateTime dueDate;
  final DateTime startDate;
  final DateTime endTime;
  //map<task id, tuple2<machineId, range scheuled>>
  final Map<int, Tuple2<int, Range>> scheduling;

  /// Processing segments per station (stationId → segments), for tasks that
  /// were preempted mid-processing.
  final Map<int, List<ProcessingSegment>> segmentsByStation;

  /// Setup/changeover segments per station (stationId → segments), if any.
  final Map<int, List<ProcessingSegment>> setupSegmentsByStation;

  FlexibleFlowOutput(
      this.jobId, this.dueDate, this.startDate, this.endTime, this.scheduling,
      {Map<int, List<ProcessingSegment>>? segmentsByStation,
      this.setupSegmentsByStation = const {}})
      : segmentsByStation = segmentsByStation ??
            scheduling.map((stationId, entry) => MapEntry(
                stationId,
                [ProcessingSegment(entry.value2.start, entry.value2.end)]));
}

/// One task priced on one machine, not yet committed.
class _FlexibleFlowTask {
  final int machineId;
  final List<ProcessingSegment> setupSegments;
  final SegmentedSchedule schedule;

  /// The machine's continuous-use streak once this task is done.
  final Duration continuousUsageAfter;

  const _FlexibleFlowTask({
    required this.machineId,
    required this.setupSegments,
    required this.schedule,
    required this.continuousUsageAfter,
  });

  /// When the machine starts working: setup if there is one, else processing.
  DateTime get start =>
      setupSegments.isNotEmpty ? setupSegments.first.start : schedule.startDate;
}

/// A whole job's route through the stations, priced but not committed.
///
/// The two `*After` maps hold the per-machine state the route would leave
/// behind, applied only by `FlexibleFlowShop._commitPlacement`.
class _FlexibleFlowPlacement {
  final FlexibleFlowInput job;
  final DateTime startTime;
  final DateTime endTime;
  final Map<int, Tuple2<int, Range>> scheduling;
  final Map<int, List<ProcessingSegment>> segmentsByStation;
  final Map<int, List<ProcessingSegment>> setupSegmentsByStation;
  final Map<int, DateTime> availabilityAfter;
  final Map<int, Duration> continuousUsageAfter;

  const _FlexibleFlowPlacement({
    required this.job,
    required this.startTime,
    required this.endTime,
    required this.scheduling,
    required this.segmentsByStation,
    required this.setupSegmentsByStation,
    required this.availabilityAfter,
    required this.continuousUsageAfter,
  });
}

class FlexibleFlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<FlexibleFlowInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability;
  List<FlexibleFlowOutput> output = [];
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;

  /// machineId → state letter (A-J) the machine starts this order in,
  /// before its first job.
  final Map<int, String> initialMachineState;
  final Map<int, int?> _machineLastJob = {};

  // Machine inactivity support.
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count.
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;

  /// How long each machine has run continuously since its last pause.
  final Map<int, Duration> _machineContinuousUsage = {};
  final Map<int, PreemptionEngine> _engineByMachine = {};

  FlexibleFlowShop(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machinesAvailability,
    String rule, {
    this.stateSetupMatrix,
    this.jobStates,
    this.initialMachineState = const {},
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
  }) {
    final r = rule.toUpperCase();
    switch (r) {
      case "EDD":
        eddRule();
        break;
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "FIFO":
        fifoRule();
        break;
      case "WSPT":
        wsptRule();
        break;
      case "EDD_ADAPTADO":
        eddaRule();
        break;
      case "SPT_ADAPTADO":
        sptaRule();
        break;
      case "LPT_ADAPTADO":
        lptaRule();
        break;
      case "FIFO_ADAPTADO":
        fifoaRule();
        break;
      case "WSPT_ADAPTADO":
        wsptaRule();
        break;
      case "MS":
        msRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "JOHNSON":
        _applyJohnsonRuleFlexible(inputJobs);
        break;

      case "CDS":
        cdsAlgorithm();
        break;
      case "GENETICS":
        // Fallback genetics: order by combined score
        _schedule((a, b) {
          final scoreA = (a.priority / max(1, _totalProcessingTime(a))) + (1 / max(1, _totalProcessingTime(a)));
          final scoreB = (b.priority / max(1, _totalProcessingTime(b))) + (1 / max(1, _totalProcessingTime(b)));
          return scoreB.compareTo(scoreA);
        });
        break;
      case "MINSLACK":
        // The DB grants MINSLACK to some environments and MS to others; they
        // are the same rule. Accepting both keeps a granted rule from
        // silently producing an empty schedule.
        msRule();
        break;
      default:
        throw ArgumentError('Regla de despacho desconocida: "$rule"');
    }
  }

  void eddRule() => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptRule() => _schedule(
        (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)),
      );
  void lptRule() => _schedule(
        (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)),
      );
  void fifoRule() =>
      _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptRule() => _schedule((a, b) {
        double wsptA = a.priority / max(1, _totalProcessingTime(a));
        double wsptB = b.priority / max(1, _totalProcessingTime(b));
        return wsptB.compareTo(wsptA);
      });

  void _schedule(
      int Function(FlexibleFlowInput, FlexibleFlowInput) comparator) {

    inputJobs.sort(comparator);
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

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

  void _assignJobToMachines(FlexibleFlowInput job) {
    _commitPlacement(_simulateJob(job, notBefore: null));
  }

  /// Schedules ONE task of [jobId] on [machineId], setup then processing,
  /// without writing anything.
  ///
  /// This is the single definition of what a task costs on a machine. Both
  /// [_selectBestMachine] and [_simulateJob] go through it, which is what
  /// keeps the machine chosen and the machine scheduled in agreement — they
  /// used to disagree, because selection priced setup+processing as one
  /// combined block while assignment scheduled them as two separate ones. A
  /// boundary falling between the two, or an uninterruptible task, made the
  /// combined estimate longer than reality and could hand the task to the
  /// wrong machine.
  _FlexibleFlowTask _scheduleTaskOn({
    required int machineId,
    required int jobId,
    required DateTime earliestStart,
    required Duration processingTime,
    required bool interruptible,
  }) {
    final DateTime machineFree = machinesAvailability[machineId] ?? startDate;
    DateTime startTime =
        earliestStart.isAfter(machineFree) ? earliestStart : machineFree;
    startTime = _adjustForWorkingSchedule(startTime);

    final Duration setupDuration = _getSetupDuration(
      machineId,
      jobId,
      _machineLastJob[machineId],
    );

    // Schedule setup as its own segmented block (through the preemption
    // engine, so it's just as sensitive to work-shift/rest/maintenance
    // boundaries as processing is), then start processing right after.
    List<ProcessingSegment> setupSegments = const [];
    DateTime processStart = startTime;
    Duration continuousUsage =
        _machineContinuousUsage[machineId] ?? Duration.zero;
    if (setupDuration > Duration.zero) {
      final setupSchedule = _engineFor(machineId).computeSegments(
        earliestStart: startTime,
        totalDuration: setupDuration,
        priorContinuousUsage: continuousUsage,
      );
      setupSegments = setupSchedule.segments;
      processStart = setupSchedule.completionTime;
      continuousUsage = setupSegments.length > 1
          ? setupSegments.last.duration
          : continuousUsage + setupSegments.single.duration;
    }

    // Split processing into segments wherever the work-shift end, a
    // maintenance window, or the continuous-use rest cap would otherwise
    // fall inside this task's span on this machine.
    final schedule = _engineFor(machineId).computeSegments(
      earliestStart: processStart,
      totalDuration: processingTime,
      priorContinuousUsage: continuousUsage,
      interruptible: interruptible,
    );

    return _FlexibleFlowTask(
      machineId: machineId,
      setupSegments: setupSegments,
      schedule: schedule,
      continuousUsageAfter: schedule.segments.length > 1
          ? schedule.segments.last.duration
          : continuousUsage + schedule.segments.single.duration,
    );
  }

  /// Walks [job] through every station and returns the placement WITHOUT
  /// committing it — no field is written, so contenders can be priced and
  /// discarded. [_commitPlacement] does the writing.
  _FlexibleFlowPlacement _simulateJob(
    FlexibleFlowInput job, {
    DateTime? notBefore,
  }) {
    DateTime jobStartTime = job.availableDate;
    if (notBefore != null && notBefore.isAfter(jobStartTime)) {
      jobStartTime = notBefore;
    }
    DateTime? actualStartTime;
    DateTime? finalEndTime;

    Map<int, Tuple2<int, Range>> scheduling = {};
    Map<int, List<ProcessingSegment>> segmentsByStation = {};
    Map<int, List<ProcessingSegment>> setupSegmentsByStation = {};
    Map<int, DateTime> availabilityAfter = {};
    Map<int, Duration> continuousUsageAfter = {};

    for (var task in job.taskSequence) {
      int stationId = task.value1;
      Map<int, Duration> machinesInStation = task.value2;

      final bool taskInterruptible = job.isTaskInterruptible(stationId);
      final int machineId = _selectBestMachine(
        machinesInStation,
        job.jobId,
        jobStartTime,
        taskInterruptible,
      );

      final placed = _scheduleTaskOn(
        machineId: machineId,
        jobId: job.jobId,
        earliestStart: jobStartTime,
        processingTime: machinesInStation[machineId]!,
        interruptible: taskInterruptible,
      );

      final DateTime taskStart = placed.schedule.startDate;
      final DateTime endTime = placed.schedule.completionTime;

      // Guarda el primer tiempo real de inicio
      actualStartTime ??= placed.start;
      // Guarda el último tiempo de finalización
      finalEndTime = endTime;

      scheduling[stationId] = Tuple2(machineId, Range(taskStart, endTime));
      segmentsByStation[stationId] = placed.schedule.segments;
      setupSegmentsByStation[stationId] = placed.setupSegments;
      availabilityAfter[machineId] = endTime;
      continuousUsageAfter[machineId] = placed.continuousUsageAfter;

      jobStartTime = endTime;
    }

    return _FlexibleFlowPlacement(
      job: job,
      startTime: actualStartTime ?? jobStartTime,
      endTime: finalEndTime ?? jobStartTime,
      scheduling: scheduling,
      segmentsByStation: segmentsByStation,
      setupSegmentsByStation: setupSegmentsByStation,
      availabilityAfter: availabilityAfter,
      continuousUsageAfter: continuousUsageAfter,
    );
  }

  /// Applies a placement produced by [_simulateJob] to the real schedule.
  void _commitPlacement(_FlexibleFlowPlacement placement) {
    final job = placement.job;

    placement.availabilityAfter.forEach((machineId, endTime) {
      machinesAvailability[machineId] = endTime;
      _machineLastJob[machineId] = job.jobId;
    });
    placement.continuousUsageAfter.forEach((machineId, usage) {
      _machineContinuousUsage[machineId] = usage;
    });

    output.add(FlexibleFlowOutput(
      job.jobId,
      job.dueDate,
      placement.startTime,
      placement.endTime,
      placement.scheduling,
      segmentsByStation: placement.segmentsByStation,
      setupSegmentsByStation: placement.setupSegmentsByStation,
    ));
  }


  /// Picks the machine in a station that finishes the task soonest.
  ///
  /// Prices every option through [_scheduleTaskOn] — the same code path the
  /// task is actually scheduled with — so the machine chosen here is the one
  /// that really is fastest, setup and preemptions included.
  int _selectBestMachine(
    Map<int, Duration> machinesInStation,
    int jobId,
    DateTime jobStartTime,
    bool taskInterruptible,
  ) {
    int bestMachineId = -1;
    DateTime bestEndTime = DateTime(9999);
    DateTime bestStartTime = DateTime(9999);

    for (var entry in machinesInStation.entries) {
      final machineId = entry.key;

      final placed = _scheduleTaskOn(
        machineId: machineId,
        jobId: jobId,
        earliestStart: jobStartTime,
        processingTime: entry.value,
        interruptible: taskInterruptible,
      );
      final DateTime taskStart = placed.start;
      final DateTime endTime = placed.schedule.completionTime;

      // Earliest finish wins; ties go to the earliest start, then to the
      // lowest machine id so the choice is deterministic.
      if (bestMachineId == -1 ||
          endTime.isBefore(bestEndTime) ||
          (endTime.isAtSameMomentAs(bestEndTime) &&
              taskStart.isBefore(bestStartTime)) ||
          (endTime.isAtSameMomentAs(bestEndTime) &&
              taskStart.isAtSameMomentAs(bestStartTime) &&
              machineId < bestMachineId)) {
        bestMachineId = machineId;
        bestEndTime = endTime;
        bestStartTime = taskStart;
      }
    }

    return bestMachineId;
  }

  int _totalProcessingTime(FlexibleFlowInput job) {
    int totalProcessingTime = 0;
    for (var task in job.taskSequence) {
      Map<int, Duration> machineTimes = task.value2;
      int averageProcessingTime = machineTimes.values
              .fold(Duration.zero, (sum, time) => sum + time)
              .inMinutes ~/
          machineTimes.length;
      totalProcessingTime += averageProcessingTime;
    }
    return totalProcessingTime;
  }

  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;


    if (start.hour < workingStart.hour ||
        (start.hour == workingStart.hour &&
            start.minute < workingStart.minute)) {

      return DateTime(
        start.year,
        start.month,
        start.day,
        workingStart.hour,
        workingStart.minute,
      );

    } else if (start.hour > workingEnd.hour ||
        (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {

      return DateTime(
        start.year,
        start.month,
        start.day + 1,
        workingStart.hour,
        workingStart.minute,
      );
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, DateTime end) {
    TimeOfDay workingEnd = workingSchedule.value2;
    DateTime endOfDay = DateTime(
      start.year,
      start.month,
      start.day,
      workingEnd.hour,
      workingEnd.minute,
    );

    if (end.isAfter(endOfDay)) {
      Duration remainingTime = end.difference(endOfDay);
      return DateTime(
        start.year,
        start.month,
        start.day + 1,
        workingSchedule.value1.hour,
        workingSchedule.value1.minute,
      ).add(remainingTime);
    }
    return end;
  }

  Duration _getSetupDuration(
    int machineId,
    int currentJobId,
    int? previousJobId,
  ) {
    // With no previous job on this machine yet, fall back to the machine's
    // configured initial state for this order.
    if (stateSetupMatrix != null && jobStates != null) {
      final machineStates = stateSetupMatrix![machineId];
      if (machineStates != null) {
        String? previousState;
        if (previousJobId != null && previousJobId > 0) {
          previousState = jobStates![previousJobId]?[machineId];
        } else {
          previousState = initialMachineState[machineId];
        }
        final currentState = jobStates![currentJobId]?[machineId];
        if (previousState != null && currentState != null) {
          final setupMinutes = machineStates[previousState]?[currentState];
          if (setupMinutes != null) {
            return Duration(minutes: setupMinutes);
          }
        }
      }
    }
    return Duration.zero;
  }

  // ── Dynamic (*_ADAPTADO) rules ────────────────────────────────────────────
  //
  // `_dynamicSchedule` re-sorted the pending list on every iteration, but the
  // comparators it received read only immutable job fields — so the order
  // never changed and these produced the same schedule as the static rules.
  // They now compare each contender's effective route span at the decision
  // point: see _runDynamic.

  void eddaRule() => _runDynamicStagewise(DispatchCriterion.edd);
  void sptaRule() => _runDynamicStagewise(DispatchCriterion.spt);
  void lptaRule() => _runDynamicStagewise(DispatchCriterion.lpt);
  void fifoaRule() => _runDynamicStagewise(DispatchCriterion.fifo);
  void wsptaRule() => _runDynamicStagewise(DispatchCriterion.wspt);

  // MS, CR and ATCS are dynamic by definition — their index depends on the
  // clock t — so they run through the same event-driven dispatch as the
  // *_ADAPTADO rules.
  void msRule() => _runDynamicStagewise(DispatchCriterion.ms);
  void crRule() => _runDynamicStagewise(DispatchCriterion.cr);
  void atcRule() => _runDynamicStagewise(DispatchCriterion.atcs);

  /// Stage-by-stage event-driven dispatch for the *_ADAPTADO rules and
  /// MS/CR/ATCS in a (flexible) hybrid flow shop.
  ///
  /// Earlier this priced and ranked whole ROUTES (see the removed
  /// `_runDynamic`): at every decision it simulated each pending job clear
  /// through every remaining station and picked the one with the best
  /// route-level index. That matches a strict permutation flow shop, where
  /// one machine per stage keeps a single global order — but a station with
  /// several parallel machines does not keep one order at all, so ranking
  /// whole routes does not match how the shop actually queues work at each
  /// station. The standard treatment of a hybrid/flexible flow shop in the
  /// literature dispatches at EACH station, among the jobs actually queued
  /// there (Ruiz & Vázquez-Rodríguez 2010; Pinedo, *Scheduling*, ch. 4 on
  /// hybrid flow shops) — the same operation-level treatment Open Shop and
  /// Flexible Job Shop already use in this codebase.
  ///
  /// One non-delay loop drives every station at once, mirroring
  /// `OpenShop._schedule`: each round collects the (job, machine) pairings
  /// whose job is ready at that job's CURRENT station (its route order is
  /// still fixed — only the ranking is per-station now), prices every one of
  /// them through [_scheduleTaskOn], and commits the pairing that can start
  /// earliest — ties broken by the dispatch rule. `remainingWork`, which
  /// MS/CR/ATCS charge against the due date, is the job's own nominal time
  /// over the stations still ahead of it (mirrors Vepsäläinen & Morton 1987's
  /// use of remaining work in slack-based indices).
  void _runDynamicStagewise(DispatchCriterion criterion) {
    if (inputJobs.isEmpty) return;

    final AtcsParameters? atcs =
        criterion == DispatchCriterion.atcs ? _atcsParametersStagewise() : null;

    final Map<int, int> stageIndex = {
      for (final job in inputJobs) job.jobId: 0,
    };
    final Map<int, DateTime> jobReadyAt = {
      for (final job in inputJobs) job.jobId: job.availableDate,
    };
    final Map<int, Map<int, Tuple2<int, Range>>> jobScheduling = {
      for (final job in inputJobs) job.jobId: {},
    };
    final Map<int, Map<int, List<ProcessingSegment>>> jobSegments = {
      for (final job in inputJobs) job.jobId: {},
    };
    final Map<int, Map<int, List<ProcessingSegment>>> jobSetupSegments = {
      for (final job in inputJobs) job.jobId: {},
    };
    final Map<int, DateTime> jobActualStart = {};

    bool isActive(FlexibleFlowInput job) =>
        stageIndex[job.jobId]! < job.taskSequence.length;

    while (inputJobs.any(isActive)) {
      final candidates = <({
        FlexibleFlowInput job,
        int stationId,
        int machineId,
        DateTime earliestStart,
        _FlexibleFlowTask placed,
        DispatchCandidate<FlexibleFlowInput> dispatch,
      })>[];
      SchedulingHorizonException? pricingFailure;

      for (final job in inputJobs) {
        if (!isActive(job)) continue;
        final int stage = stageIndex[job.jobId]!;
        final task = job.taskSequence[stage];
        final int stationId = task.value1;
        final Map<int, Duration> machines = task.value2;
        final bool interruptible = job.isTaskInterruptible(stationId);
        final DateTime ready = jobReadyAt[job.jobId]!;

        for (final entry in machines.entries) {
          final machineId = entry.key;
          final DateTime machineFree =
              machinesAvailability[machineId] ?? startDate;
          final DateTime earliestStart = _adjustForWorkingSchedule(
              ready.isAfter(machineFree) ? ready : machineFree);

          final _FlexibleFlowTask placed;
          try {
            placed = _scheduleTaskOn(
              machineId: machineId,
              jobId: job.jobId,
              earliestStart: earliestStart,
              processingTime: entry.value,
              interruptible: interruptible,
            );
          } on SchedulingHorizonException catch (e) {
            pricingFailure ??= e;
            continue;
          }

          final DateTime end = placed.schedule.completionTime;
          final Duration span = end.difference(earliestStart);
          candidates.add((
            job: job,
            stationId: stationId,
            machineId: machineId,
            earliestStart: earliestStart,
            placed: placed,
            dispatch: DispatchCandidate(
              job: job,
              start: placed.start,
              end: end,
              span: span.isNegative ? Duration.zero : span,
              dueDate: job.dueDate,
              releaseDate: job.availableDate,
              priority: job.priority,
              jobId: job.jobId,
              setup: segmentsDuration(placed.setupSegments),
              remainingWork: _remainingWorkAfterStage(job, stage),
            ),
          ));
        }
      }

      if (candidates.isEmpty) {
        // Every ready operation was unplaceable on every candidate machine:
        // that is the calendar's fault, and the user has to hear about it.
        if (pricingFailure != null) throw pricingFailure;
        break;
      }

      // Non-delay: the pairing that can start soonest goes first; the
      // dispatch rule only breaks ties among pairings tied on start time,
      // same as OpenShop._schedule.
      candidates.sort((a, b) {
        final cmpStart = a.earliestStart.compareTo(b.earliestStart);
        if (cmpStart != 0) return cmpStart;
        final cmp = compareCandidates<FlexibleFlowInput>(
          criterion,
          a.dispatch,
          b.dispatch,
          decisionTime: a.earliestStart,
          atcs: atcs,
        );
        if (cmp != 0) return cmp;
        if (a.stationId != b.stationId) {
          return a.stationId.compareTo(b.stationId);
        }
        return a.machineId.compareTo(b.machineId);
      });

      final selected = candidates.first;
      final job = selected.job;
      final placed = selected.placed;
      final DateTime taskStart = placed.schedule.startDate;
      final DateTime end = placed.schedule.completionTime;

      jobActualStart.putIfAbsent(job.jobId, () => placed.start);
      jobScheduling[job.jobId]![selected.stationId] =
          Tuple2(selected.machineId, Range(taskStart, end));
      jobSegments[job.jobId]![selected.stationId] = placed.schedule.segments;
      jobSetupSegments[job.jobId]![selected.stationId] = placed.setupSegments;

      machinesAvailability[selected.machineId] = end;
      _machineLastJob[selected.machineId] = job.jobId;
      _machineContinuousUsage[selected.machineId] = placed.continuousUsageAfter;

      stageIndex[job.jobId] = stageIndex[job.jobId]! + 1;
      jobReadyAt[job.jobId] = end;

      // Append the moment the job finishes its LAST station, so `output`
      // reflects the order jobs actually finish in — same convention the
      // static rules and the old route-level dispatch both kept (and what
      // callers like the Gantt adapter and these tests read as "the
      // schedule's order"). Building it from `inputJobs` at the very end,
      // as this used to, always produced the ORIGINAL input order — it
      // silently discarded every dispatch decision the loop just made.
      if (stageIndex[job.jobId] == job.taskSequence.length) {
        output.add(FlexibleFlowOutput(
          job.jobId,
          job.dueDate,
          jobActualStart[job.jobId] ?? job.availableDate,
          end,
          Map<int, Tuple2<int, Range>>.from(jobScheduling[job.jobId]!),
          segmentsByStation:
              Map<int, List<ProcessingSegment>>.from(jobSegments[job.jobId]!),
          setupSegmentsByStation: Map<int, List<ProcessingSegment>>.from(
              jobSetupSegments[job.jobId]!),
        ));
      }
    }
  }

  /// Nominal work [job] still has after stage [currentStageIndex]: every
  /// later station's mean duration over its candidate machines. Mirrors
  /// OpenShop._remainingWorkAfter.
  Duration _remainingWorkAfterStage(
      FlexibleFlowInput job, int currentStageIndex) {
    Duration total = Duration.zero;
    for (int i = currentStageIndex + 1; i < job.taskSequence.length; i++) {
      final machines = job.taskSequence[i].value2;
      if (machines.isEmpty) continue;
      total +=
          machines.values.fold(Duration.zero, (sum, d) => sum + d) ~/
              machines.length;
    }
    return total;
  }

  /// Fits the ATCS parameters to this instance (see
  /// [AtcsParameters.calibrate]) for the STAGE-WISE dispatcher: a candidate
  /// here is one operation (one job at one station), so p̄ and s̄ must be
  /// per-operation — mirrors OpenShop._atcsParameters.
  AtcsParameters _atcsParametersStagewise() {
    double totalProcessing = 0;
    int operationCount = 0;
    final Map<int, double> stationLoad = {};
    final Set<int> allMachineIds = {};

    for (final job in inputJobs) {
      for (final task in job.taskSequence) {
        final machines = task.value2;
        if (machines.isEmpty) continue;
        final double mean = machines.values
                .fold<double>(0, (sum, d) => sum + d.inSeconds / 60.0) /
            machines.length;
        totalProcessing += mean;
        operationCount++;
        // A station of k machines works through its queue k times faster.
        stationLoad[task.value1] =
            (stationLoad[task.value1] ?? 0) + mean / machines.length;
        allMachineIds.addAll(machines.keys);
      }
    }
    final double meanProcessing =
        operationCount == 0 ? 1 : totalProcessing / operationCount;

    // Mean pairwise changeover, at the OPERATION level: over every machine
    // that appears in some station, and every ordered pair of distinct jobs
    // that both have a state on it.
    double setupTotal = 0;
    int setupCount = 0;
    if (stateSetupMatrix != null && jobStates != null) {
      for (final machineId in allMachineIds) {
        final matrix = stateSetupMatrix![machineId];
        if (matrix == null) continue;
        for (final from in inputJobs) {
          final fromState = jobStates![from.jobId]?[machineId];
          if (fromState == null) continue;
          for (final to in inputJobs) {
            if (identical(from, to)) continue;
            final toState = jobStates![to.jobId]?[machineId];
            final minutes =
                toState == null ? null : matrix[fromState]?[toState];
            if (minutes == null) continue;
            setupTotal += minutes;
            setupCount++;
          }
        }
      }
    }
    final double meanSetup = setupCount == 0 ? 0 : setupTotal / setupCount;

    final double bottleneck =
        stationLoad.values.fold(0.0, (a, b) => max(a, b));
    final int stationCount = max(stationLoad.length, 1);
    final double workMinutes =
        bottleneck + operationCount * meanSetup / stationCount;

    return AtcsParameters.calibrate(
      start: startDate,
      dueDates: inputJobs.map((job) => job.dueDate),
      meanProcessingMinutes: meanProcessing,
      meanSetupMinutes: meanSetup,
      makespanMinutes: calendarMinutes(
        PreemptionEngine(workingSchedule: workingSchedule),
        startDate,
        Duration(minutes: workMinutes.round()),
      ),
    );
  }

  void cdsAlgorithm() {
    if (inputJobs.isEmpty) return;

    int numStations = inputJobs.first.taskSequence.length;

    if (numStations == 2) {
      _applyJohnsonRuleFlexible(inputJobs);
      return;
    }

    List<FlexibleFlowInput> bestSequence = [];
    int bestMakespan = double.maxFinite.toInt();

    for (int k = 1; k < numStations; k++) {
      List<FlexibleFlowInput> tempJobs = inputJobs.map((job) {
        Duration sumA = Duration.zero;
        Duration sumB = Duration.zero;

        for (int i = 0; i < k; i++) {
          Map<int, Duration> machineDurations = job.taskSequence[i].value2;
          sumA += _averageProcessingTime(machineDurations);
        }

        for (int i = k; i < numStations; i++) {
          Map<int, Duration> machineDurations = job.taskSequence[i].value2;
          sumB += _averageProcessingTime(machineDurations);
        }

        return FlexibleFlowInput(
          job.jobId,
          job.dueDate,
          job.priority,
          job.availableDate,
          [
            Tuple2(0, {0: sumA}),
            Tuple2(1, {1: sumB}),
          ],
        );
      }).toList();


      List<FlexibleFlowInput> ordered =
          _getJohnsonOrderedJobsFlexible(tempJobs);

      List<int> orderedIds = ordered.map((e) => e.jobId).toList();

      List<FlexibleFlowInput> orderedOriginal = orderedIds
          .map((id) => inputJobs.firstWhere((job) => job.jobId == id))
          .toList();

      int makespan = _calculateMakespanFlexible(orderedOriginal);

      if (makespan < bestMakespan) {
        bestMakespan = makespan;
        bestSequence = orderedOriginal;
      }
    }

    inputJobs = bestSequence;
    _schedule((a, b) => 0); // Puedes usar una regla dummy o alguna prioridad
    print("Optimal sequence: ${bestSequence.map((job) => job.jobId).toList()}");
    print("Optimal makespan: $bestMakespan");
  }

  void _applyJohnsonRuleFlexible(List<FlexibleFlowInput> jobs) {
    List<FlexibleFlowInput> groupI = [];
    List<FlexibleFlowInput> groupII = [];

    for (var job in jobs) {
      Duration a = job.taskSequence[0].value2.values.first;
      Duration b = job.taskSequence[1].value2.values.first;

      if (a <= b) {
        groupI.add(job);
      } else {
        groupII.add(job);
      }
    }


    groupI.sort((a, b) => a.taskSequence[0].value2.values.first
        .compareTo(b.taskSequence[0].value2.values.first));
    groupII.sort((a, b) => b.taskSequence[1].value2.values.first
        .compareTo(a.taskSequence[1].value2.values.first));


    inputJobs = [...groupI, ...groupII];
    _schedule((a, b) => 0);
  }

  Duration _averageProcessingTime(Map<int, Duration> times) {
    if (times.isEmpty) return Duration.zero;
    int totalMs = times.values.fold(0, (sum, d) => sum + d.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ times.length);
  }


  List<FlexibleFlowInput> _getJohnsonOrderedJobsFlexible(
      List<FlexibleFlowInput> jobs) {
    List<FlexibleFlowInput> groupI = [];
    List<FlexibleFlowInput> groupII = [];

    for (var job in jobs) {
      Duration a = job.taskSequence[0].value2[0]!;
      Duration b = job.taskSequence[1].value2[1]!;

      if (a <= b) {
        groupI.add(job);
      } else {
        groupII.add(job);
      }
    }


    groupI.sort((a, b) =>
        a.taskSequence[0].value2[0]!.compareTo(b.taskSequence[0].value2[0]!));
    groupII.sort((a, b) =>
        b.taskSequence[1].value2[1]!.compareTo(a.taskSequence[1].value2[1]!));


    return [...groupI, ...groupII];
  }

  int _calculateMakespanFlexible(List<FlexibleFlowInput> jobSequence) {
    // Disponibilidad actual de cada máquina en cada estación
    Map<int, Map<int, DateTime>> stationMachineAvailability = {};

    // Inicializa todas las máquinas como disponibles desde el inicio
    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        int stationId = task.value1;
        for (var machineId in task.value2.keys) {
          stationMachineAvailability.putIfAbsent(stationId, () => {});
          stationMachineAvailability[stationId]![machineId] = startDate;
        }
      }
    }

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int stationId = task.value1;
        Map<int, Duration> machineOptions = task.value2;

        // Elegimos la máquina más disponible con menor tiempo de procesamiento
        int selectedMachineId = -1;
        DateTime earliestStart = DateTime(9999);
        Duration selectedDuration = Duration.zero;

        for (var entry in machineOptions.entries) {
          int machineId = entry.key;
          Duration duration = entry.value;

          DateTime machineAvailable =
              stationMachineAvailability[stationId]?[machineId] ?? startDate;

          DateTime tentativeStart = jobStartTime.isAfter(machineAvailable)
              ? jobStartTime
              : machineAvailable;

          tentativeStart = _adjustForWorkingSchedule(tentativeStart);
          DateTime tentativeEnd = tentativeStart.add(duration);
          tentativeEnd =
              _adjustEndTimeForWorkingSchedule(tentativeStart, tentativeEnd);


          if (tentativeEnd.isBefore(earliestStart)) {
            earliestStart = tentativeEnd;
            selectedMachineId = machineId;
            selectedDuration = duration;
          }
        }

        // Programamos el trabajo en la máquina seleccionada
        DateTime machineAvailable =
            stationMachineAvailability[stationId]![selectedMachineId]!;
        DateTime startTime = jobStartTime.isAfter(machineAvailable)
            ? jobStartTime
            : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);
        DateTime endTime = startTime.add(selectedDuration);
        endTime = _adjustEndTimeForWorkingSchedule(startTime, endTime);

        // Actualizamos disponibilidad
        stationMachineAvailability[stationId]![selectedMachineId] = endTime;
        jobStartTime = endTime; // Para la próxima estación

        // Actualizar el tiempo final global si es mayor
        if (endTime.isAfter(makespanEndTime)) {
          makespanEndTime = endTime;
        }
      }
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }

List<Map<String, dynamic>> flexibleFlowShopSchedule(Map<String, dynamic> payload) {
  final startDate = DateTime.fromMillisecondsSinceEpoch(payload['startDate'] as int);
  final workingSchedule = Tuple2(
    TimeOfDay(hour: payload['workingStartHour'] as int, minute: payload['workingStartMinute'] as int),
    TimeOfDay(hour: payload['workingEndHour'] as int, minute: payload['workingEndMinute'] as int),
  );

  final inputJobs = (payload['inputJobs'] as List<dynamic>).map((jobData) {
    final jobMap = Map<String, dynamic>.from(jobData as Map);
    final taskSequence = (jobMap['taskSequence'] as List<dynamic>).map((taskData) {
      final taskMap = Map<String, dynamic>.from(taskData as Map);
      final machineDurations = (taskMap['machineDurations'] as Map<dynamic, dynamic>).map(
        (key, value) => MapEntry(key as int, Duration(milliseconds: value as int)),
      );
      return Tuple2(taskMap['taskId'] as int, machineDurations);
    }).toList();

    return FlexibleFlowInput(
      jobMap['jobId'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['dueDate'] as int),
      jobMap['priority'] as int,
      DateTime.fromMillisecondsSinceEpoch(jobMap['availableDate'] as int),
      taskSequence,
    );
  }).toList();

  final machinesAvailability = (payload['machinesAvailability'] as Map<dynamic, dynamic>)
      .map((key, value) => MapEntry(key as int, DateTime.fromMillisecondsSinceEpoch(value as int)));

  // Calendar inputs — inactivity windows, the continuous-use cap and the
  // rest duration — used to be dropped on the floor here, so an order run
  // through this isolate entry point ignored maintenance/shift/rest
  // altogether. Parsed the same way openShopSchedule does.
  final machineInactivities = <int, List<MachineInactivityEntity>>{};
  final rawInactivities = payload['machineInactivities'];
  if (rawInactivities != null) {
    for (final entry in (rawInactivities as Map<dynamic, dynamic>).entries) {
      final machineId = entry.key as int;
      machineInactivities[machineId] = (entry.value as List<dynamic>)
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
  }

  final machineContinueCapacity = payload['machineContinueCapacity'] == null
      ? const <int, int>{}
      : (payload['machineContinueCapacity'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as int));

  final machineRestTime = <int, Duration?>{};
  final rawRestTime = payload['machineRestTime'];
  if (rawRestTime != null) {
    for (final entry in (rawRestTime as Map<dynamic, dynamic>).entries) {
      machineRestTime[entry.key as int] = entry.value == null
          ? null
          : Duration(milliseconds: entry.value as int);
    }
  }

  final stateSetupMatrix = payload['stateSetupMatrix'] == null
      ? null
      : (payload['stateSetupMatrix'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
                key as int,
                (Map<dynamic, dynamic>.from(value as Map)).map(
                  (prev, curr) => MapEntry(
                    prev as String,
                    (Map<dynamic, dynamic>.from(curr as Map)).map(
                      (next, minutes) => MapEntry(next as String, minutes as int),
                    ),
                  ),
                ),
              ),
        );

  final jobStates = payload['jobStates'] == null
      ? null
      : (payload['jobStates'] as Map<dynamic, dynamic>).map(
          (key, value) => MapEntry(
            key as int,
            (Map<dynamic, dynamic>.from(value as Map)).map((mKey, state) => MapEntry(mKey as int, state as String)),
          ),
        );

  final initialMachineState = payload['initialMachineState'] == null
      ? const <int, String>{}
      : (payload['initialMachineState'] as Map<dynamic, dynamic>)
          .map((key, value) => MapEntry(key as int, value as String));

  final output = FlexibleFlowShop(
    startDate,
    workingSchedule,
    inputJobs,
    machinesAvailability,
    payload['rule'] as String,
    initialMachineState: initialMachineState,
    stateSetupMatrix: stateSetupMatrix,
    jobStates: jobStates,
    machineInactivities: machineInactivities,
    machineContinueCapacity: machineContinueCapacity,
    machineRestTime: machineRestTime,
  ).output;

  List<Map<String, dynamic>> segmentsToPayload(
      List<ProcessingSegment> segments) {
    return segments
        .map((s) => {
              'start': s.start.millisecondsSinceEpoch,
              'end': s.end.millisecondsSinceEpoch,
            })
        .toList();
  }

  return output.map((out) {
    return {
      'jobId': out.jobId,
      'dueDate': out.dueDate.millisecondsSinceEpoch,
      'startDate': out.startDate.millisecondsSinceEpoch,
      'endTime': out.endTime.millisecondsSinceEpoch,
      'scheduling': out.scheduling.map((key, value) => MapEntry(key.toString(), {
            'machineId': value.value1,
            'start': value.value2.startDate.millisecondsSinceEpoch,
            'end': value.value2.endDate.millisecondsSinceEpoch,
          })),
      'segmentsByStation': out.segmentsByStation.map((key, segments) =>
          MapEntry(key.toString(), segmentsToPayload(segments))),
      'setupSegmentsByStation': out.setupSegmentsByStation.map(
          (key, segments) =>
              MapEntry(key.toString(), segmentsToPayload(segments))),
    };
  }).toList();
}

}


