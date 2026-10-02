import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'package:production_planning/shared/types/rnage.dart';
import 'dart:math';

class FlowShopInput {
  final int jobId;
  final int sequenceId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  // this list has the order of the tasks, it has a tuple of 2 <task id, machine id>
  final List<Tuple2<int, int>> taskSequence;
  // in this map we have the durations, the id is the task id, and the duration is how long it takes
  final Map<int, Duration> taskTimesInMachines;

  /// Whether each task (keyed by task id) may be split by a work-shift
  /// boundary, the continuous-use rest cap, or a maintenance window.
  /// Missing entries default to interruptible.
  final Map<int, bool> interruptibleByTask;

  FlowShopInput(
    this.jobId,
    this.sequenceId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.taskSequence,
    this.taskTimesInMachines, {
    this.interruptibleByTask = const {},
  });

  bool isTaskInterruptible(int taskId) => interruptibleByTask[taskId] ?? true;
}

class FlowShopOutput {
  final int jobId;
  final DateTime startDate;
  final DateTime dueDate;
  final DateTime endTime;
  // the output, the map has the key the machine id, the value is a tuple of <task id, range start to end time>
  final Map<int, Tuple2<int, Range>> machinesScheduling;

  /// Processing segments per machine (machineId → segments), for tasks that
  /// were preempted mid-processing. Defaults to a single segment matching
  /// the machine's Range when not explicitly provided.
  final Map<int, List<ProcessingSegment>> segmentsByMachine;

  /// Setup/changeover segments per machine (machineId → segments), if any.
  final Map<int, List<ProcessingSegment>> setupSegmentsByMachine;

  FlowShopOutput(
    this.jobId,
    this.startDate,
    this.dueDate,
    this.endTime,
    this.machinesScheduling, {
    Map<int, List<ProcessingSegment>>? segmentsByMachine,
    this.setupSegmentsByMachine = const {},
  }) : segmentsByMachine = segmentsByMachine ??
            machinesScheduling.map((machineId, entry) => MapEntry(
                machineId,
                [ProcessingSegment(entry.value2.start, entry.value2.end)]));
}

/// A whole job's route through the flow shop, priced but not committed.
///
/// Produced by `FlowShop._simulateJob`, written by `_commitPlacement`. The
/// two `*After` maps hold the per-machine state the route would leave behind
/// so that simulating a candidate touches nothing until it actually wins.
class _FlowShopPlacement {
  final FlowShopInput job;
  final DateTime startTime;
  final DateTime endTime;
  final Map<int, Tuple2<int, Range>> scheduling;
  final Map<int, List<ProcessingSegment>> segmentsByMachine;
  final Map<int, List<ProcessingSegment>> setupSegmentsByMachine;

  /// New earliest-free time per machine this route touched.
  final Map<int, DateTime> availabilityAfter;

  /// New continuous-use streak per machine this route touched.
  final Map<int, Duration> continuousUsageAfter;

  const _FlowShopPlacement({
    required this.job,
    required this.startTime,
    required this.endTime,
    required this.scheduling,
    required this.segmentsByMachine,
    required this.setupSegmentsByMachine,
    required this.availabilityAfter,
    required this.continuousUsageAfter,
  });
}

class FlowShop {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; // like 8-17

  List<FlowShopInput> inputJobs = [];
  Map<int, DateTime> machinesAvailability = {};
  List<FlowShopOutput> output = [];

  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;
  final Map<int, Map<int, String>>? jobStates;

  /// machineId → state letter (A-J) the machine starts this order in,
  /// before its first job.
  final Map<int, String> initialMachineState;
  final Map<int, int?> _machineLastSequence = {};
  final Map<int, int?> _machineLastJob = {};

  // Machine inactivity support.
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count — so a
  // single long task can be preempted mid-processing.
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;

  /// How long each machine has run continuously since its last pause.
  final Map<int, Duration> _machineContinuousUsage = {};
  final Map<int, PreemptionEngine> _engineByMachine = {};

  FlowShop(
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
    _initializeMachineLastSequence();
    // Preemption engine per machine (rest cap + maintenance windows).
    for (final machineId in machinesAvailability.keys) {
      _machineContinuousUsage[machineId] = Duration.zero;
      final capacityMinutes = machineContinueCapacity[machineId] ?? 0;
      _engineByMachine[machineId] = PreemptionEngine(
        workingSchedule: workingSchedule,
        maintenanceWindows: machineInactivities[machineId] ?? const [],
        continuousUseCap:
            capacityMinutes > 0 ? Duration(minutes: capacityMinutes) : Duration.zero,
        restDuration: machineRestTime[machineId] ?? Duration.zero,
      );
    }
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
      case "JOHNSON":
        _applyJohnsonRule(inputJobs);
        break;
      case "CDS":
        cdsAlgorithm();
        break;
      // The DB grants MINSLACK here and MS elsewhere; same rule.
      case "MINSLACK":
      case "MS":
        msRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "GENETICS":
        scheduleGeneticAlgorithm();
        break;
      default:
        // no-op: unknown rule
        break;
    }
  }

  /* ---------- Rules (dispatching / sequencing) ---------- */

  void eddRule() => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void sptRule() => _schedule(
        (a, b) => _totalProcessingTime(a).compareTo(_totalProcessingTime(b)),
      );
  void lptRule() => _schedule(
        (a, b) => _totalProcessingTime(b).compareTo(_totalProcessingTime(a)),
      );
  void fifoRule() => _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptRule() => _schedule((a, b) {
        double wsptA = a.priority / max(1, _totalProcessingTime(a));
        double wsptB = b.priority / max(1, _totalProcessingTime(b));
        return wsptB.compareTo(wsptA);
      });

  // ── Dynamic (*_ADAPTADO) rules ────────────────────────────────────────────
  //
  // These used to hand `dynamicRule` a comparator built from immutable job
  // fields only. The loop re-sorted on every iteration, but re-sorting by a
  // key that never changes returns the same order — so the "dynamic" rules
  // produced exactly the schedule their static counterparts did.
  //
  // They now compare the job's EFFECTIVE route span at each decision point:
  // see _runDynamic.

  void eddaRule() => _runDynamic(DispatchCriterion.edd);
  void sptaRule() => _runDynamic(DispatchCriterion.spt);
  void lptaRule() => _runDynamic(DispatchCriterion.lpt);
  void fifoaRule() => _runDynamic(DispatchCriterion.fifo);
  void wsptaRule() => _runDynamic(DispatchCriterion.wspt);

  // MS, CR and ATCS are dynamic by definition — their index depends on the
  // clock t — so they run through the same event-driven dispatch as the
  // *_ADAPTADO rules. MS and CR used to measure t with DateTime.now(), the
  // wall clock when the button was pressed, so the same order could
  // schedule differently from one minute to the next; the ATC index had no
  // setup term and no release gate.
  void msRule() => _runDynamic(DispatchCriterion.ms);
  void crRule() => _runDynamic(DispatchCriterion.cr);
  void atcRule() => _runDynamic(DispatchCriterion.atcs);

  void _schedule(int Function(FlowShopInput, FlowShopInput) comparator) {
    inputJobs.sort(comparator);
    for (var job in inputJobs) {
      _assignJobToMachines(job);
    }
  }

  /// Event-driven dispatch for the *_ADAPTADO rules.
  ///
  /// The decision point is the moment the route's entry machine frees up.
  /// Among the jobs released by then, each is simulated end-to-end through
  /// its whole route via [_simulateJob], so the span being compared is what
  /// the job really costs — every changeover along the route plus every
  /// split a shift boundary, maintenance window or rest cap forces.
  void _runDynamic(DispatchCriterion criterion) {
    if (inputJobs.isEmpty) return;

    final pending = List<FlowShopInput>.from(inputJobs);
    final AtcsParameters? atcs =
        criterion == DispatchCriterion.atcs ? _atcsParameters() : null;
    final sequenced = <FlowShopInput>[];

    while (pending.isNotEmpty) {
      final DateTime decisionTime = _entryMachineFreeAt(pending);

      final selected = selectNext<FlowShopInput>(
        pending: pending,
        decisionTime: decisionTime,
        releaseTime: (job) => job.availableDate,
        criterion: criterion,
        atcs: atcs,
        evaluate: (job, at) {
          final placement = _simulateJob(job, notBefore: at);
          final span = placement.endTime.difference(at);
          return DispatchCandidate(
            job: job,
            start: placement.startTime,
            end: placement.endTime,
            span: span.isNegative ? Duration.zero : span,
            dueDate: job.dueDate,
            releaseDate: job.availableDate,
            priority: job.priority,
            jobId: job.jobId,
            setup: placement.setupSegmentsByMachine.values.fold(
              Duration.zero,
              (sum, segments) => sum + segmentsDuration(segments),
            ),
          );
        },
      );

      if (selected == null) {
        // Unreachable in practice: selectNext only returns null for an empty
        // list (it throws when every job is unplaceable). If it ever
        // happens, schedule what is left in order rather than dropping it.
        for (final job in pending) {
          _commitPlacement(_simulateJob(job, notBefore: decisionTime));
          sequenced.add(job);
        }
        pending.clear();
        break;
      }

      // selectNext is non-delay on effective starts: the winner can really
      // begin its route at t*, the earliest instant any pending job can on
      // the entry machine, after setups and interruptions. A job an
      // interruption would hold back does not take the line ahead of one
      // that can start now, and if nothing can start at decisionTime the
      // clock jumps to t*. Re-simulate from the same instant it was judged
      // from; _simulateJob is pure, so this recomputes rather than decides.
      _commitPlacement(_simulateJob(
        selected.job,
        notBefore:
            evaluationTime(selected.job, decisionTime, (j) => j.availableDate),
      ));
      sequenced.add(selected.job);
      pending.remove(selected.job);
    }

    inputJobs = sequenced;
  }

  /// When the next dispatch decision happens: the earliest moment the entry
  /// machine of any pending job's route becomes free.
  ///
  /// The minimum, not the maximum — waiting for the last machine would stall
  /// the loop behind one no pending job is queued on. Releases and
  /// interruptions after this instant are folded into each job's effective
  /// start by selectNext, so no separate clock floor is needed.
  DateTime _entryMachineFreeAt(List<FlowShopInput> pending) {
    final DateTime floor = startDate;
    DateTime? earliest;

    for (final job in pending) {
      if (job.taskSequence.isEmpty) continue;
      final int entryMachineId = job.taskSequence.first.value2;
      final DateTime freeAt = machinesAvailability[entryMachineId] ?? startDate;
      if (earliest == null || freeAt.isBefore(earliest)) earliest = freeAt;
    }

    if (earliest == null || earliest.isBefore(floor)) return floor;
    return earliest;
  }

  /* ---------- Core scheduling (assignment) ---------- */

  void _assignJobToMachines(FlowShopInput job) {
    _commitPlacement(_simulateJob(job, notBefore: null));
  }

  /// Walks [job] through its whole machine route and returns the resulting
  /// placement WITHOUT committing it.
  ///
  /// No field is written here: `machinesAvailability`, `_machineLastJob`,
  /// `_machineLastSequence` and `_machineContinuousUsage` are only read, and
  /// `computeSegments` is a pure function of its arguments. That makes it
  /// safe to price several contenders and keep only the winner.
  ///
  /// No per-machine bookkeeping copy is needed because a flow shop route
  /// touches each machine exactly once, so nothing this job does to one
  /// machine can affect its own later steps.
  ///
  /// [notBefore], when given, holds the job back to the decision clock of a
  /// dynamic rule, so every contender is priced from the same instant.
  _FlowShopPlacement _simulateJob(FlowShopInput job, {DateTime? notBefore}) {
    DateTime jobStartTime = job.availableDate;
    if (notBefore != null && notBefore.isAfter(jobStartTime)) {
      jobStartTime = notBefore;
    }
    DateTime? actualStartTime;
    Map<int, Tuple2<int, Range>> scheduling = {};
    Map<int, List<ProcessingSegment>> segmentsByMachine = {};
    Map<int, List<ProcessingSegment>> setupSegmentsByMachine = {};
    // Per-machine state this route would leave behind, applied only on commit.
    Map<int, DateTime> availabilityAfter = {};
    Map<int, Duration> continuousUsageAfter = {};

    for (var task in job.taskSequence) {
      int taskId = task.value1;
      int machineId = task.value2;
      Duration duration = job.taskTimesInMachines[taskId]!;

      DateTime machineAvailable = machinesAvailability[machineId] ?? startDate;
      DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
      startTime = _adjustForWorkingSchedule(startTime);

      final int? previousSequence = _machineLastSequence[machineId];
      final int? previousJob = _machineLastJob[machineId];
      final Duration setupDuration = _getSetupDuration(
        machineId,
        job.sequenceId,
        previousSequence,
        currentJobId: job.jobId,
        previousJobId: previousJob,
      );

      // Setup then processing, both through the preemption engine. The
      // task's interruption flag governs the pair: interruptible → each may
      // be split by a shift end / maintenance / rest cap; not interruptible
      // → one contiguous block, processing starting the instant setup ends.
      final placed = _engineByMachine[machineId]!.computeSetupAndProcessing(
        earliestStart: startTime,
        setupDuration: setupDuration,
        processingDuration: duration,
        priorContinuousUsage:
            _machineContinuousUsage[machineId] ?? Duration.zero,
        interruptible: job.isTaskInterruptible(taskId),
      );
      final schedule = placed.processing;
      final DateTime adjustedEnd = schedule.completionTime;

      actualStartTime ??= placed.start;

      scheduling[machineId] = Tuple2(taskId, Range(schedule.startDate, adjustedEnd));
      segmentsByMachine[machineId] = schedule.segments;
      setupSegmentsByMachine[machineId] = placed.setupSegments;
      availabilityAfter[machineId] = adjustedEnd;
      continuousUsageAfter[machineId] = placed.continuousUsageAfter;
      jobStartTime = adjustedEnd;
    }

    return _FlowShopPlacement(
      job: job,
      startTime: actualStartTime ?? job.availableDate,
      endTime: jobStartTime,
      scheduling: scheduling,
      segmentsByMachine: segmentsByMachine,
      setupSegmentsByMachine: setupSegmentsByMachine,
      availabilityAfter: availabilityAfter,
      continuousUsageAfter: continuousUsageAfter,
    );
  }

  /// Applies a placement produced by [_simulateJob] to the real schedule.
  void _commitPlacement(_FlowShopPlacement placement) {
    final job = placement.job;

    placement.availabilityAfter.forEach((machineId, endTime) {
      machinesAvailability[machineId] = endTime;
      _machineLastSequence[machineId] = job.sequenceId;
      _machineLastJob[machineId] = job.jobId;
    });
    placement.continuousUsageAfter.forEach((machineId, usage) {
      _machineContinuousUsage[machineId] = usage;
    });

    output.add(
      FlowShopOutput(
        job.jobId,
        placement.startTime,
        job.dueDate,
        placement.endTime,
        placement.scheduling,
        segmentsByMachine: placement.segmentsByMachine,
        setupSegmentsByMachine: placement.setupSegmentsByMachine,
      ),
    );
  }

  Duration _getSetupDuration(
    int machineId,
    int currentSequenceId,
    int? previousSequenceId, {
    int? currentJobId,
    int? previousJobId,
  }) {
    // State-based setup matrix (job final states on each machine). With no
    // previous job on this machine yet, fall back to the machine's
    // configured initial state for this order, so its first job can also
    // pay a real changeover instead of always zero.
    if (stateSetupMatrix != null && jobStates != null && currentJobId != null) {
      final machineStates = stateSetupMatrix![machineId];
      if (machineStates != null) {
        String? previousState;
        if (previousJobId != null) {
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


  int _totalProcessingTime(FlowShopInput job) {
    return job.taskTimesInMachines.values.fold(0, (sum, duration) => sum + duration.inMinutes);
  }

  void _initializeMachineLastSequence() {
    for (final machineId in machinesAvailability.keys) {
      _machineLastSequence[machineId] = null;
      _machineLastJob[machineId] = null;
    }
  }

  DateTime _adjustForWorkingSchedule(DateTime start) {
    TimeOfDay workingStart = workingSchedule.value1;
    TimeOfDay workingEnd = workingSchedule.value2;

    if (start.hour < workingStart.hour || (start.hour == workingStart.hour && start.minute < workingStart.minute)) {
      return DateTime(start.year, start.month, start.day, workingStart.hour, workingStart.minute);
    } else if (start.hour > workingEnd.hour || (start.hour == workingEnd.hour && start.minute > workingEnd.minute)) {
      return DateTime(start.year, start.month, start.day + 1, workingStart.hour, workingStart.minute);
    }
    return start;
  }

  DateTime _calculateEndWithSchedule(DateTime start, Duration duration) {
    if (duration <= Duration.zero) return start;

    final TimeOfDay workingStart = workingSchedule.value1;
    final TimeOfDay workingEnd = workingSchedule.value2;

    final DateTime probeDayStart = DateTime(
      start.year,
      start.month,
      start.day,
      workingStart.hour,
      workingStart.minute,
    );
    final DateTime probeDayEnd = DateTime(
      start.year,
      start.month,
      start.day,
      workingEnd.hour,
      workingEnd.minute,
    );
    if (!probeDayEnd.isAfter(probeDayStart)) {
      return start.add(duration);
    }

    DateTime current = start;
    Duration remaining = duration;
    int maxIterations = 10000; // Seguridad contra loops infinitos
    int iterations = 0;

    while (remaining > Duration.zero && iterations < maxIterations) {
      iterations++;

      final DateTime dayStart = DateTime(current.year, current.month, current.day, workingStart.hour, workingStart.minute);
      final DateTime dayEnd = DateTime(current.year, current.month, current.day, workingEnd.hour, workingEnd.minute);

      // Si current está antes del inicio del horario laboral, sáltalo al inicio
      if (current.isBefore(dayStart)) {
        current = dayStart;
      }

      // Si current está en o después del fin del horario laboral, sáltalo al siguiente día
      if (!current.isBefore(dayEnd)) {
        current = DateTime(current.year, current.month, current.day + 1, workingStart.hour, workingStart.minute);
      } else {
        // current está dentro del horario laboral: descuenta el tiempo disponible hoy
        final Duration availableToday = dayEnd.difference(current);
        if (remaining <= availableToday) {
          // El tiempo restante cabe en lo que queda de hoy
          return current.add(remaining);
        } else {
          // El tiempo restante excede lo disponible hoy, descuenta y salta al siguiente
          remaining -= availableToday;
          current = DateTime(current.year, current.month, current.day + 1, workingStart.hour, workingStart.minute);
        }
      }
    }

    return current;
  }

  /// Fits the ATCS parameters to this instance (see
  /// [AtcsParameters.calibrate]). A candidate here is a whole route, so p̄
  /// and s̄ are per route. The makespan estimate is the bottleneck machine's
  /// load plus its share of the changeovers.
  AtcsParameters _atcsParameters() {
    final int n = inputJobs.length;
    final double meanProcessing = inputJobs.fold<double>(
            0, (sum, job) => sum + _totalProcessingTime(job)) /
        n;
    final double meanSetup = meanPairwiseSetupMinutes<FlowShopInput>(
      inputJobs,
      (from, to) => to.taskSequence.fold<Duration>(
        Duration.zero,
        (sum, task) =>
            sum +
            _getSetupDuration(
              task.value2,
              to.sequenceId,
              from.sequenceId,
              currentJobId: to.jobId,
              previousJobId: from.jobId,
            ),
      ),
    );

    final Map<int, double> load = {};
    for (final job in inputJobs) {
      for (final task in job.taskSequence) {
        final Duration? p = job.taskTimesInMachines[task.value1];
        if (p == null) continue;
        load[task.value2] = (load[task.value2] ?? 0) + p.inSeconds / 60.0;
      }
    }
    final double bottleneck = load.values.fold(0.0, (a, b) => max(a, b));
    final int machineCount = max(load.length, 1);
    final double workMinutes = bottleneck + n * meanSetup / machineCount;

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

  /* ---------- CDS & Johnson helpers ---------- */

  void cdsAlgorithm() {
    if (inputJobs.isEmpty) return;

    int numMachines = inputJobs.first.taskSequence.length;

    if (numMachines == 2) {
      _applyJohnsonRule(inputJobs);
      return;
    }

    List<FlowShopInput> bestSequence = [];
    int bestMakespan = double.maxFinite.toInt();

    for (int k = 1; k < numMachines; k++) {
      List<FlowShopInput> tempJobs = inputJobs.map((job) {
        Duration sumA = Duration.zero;
        Duration sumB = Duration.zero;

        for (int i = 0; i < k; i++) {
          int taskId = job.taskSequence[i].value1;
          sumA += job.taskTimesInMachines[taskId]!;
        }

        for (int i = k; i < numMachines; i++) {
          int taskId = job.taskSequence[i].value1;
          sumB += job.taskTimesInMachines[taskId]!;
        }

        Map<int, Duration> reducedTimes = {0: sumA, 1: sumB};

        return FlowShopInput(
          job.jobId,
          job.sequenceId,
          job.dueDate,
          job.priority,
          job.availableDate,
          [const Tuple2(0, 0), const Tuple2(1, 1)],
          reducedTimes,
        );
      }).toList();

      List<FlowShopInput> ordered = _getJohnsonOrderedJobs(tempJobs);
      List<int> orderedIds = ordered.map((e) => e.jobId).toList();

      List<FlowShopInput> orderedOriginal = orderedIds.map((id) => inputJobs.firstWhere((job) => job.jobId == id)).toList();

      int makespan = _calculateMakespan(orderedOriginal);

      if (makespan < bestMakespan) {
        bestMakespan = makespan;
        bestSequence = orderedOriginal;
      }
    }

    inputJobs = bestSequence;
    _schedule((a, b) => 0);
    print("Optimal sequence: ${bestSequence.map((job) => job.jobId).toList()}");
    print("Optimal makespan: $bestMakespan");
  }

  void _applyJohnsonRule(List<FlowShopInput> jobs) {
    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in jobs) {
      Duration a = job.taskTimesInMachines[job.taskSequence[0].value1]!;
      Duration b = job.taskTimesInMachines[job.taskSequence[1].value1]!;
      if (a <= b) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort((a, b) => a.taskTimesInMachines[a.taskSequence[0].value1]!.compareTo(b.taskTimesInMachines[b.taskSequence[0].value1]!));
    conjuntoII.sort((a, b) => b.taskTimesInMachines[b.taskSequence[1].value1]!.compareTo(a.taskTimesInMachines[a.taskSequence[1].value1]!));

    inputJobs = [...conjuntoI, ...conjuntoII];
    _schedule((a, b) => 0);
  }

  List<FlowShopInput> _getJohnsonOrderedJobs(List<FlowShopInput> jobs) {
    List<FlowShopInput> conjuntoI = [];
    List<FlowShopInput> conjuntoII = [];

    for (var job in jobs) {
      Duration a = job.taskTimesInMachines[0]!;
      Duration b = job.taskTimesInMachines[1]!;
      if (a <= b) {
        conjuntoI.add(job);
      } else {
        conjuntoII.add(job);
      }
    }

    conjuntoI.sort((a, b) => a.taskTimesInMachines[0]!.compareTo(b.taskTimesInMachines[0]!));
    conjuntoII.sort((a, b) => b.taskTimesInMachines[1]!.compareTo(a.taskTimesInMachines[1]!));
    return [...conjuntoI, ...conjuntoII];
  }

  int _calculateMakespan(List<FlowShopInput> jobSequence) {
    Map<int, DateTime> currentMachineAvailability = {};
    Map<int, int?> currentMachineSequence = {};
    Map<int, int?> currentMachineJob = {};

    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        final machineId = task.value2;
        currentMachineAvailability.putIfAbsent(machineId, () => startDate);
        currentMachineSequence.putIfAbsent(machineId, () => null);
        currentMachineJob.putIfAbsent(machineId, () => null);
      }
    }

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int taskId = task.value1;
        int machineId = task.value2;
        Duration duration = job.taskTimesInMachines[taskId]!;

        DateTime machineAvailable = currentMachineAvailability[machineId] ?? startDate;
        DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);

        final int? previousSequence = currentMachineSequence[machineId];
        final int? previousJob = currentMachineJob[machineId];
        final Duration setupDuration = _getSetupDuration(
          machineId,
          job.sequenceId,
          previousSequence,
          currentJobId: job.jobId,
          previousJobId: previousJob,
        );
        final Duration totalDuration = duration + setupDuration;

        DateTime endTime = _calculateEndWithSchedule(startTime, totalDuration);

        currentMachineAvailability[machineId] = endTime;
        currentMachineSequence[machineId] = job.sequenceId;
        currentMachineJob[machineId] = job.jobId;
        jobStartTime = endTime;
      }

      makespanEndTime = jobStartTime.isAfter(makespanEndTime) ? jobStartTime : makespanEndTime;
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }

  /* ---------- Genetic algorithm (Flow Shop sequencing) ---------- */

  void scheduleGeneticAlgorithm() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN FLOW SHOP");

    const int populationSize = 15;
    const int maxGenerations = 25;
    const int maxGenerationsNoImprovement = 5;
    const double mutationRate = 0.1;

    if (inputJobs.isEmpty) return;

    List<List<FlowShopInput>> population = _initializePopulation(populationSize);

    List<FlowShopInput> bestIndividual = List.from(inputJobs);
    int bestFitness = _evaluateFitnessFlowShop(bestIndividual);
    int generationsNoImprovement = 0;

    for (int generation = 0; generation < maxGenerations; generation++) {
      List<Tuple2<List<FlowShopInput>, int>> evaluated = population.map((individual) {
        return Tuple2(individual, _evaluateFitnessFlowShop(individual));
      }).toList();

      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = List.from(evaluated.first.value1);
        generationsNoImprovement = 0;
        print("Generación $generation: Mejor makespan = $bestFitness minutos");
      } else {
        generationsNoImprovement++;
        // Early stopping: si no hay mejora en N generaciones, termina
        if (generationsNoImprovement >= maxGenerationsNoImprovement) {
          print("Sin mejora en $maxGenerationsNoImprovement generaciones. Deteniendo búsqueda.");
          break;
        }
      }

      population = _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    print("Mejor secuencia encontrada: ${bestIndividual.map((j) => j.jobId).toList()}");
    print("Makespan óptimo: $bestFitness minutos");

    inputJobs = bestIndividual;
    _schedule((a, b) => 0);
  }

  List<List<FlowShopInput>> _initializePopulation(int size) {
    List<List<FlowShopInput>> population = [];
    for (int i = 0; i < size; i++) {
      List<FlowShopInput> shuffled = List.from(inputJobs);
      shuffled.shuffle();
      population.add(shuffled);
    }
    return population;
  }

  int _evaluateFitnessFlowShop(List<FlowShopInput> jobSequence) {
    Map<int, DateTime> machineAvailability = {};
    Map<int, int?> machineSequence = {};
    Map<int, int?> machineJob = {};

    for (var job in jobSequence) {
      for (var task in job.taskSequence) {
        final machineId = task.value2;
        machineAvailability.putIfAbsent(machineId, () => startDate);
        machineSequence.putIfAbsent(machineId, () => null);
        machineJob.putIfAbsent(machineId, () => null);
      }
    }

    DateTime makespanEndTime = startDate;

    for (var job in jobSequence) {
      DateTime jobStartTime = job.availableDate;

      for (var task in job.taskSequence) {
        int taskId = task.value1;
        int machineId = task.value2;
        Duration duration = job.taskTimesInMachines[taskId]!;

        DateTime machineAvailable = machineAvailability[machineId] ?? startDate;
        DateTime startTime = jobStartTime.isAfter(machineAvailable) ? jobStartTime : machineAvailable;
        startTime = _adjustForWorkingSchedule(startTime);

        final int? previousSequence = machineSequence[machineId];
        final int? previousJob = machineJob[machineId];
        final Duration setupDuration = _getSetupDuration(
          machineId,
          job.sequenceId,
          previousSequence,
          currentJobId: job.jobId,
          previousJobId: previousJob,
        );
        final Duration totalDuration = duration + setupDuration;

        DateTime endTime = _calculateEndWithSchedule(startTime, totalDuration);

        machineAvailability[machineId] = endTime;
        machineSequence[machineId] = job.sequenceId;
        machineJob[machineId] = job.jobId;
        jobStartTime = endTime;
      }

      if (jobStartTime.isAfter(makespanEndTime)) makespanEndTime = jobStartTime;
    }

    return makespanEndTime.difference(startDate).inMinutes;
  }

  List<List<FlowShopInput>> _generateNewPopulation(
    List<Tuple2<List<FlowShopInput>, int>> evaluated,
    int size,
    double mutationRate,
  ) {
    List<List<FlowShopInput>> newPop = [];

    for (int i = 0; i < size; i++) {
      final parent1 = _selectParent(evaluated);
      final parent2 = _selectParent(evaluated);
      List<FlowShopInput> child = _crossover(parent1, parent2);
      if (Random().nextDouble() < mutationRate) {
        child = _mutate(child);
      }
      newPop.add(child);
    }

    return newPop;
  }

  List<FlowShopInput> _selectParent(List<Tuple2<List<FlowShopInput>, int>> evaluated) {
    int k = min(5, evaluated.length);
    final selected = List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    return selected.first.value1;
  }

  List<FlowShopInput> _crossover(List<FlowShopInput> p1, List<FlowShopInput> p2) {
    final length = p1.length;
    if (length == 0) return [];

    final int point = Random().nextInt(length);
    final Set<int> jobIds = p1.sublist(0, point).map((j) => j.jobId).toSet();

    final List<FlowShopInput> child = [
      ...p1.sublist(0, point),
      ...p2.where((j) => !jobIds.contains(j.jobId)),
    ];

    // if child shorter (shouldn't) fill with remaining from p1
    if (child.length < length) {
      for (var j in p1) {
        if (!child.contains(j)) child.add(j);
        if (child.length == length) break;
      }
    }

    return child;
  }

  List<FlowShopInput> _mutate(List<FlowShopInput> individual) {
    if (individual.length < 2) return individual;
    int i = Random().nextInt(individual.length);
    int j = Random().nextInt(individual.length);
    final temp = individual[i];
    individual[i] = individual[j];
    individual[j] = temp;
    return individual;
  }
}
