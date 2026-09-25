import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'dart:math';

class ParallelInput {
  final int jobId;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;
  final Map<int, Duration> durationsInMachines;

  /// Product family / job-type label, e.g. "A", "B".
  /// Used as the row/column key in the state-based setup matrix.
  final String jobState;

  /// Optional per-machine state (machineId → state). Falls back to [jobState].
  final Map<int, String>? jobStatesByMachine;

  /// Default interruptibility (usually the task's own setting). Whether this
  /// job's processing may be split by a work-shift boundary, the
  /// continuous-use rest cap, or a maintenance window.
  final bool interruptible;

  /// Optional per-machine override (machineId → interruptible). Falls back
  /// to [interruptible].
  final Map<int, bool>? interruptibleByMachine;

  ParallelInput(
    this.jobId,
    this.dueDate,
    this.priority,
    this.availableDate,
    this.durationsInMachines, {
    this.jobState = 'A',
    this.jobStatesByMachine,
    this.interruptible = true,
    this.interruptibleByMachine,
  });

  String stateOnMachine(int machineId) =>
      jobStatesByMachine?[machineId] ?? jobState;

  bool isInterruptibleOnMachine(int machineId) =>
      interruptibleByMachine?[machineId] ?? interruptible;
}

class ParallelOutput {
  final int jobId;
  final int machineId;
  final DateTime startDate;
  final DateTime endDate;
  final Duration delay;
  final DateTime dueDate;
  final List<ProcessingSegment> segments;
  final List<ProcessingSegment> setupSegments;

  ParallelOutput(
    this.jobId,
    this.machineId,
    this.startDate,
    this.endDate,
    this.delay,
    this.dueDate, {
    List<ProcessingSegment>? segments,
    this.setupSegments = const [],
  }) : segments = segments ?? [ProcessingSegment(startDate, endDate)];
}

/// One job priced on one machine, not yet committed.
///
/// Produced by `ParallelMachine._bestPlacementFor`, written by
/// `_commitPlacement`. Splitting evaluation from commitment is what lets the
/// dynamic rules compare jobs on their real cost — the same placement that
/// won the comparison is the one that gets scheduled.
class _ParallelPlacement {
  final ParallelInput job;
  final int machineId;

  /// Start of processing (after setup, if any).
  final DateTime processStart;

  final SegmentedSchedule schedule;
  final List<ProcessingSegment> setupSegments;

  /// Continuous-use streak after setup, before processing.
  final Duration continuousUsageAfterSetup;

  final Duration delay;

  const _ParallelPlacement({
    required this.job,
    required this.machineId,
    required this.processStart,
    required this.schedule,
    required this.setupSegments,
    required this.continuousUsageAfterSetup,
    required this.delay,
  });

  /// When the machine actually starts working: setup if there is one,
  /// otherwise processing.
  DateTime get start =>
      setupSegments.isNotEmpty ? setupSegments.first.start : processStart;

  DateTime get end => schedule.completionTime;
}

class ParallelMachine {
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule;
  List<ParallelInput> inputJobs = [];
  Map<int, List<Tuple2<DateTime, DateTime>>> machines = {};
  List<ParallelOutput> output = [];

  // ── Setup-time state ──────────────────────────────────────────────────────
  // stateSetupMatrix: machineId → fromState → toState → minutes
  // Mirrors the structure used by Flow Shop / Flexible Job Shop / Open Shop.
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;

  /// machineId → state letter (A-J) the machine starts this order in,
  /// before its first job.
  final Map<int, String> initialMachineState;

  // Tracks which job-state each machine processed last. Seeded from
  // [initialMachineState] below; null when a machine has no configured
  // initial state (cold start, same as before this field existed).
  final Map<int, String?> _machineLastState = {};

  // Machine inactivity support.
  // machineContinueCapacity is interpreted as MINUTES of continuous
  // processing allowed before a mandatory rest — not a job count — so a
  // single long job can be preempted mid-processing.
  final Map<int, List<MachineInactivityEntity>> machineInactivities;
  final Map<int, int> machineContinueCapacity;
  final Map<int, Duration?> machineRestTime;

  /// How long each machine has run continuously since its last pause.
  final Map<int, Duration> _machineContinuousUsage = {};
  final Map<int, PreemptionEngine> _engineByMachine = {};

  /// Earliest-free moment of each machine, as the schedule is built.
  ///
  /// A field rather than a local of the assignment loop because the dynamic
  /// rules need to read it to know WHEN the next decision happens — the
  /// earliest moment any machine frees up.
  final Map<int, DateTime> machineAvailable = {};

  ParallelMachine(
    this.startDate,
    this.workingSchedule,
    this.inputJobs,
    this.machines,
    String rule, {
    this.stateSetupMatrix,
    this.initialMachineState = const {},
    this.machineInactivities = const {},
    this.machineContinueCapacity = const {},
    this.machineRestTime = const {},
  }) {
    // Initialise cold-start tracking and a preemption engine per machine.
    for (final machineId in machines.keys) {
      _machineLastState[machineId] = initialMachineState[machineId];
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
      case "SPT":
        sptRule();
        break;
      case "LPT":
        lptRule();
        break;
      case "EDD":
        eddRule();
        break;
      case "FIFO":
        fcfsRule();
        break;
      case "MINSLACK":
        minslackRule();
        break;
      case "CR":
        crRule();
        break;
      case "ATCS":
        atcRule();
        break;
      case "WSPT":
        wsptRule();
        break;
      case "SPT_ADAPTADO":
        sptaRule();
        break;
      case "EDD_ADAPTADO":
        eddaRule();
        break;
      case "FIFO_ADAPTADO":
        fifoaRule();
        break;
      case "WSPT_ADAPTADO":
        wsptaRule();
        break;
      case "LPT_ADAPTADO":
        lptaRule();
        break;
      case "MS":
        msRule();
        break;
      case "GENETICS":
        geneticsRule();
        break;
      case "TABU":        
        tabuSearchRule();
      break;


    }
  }

  // ── Setup-time helper ─────────────────────────────────────────────────────

  /// Returns the changeover duration required on [machineId] before processing
  /// [toJob], given that the machine's last job-state was [fromState].
  ///
  /// Returns [Duration.zero] when:
  ///   • no matrix is configured, or
  ///   • [fromState] is null (cold start / first job on this machine), or
  ///   • the specific (fromState, toState) cell is absent from the matrix.
  Duration _setupDuration(int machineId, String? fromState, String toState) {
    if (stateSetupMatrix == null || fromState == null) return Duration.zero;
    final minutes = stateSetupMatrix![machineId]?[fromState]?[toState];
    return minutes != null ? Duration(minutes: minutes) : Duration.zero;
  }

  // ── Dispatching rules ─────────────────────────────────────────────────────

  void sptRule()      => _schedule((a, b) => _averageProcessingTime(a).compareTo(_averageProcessingTime(b)));
  void lptRule()      => _schedule((a, b) => _averageProcessingTime(b).compareTo(_averageProcessingTime(a)));
  void eddRule()      => _schedule((a, b) => a.dueDate.compareTo(b.dueDate));
  void fcfsRule()     => _schedule((a, b) => a.availableDate.compareTo(b.availableDate));
  void wsptRule()     => _schedule((a, b) => calculateWSPT(b).compareTo(calculateWSPT(a)));

  // ── Dynamic (*_ADAPTADO) rules ────────────────────────────────────────────
  //
  // These previously partitioned jobs against `DateTime.now()` captured once
  // before the sort, which made the schedule depend on the wall clock at the
  // moment the button was pressed, and collapsed to `return 0` — discarding
  // the rule's own criterion — whenever two jobs were both unreleased.
  //
  // They are now real event-driven dispatch against the schedule's own
  // clock: see _runDynamic.

  void sptaRule() => _runDynamic(DispatchCriterion.spt);
  void eddaRule() => _runDynamic(DispatchCriterion.edd);
  void lptaRule() => _runDynamic(DispatchCriterion.lpt);
  void fifoaRule() => _runDynamic(DispatchCriterion.fifo);
  void wsptaRule() => _runDynamic(DispatchCriterion.wspt);

  // MS, CR and ATCS are dynamic by definition — their index depends on the
  // clock t — so they run through the same event-driven dispatch. They used
  // to be sorted once against each job's release date (MS, CR) or against
  // the schedule start (ATC, which also ignored priority and setups), which
  // froze the very quantity they measure.
  void msRule() => _runDynamic(DispatchCriterion.ms);
  void minslackRule() => _runDynamic(DispatchCriterion.ms);
  void crRule() => _runDynamic(DispatchCriterion.cr);
  void atcRule() => _runDynamic(DispatchCriterion.atcs);

  // ── Core scheduler ────────────────────────────────────────────────────────

  void _schedule(int Function(ParallelInput, ParallelInput) comparator) {
    inputJobs.sort(comparator);
    _assignJobsToMachines();
  }

  /// Event-driven dispatch across parallel machines.
  ///
  /// The decision point is the earliest moment ANY machine frees up. Among
  /// the jobs released by then, each is priced on its best machine through
  /// [_bestPlacementFor] — which runs the preemption engine, so the span
  /// being compared already includes the changeover out of that machine's
  /// current state and any split caused by a shift end, maintenance window
  /// or rest cap.
  void _runDynamic(DispatchCriterion criterion) {
    output.clear();
    machines.updateAll((key, value) => []);
    _machineContinuousUsage.updateAll((key, value) => Duration.zero);
    _machineLastState.updateAll((key, value) => null);
    _resetMachineAvailability();

    if (inputJobs.isEmpty) return;

    final pending = List<ParallelInput>.from(inputJobs);
    final AtcsParameters? atcs =
        criterion == DispatchCriterion.atcs ? _atcsParameters() : null;
    final sequenced = <ParallelInput>[];

    while (pending.isNotEmpty) {
      // The next decision happens when the first machine becomes free.
      DateTime decisionTime = machineAvailable.values
          .reduce((a, b) => a.isBefore(b) ? a : b);

      _ParallelPlacement? chosen;

      final selected = selectNext<ParallelInput>(
        pending: pending,
        decisionTime: decisionTime,
        releaseTime: (job) => job.availableDate,
        criterion: criterion,
        atcs: atcs,
        evaluate: (job, at) {
          final placement = _bestPlacementFor(job, notBefore: at);
          if (placement == null) return null;
          final span = placement.end.difference(at);
          return DispatchCandidate(
            job: job,
            start: placement.start,
            end: placement.end,
            span: span.isNegative ? Duration.zero : span,
            dueDate: job.dueDate,
            releaseDate: job.availableDate,
            priority: job.priority,
            jobId: job.jobId,
            setup: segmentsDuration(placement.setupSegments),
          );
        },
      );

      if (selected == null) {
        // No job is released yet at the earliest free machine. Advance the
        // clock to the next release instead of spinning.
        final DateTime next =
            earliestRelease(pending, (job) => job.availableDate)!;
        if (next.isAfter(decisionTime)) {
          machineAvailable.updateAll(
            (id, freeAt) => freeAt.isBefore(next) ? next : freeAt,
          );
          continue;
        }
        // Unreachable in practice: a release at or before the decision time
        // means that job was a candidate. Guard anyway — this runs on the UI
        // isolate, so a spin here would freeze the app.
        for (final job in pending) {
          final fallback = _bestPlacementFor(job, notBefore: decisionTime);
          if (fallback != null) _commitPlacement(fallback);
          sequenced.add(job);
        }
        pending.clear();
        break;
      }

      // Re-price the winner so the committed placement is the one it was
      // judged on. _bestPlacementFor is pure, so this recomputes rather than
      // re-decides.
      chosen = _bestPlacementFor(selected.job, notBefore: decisionTime);
      if (chosen != null) _commitPlacement(chosen);

      sequenced.add(selected.job);
      pending.remove(selected.job);
    }

    inputJobs = sequenced;
  }

  /// Assigns each job to the machine that minimises tardiness after accounting
  /// for the sequence-dependent setup time on that machine.
  ///
  /// Key difference from the original: before committing a job to a machine we
  /// add the setup duration s_{lastState → jobState} to the candidate start
  /// time.  The "best" machine is still the one that produces the earliest
  /// (adjusted) end time, but now setup cost is part of that calculation.
  ///
  /// After a machine is chosen, [_machineLastState] is updated so the next job
  /// assigned to that machine sees the correct "from" state.
  void _assignJobsToMachines() {
    _resetMachineAvailability();

    for (final job in inputJobs) {
      final placement = _bestPlacementFor(job, notBefore: null);
      if (placement != null) _commitPlacement(placement);
    }
  }

  /// Resets the earliest-free clock of every machine to the schedule start.
  ///
  /// Kept separate because the genetic and tabu searches re-enter the
  /// scheduler repeatedly and each pass must start from idle machines.
  void _resetMachineAvailability() {
    machineAvailable
      ..clear()
      ..addEntries(machines.keys.map((id) => MapEntry(id, startDate)));
  }

  /// Evaluates [job] on every machine that can run it and returns the best
  /// placement, WITHOUT committing anything.
  ///
  /// Nothing here writes to [machineAvailable], [_machineLastState],
  /// [_machineContinuousUsage], [machines] or [output] — the engine's
  /// `computeSegments` is a pure function of its arguments, so a candidate
  /// can be priced and then discarded. [_commitPlacement] does the writing.
  ///
  /// [notBefore], when given, forces the job to start no earlier than that
  /// moment; the dynamic rules pass the decision time so every contender is
  /// priced from the same instant.
  _ParallelPlacement? _bestPlacementFor(
    ParallelInput job, {
    required DateTime? notBefore,
  }) {
    _ParallelPlacement? best;

    for (final entry in job.durationsInMachines.entries) {
      final int machineId = entry.key;
      final Duration processingTime = entry.value;
      final DateTime freeAt = machineAvailable[machineId] ?? startDate;

      // Earliest moment when machine, job and (for dynamic rules) the
      // decision clock are all ready.
      DateTime candidateStart =
          job.availableDate.isAfter(freeAt) ? job.availableDate : freeAt;
      if (notBefore != null && notBefore.isAfter(candidateStart)) {
        candidateStart = notBefore;
      }
      candidateStart = _adjustForWorkingSchedule(candidateStart);

      // ── Sequence-dependent setup time ─────────────────────────────────
      // The machine needs s_{prevState → jobState} minutes of preparation
      // before it can start processing this job.  Setup runs on the machine
      // (occupies it) and, like processing, is scheduled through the
      // preemption engine as its own segmented block, so it's just as
      // sensitive to work-shift/rest/maintenance boundaries.
      final String toState = job.stateOnMachine(machineId);
      final Duration setup = _setupDuration(
        machineId,
        _machineLastState[machineId],
        toState,
      );

      List<ProcessingSegment> candidateSetupSegments = const [];
      DateTime processStart = candidateStart;
      Duration continuousUsageAfterSetup =
          _machineContinuousUsage[machineId] ?? Duration.zero;
      if (setup > Duration.zero) {
        final setupSchedule = _engineByMachine[machineId]!.computeSegments(
          earliestStart: candidateStart,
          totalDuration: setup,
          priorContinuousUsage: continuousUsageAfterSetup,
        );
        candidateSetupSegments = setupSchedule.segments;
        processStart = setupSchedule.completionTime;
        continuousUsageAfterSetup = candidateSetupSegments.length > 1
            ? candidateSetupSegments.last.duration
            : continuousUsageAfterSetup + candidateSetupSegments.single.duration;
      }

      // Split into segments wherever the work-shift end, a maintenance
      // window, or the continuous-use rest cap falls inside this job's
      // processing span on this candidate machine.
      final schedule = _engineByMachine[machineId]!.computeSegments(
        earliestStart: processStart,
        totalDuration: processingTime,
        priorContinuousUsage: continuousUsageAfterSetup,
        interruptible: job.isInterruptibleOnMachine(machineId),
      );
      final DateTime endTime = schedule.completionTime;
      final Duration delay = endTime.isAfter(job.dueDate)
          ? endTime.difference(job.dueDate)
          : Duration.zero;

      final candidate = _ParallelPlacement(
        job: job,
        machineId: machineId,
        processStart: processStart,
        schedule: schedule,
        setupSegments: candidateSetupSegments,
        continuousUsageAfterSetup: continuousUsageAfterSetup,
        delay: delay,
      );

      // Choose the machine that minimises delay, breaking ties on end time
      // and then on machine id, so the choice is deterministic.
      if (best == null ||
          delay < best.delay ||
          (delay == best.delay && endTime.isBefore(best.end)) ||
          (delay == best.delay &&
              endTime.isAtSameMomentAs(best.end) &&
              machineId < best.machineId)) {
        best = candidate;
      }
    }

    return best;
  }

  /// Writes a placement produced by [_bestPlacementFor] into the schedule.
  void _commitPlacement(_ParallelPlacement placement) {
    final job = placement.job;
    final machineId = placement.machineId;
    final schedule = placement.schedule;
    final DateTime endTime = placement.end;

    machineAvailable[machineId] = endTime;
    machines[machineId]?.add(Tuple2(placement.start, endTime));
    // ── Update last-state so the next job on this machine sees the correct
    //    "from" state in the setup matrix.
    _machineLastState[machineId] = job.stateOnMachine(machineId);
    // A pause anywhere within this job's segments already reset the
    // continuity streak; otherwise accumulate onto the running streak
    // that setup (if any) already left off at.
    _machineContinuousUsage[machineId] = schedule.segments.length > 1
        ? schedule.segments.last.duration
        : placement.continuousUsageAfterSetup +
            schedule.segments.single.duration;

    output.add(ParallelOutput(
      job.jobId,
      machineId,
      placement.processStart,
      endTime,
      placement.delay,
      job.dueDate,
      segments: schedule.segments,
      setupSegments: placement.setupSegments,
    ));
  }

  // ── Fitness / metric helpers ───────────────────────────────────────────────
  void _clearSchedule() {
      output.clear();
      machines.updateAll((key, value) => []);
    }

  double _averageProcessingTime(ParallelInput job) {
    return job.durationsInMachines.values.fold(0, (s, d) => s + d.inMinutes) /
        job.durationsInMachines.length;
  }

  /// Fits the ATCS parameters to this instance (see
  /// [AtcsParameters.calibrate]). Following Lee & Pinedo (1997) for
  /// parallel machines, the makespan estimate is the single-machine one
  /// spread over the m machines: (Σp̄_j + n·s̄) / m.
  AtcsParameters _atcsParameters() {
    final int n = inputJobs.length;
    final double meanProcessing = inputJobs.fold<double>(
            0,
            (sum, job) => sum +
                (job.durationsInMachines.isEmpty
                    ? 0
                    : _averageProcessingTime(job))) /
        n;
    // A pair's changeover depends on which machine they share, so it is
    // averaged over the machines both can run on; pairs with none are left
    // out — they can never follow each other.
    final double meanSetup = meanPairwiseSetupMinutes<ParallelInput>(
      inputJobs,
      (from, to) {
        final shared = to.durationsInMachines.keys
            .where(from.durationsInMachines.containsKey)
            .toList();
        if (shared.isEmpty) return null;
        final Duration total = shared.fold<Duration>(
          Duration.zero,
          (sum, m) =>
              sum +
              _setupDuration(m, from.stateOnMachine(m), to.stateOnMachine(m)),
        );
        return total ~/ shared.length;
      },
    );
    final int m = max(machines.length, 1);
    final double workMinutes = n * (meanProcessing + meanSetup) / m;

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



  double calculateWSPT(ParallelInput job) {
    final minMs = job.durationsInMachines.values
        .reduce((a, b) => a < b ? a : b)
        .inMilliseconds;
    return job.priority / minMs;
  }

  // ── Working-schedule helpers ───────────────────────────────────────────────

  DateTime _adjustForWorkingSchedule(DateTime start) {
    final ws = workingSchedule.value1;
    final we = workingSchedule.value2;
    if (start.hour < ws.hour || (start.hour == ws.hour && start.minute < ws.minute)) {
      return DateTime(start.year, start.month, start.day, ws.hour, ws.minute);
    } else if (start.hour > we.hour || (start.hour == we.hour && start.minute > we.minute)) {
      return DateTime(start.year, start.month, start.day + 1, ws.hour, ws.minute);
    }
    return start;
  }

  DateTime _adjustEndTimeForWorkingSchedule(DateTime start, Duration duration) {
    final we = workingSchedule.value2;
    final ws = workingSchedule.value1;
    final endOfDay = DateTime(start.year, start.month, start.day, we.hour, we.minute);
    final endTime = start.add(duration);
    if (endTime.isAfter(endOfDay)) {
      final remaining = endTime.difference(endOfDay);
      return DateTime(start.year, start.month, start.day + 1, ws.hour, ws.minute).add(remaining);
    }
    return endTime;
  }

  void printOutput() {
    for (final out in output) {
      print('Job ${out.jobId} → Machine ${out.machineId} | '
          'Start: ${out.startDate} | End: ${out.endDate} | '
          'Delay: ${out.delay.inMinutes} min | Due: ${out.dueDate}');
    }
  }

  // ── Genetic algorithm ─────────────────────────────────────────────────────

  void geneticsRule() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN PARALLEL MACHINES");

    const int populationSize = 5; // Reduced from 10
    const int generations = 10; // Reduced from 25
    const double mutationRate = 0.1;

    List<List<ParallelInput>> population = _initializePopulation(populationSize);
    List<ParallelInput> bestIndividual = [];
    Duration bestFitness = const Duration(days: 9999);

    for (int generation = 0; generation < generations; generation++) {
      final evaluated = population.map((ind) => Tuple2(ind, _evaluateFitness(ind))).toList();
      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = evaluated.first.value1;
      }

      population = _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    inputJobs = bestIndividual;
    _assignJobsToMachines();
  }

  List<List<ParallelInput>> _initializePopulation(int size) {
    return List.generate(size, (_) {
      final shuffled = List<ParallelInput>.from(inputJobs);
      shuffled.shuffle();
      return shuffled;
    });
  }

  /// Evaluates makespan for a candidate sequence, including setup times.
  ///
  /// Uses a local copy of last-states so that the evaluation is pure (it does
  /// not mutate [_machineLastState]).
  Duration _evaluateFitness(List<ParallelInput> jobSequence) {
    final Map<int, DateTime> machineAvail = {
      for (final id in machines.keys) id: startDate,
    };
    // Local tracking of last state per machine for this evaluation only.
    final Map<int, String?> localLastState = {
      for (final id in machines.keys) id: null,
    };

    DateTime latestEnd = startDate;

    for (final job in jobSequence) {
      DateTime bestEnd = DateTime(9999);
      int bestMachineId = -1;
      DateTime bestProcessStart = DateTime(9999);

      for (final entry in job.durationsInMachines.entries) {
        final machineId = entry.key;
        final processing = entry.value;

        DateTime candidateStart = job.availableDate.isAfter(machineAvail[machineId]!)
            ? job.availableDate
            : machineAvail[machineId]!;
        candidateStart = _adjustForWorkingSchedule(candidateStart);

        final toState = job.stateOnMachine(machineId);
        final setup = _setupDuration(machineId, localLastState[machineId], toState);
        final DateTime processStart = setup > Duration.zero
            ? _adjustForWorkingSchedule(candidateStart.add(setup))
            : candidateStart;

        final DateTime end = _adjustEndTimeForWorkingSchedule(processStart, processing);

        if (end.isBefore(bestEnd)) {
          bestEnd = end;
          bestMachineId = machineId;
          bestProcessStart = processStart;
        }
      }

      if (bestMachineId != -1) {
        machineAvail[bestMachineId] = bestEnd;
        localLastState[bestMachineId] = job.stateOnMachine(bestMachineId);
        if (bestEnd.isAfter(latestEnd)) latestEnd = bestEnd;
      }
    }

    return latestEnd.difference(startDate);
  }

  List<List<ParallelInput>> _generateNewPopulation(
    List<Tuple2<List<ParallelInput>, Duration>> evaluated,
    int size,
    double mutationRate,
  ) {
    return List.generate(size, (_) {
      final p1 = _selectParent(evaluated);
      final p2 = _selectParent(evaluated);
      var child = _crossover(p1, p2);
      if (Random().nextDouble() < mutationRate) child = _mutate(child);
      return child;
    });
  }

  List<ParallelInput> _selectParent(List<Tuple2<List<ParallelInput>, Duration>> evaluated) {
    const k = 5;
    final selected = List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    return selected.first.value1;
  }

  List<ParallelInput> _crossover(List<ParallelInput> p1, List<ParallelInput> p2) {
    final length = p1.length;
    final point = Random().nextInt(length);
    final taken = p1.sublist(0, point).map((j) => j.jobId).toSet();
    return [...p1.sublist(0, point), ...p2.where((j) => !taken.contains(j.jobId))];
  }

  List<ParallelInput> _mutate(List<ParallelInput> ind) {
    if (ind.length < 2) return ind;
    final i = Random().nextInt(ind.length);
    final j = Random().nextInt(ind.length);
    final tmp = ind[i];
    ind[i] = ind[j];
    ind[j] = tmp;
    return ind;
  }

  Duration evaluateFlujoTotalParallel(List<ParallelInput> jobSequence) {
    if (jobSequence.isEmpty) return Duration.zero;

    Map<int, DateTime> machineAvailability = {
      for (var id in machines.keys) id: startDate,
    };

    Duration totalFlow = Duration.zero;

    for (var job in jobSequence) {
      DateTime bestEndTime = DateTime(9999);
      int bestMachineId = -1;

      for (var entry in job.durationsInMachines.entries) {
        int machineId = entry.key;
        Duration processing = entry.value;

        DateTime available = machineAvailability[machineId] ?? startDate;

        DateTime start = job.availableDate.isAfter(available)
            ? job.availableDate
            : available;

        start = _adjustForWorkingSchedule(start);

        DateTime end = _adjustEndTimeForWorkingSchedule(start, processing);

        if (end.isBefore(bestEndTime)) {
          bestEndTime = end;
          bestMachineId = machineId;
        }
      }

      if (bestMachineId != -1) {
        machineAvailability[bestMachineId] = bestEndTime;
        totalFlow += bestEndTime.difference(startDate);
      }
    }

    return totalFlow;
  }

  void tabuSearchRule() {
    if (inputJobs.length < 2) {
      _clearSchedule();
      _assignJobsToMachines();
      return;
    }

    const int maxIterations = 200; // Reduced from 1000
    const int tabuTenure = 5; // Reduced from 10
    const int maxNoImprove = 20; // Reduced from 50
    const int vecinosPorIteracion = 5; // Reduced from 8

    final random = Random();

    List<ParallelInput> currentSolution = List.from(inputJobs)..shuffle();
    Duration currentFitness = evaluateFlujoTotalParallel(currentSolution);

    List<ParallelInput> bestSolution = List.from(currentSolution);
    Duration bestFitness = currentFitness;

    Map<String, int> tabuMap = {};
    int sinMejora = 0;

    final int n = currentSolution.length;

    for (int iter = 0; iter < maxIterations; iter++) {
      tabuMap.removeWhere((_, expiration) => expiration <= iter);

      List<ParallelInput>? bestNeighbor;
      Duration bestNeighborFitness = const Duration(days: 9999);

      int bestI = -1;
      int bestJ = -1;

      for (int k = 0; k < vecinosPorIteracion; k++) {
        int i = random.nextInt(n);
        int j = random.nextInt(n);

        while (i == j) {
          j = random.nextInt(n);
        }

        List<ParallelInput> neighbor = List.from(currentSolution);

        final temp = neighbor[i];
        neighbor[i] = neighbor[j];
        neighbor[j] = temp;

        Duration neighborFitness = evaluateFlujoTotalParallel(neighbor);

        String key = '${i}_$j';
        String reverseKey = '${j}_$i';

        bool isTabu =
            tabuMap.containsKey(key) || tabuMap.containsKey(reverseKey);

        bool aspiration = isTabu && neighborFitness < bestFitness;

        if ((!isTabu || aspiration) &&
            neighborFitness < bestNeighborFitness) {
          bestNeighbor = neighbor;
          bestNeighborFitness = neighborFitness;
          bestI = i;
          bestJ = j;
        }
      }

      if (bestNeighbor == null) {
        continue;
      }

      currentSolution = bestNeighbor;
      currentFitness = bestNeighborFitness;

      tabuMap['${bestI}_$bestJ'] = iter + tabuTenure;

      if (currentFitness < bestFitness) {
        bestFitness = currentFitness;
        bestSolution = List.from(currentSolution);
        sinMejora = 0;
      } else {
        sinMejora++;
      }

      if (sinMejora >= maxNoImprove) {
        currentSolution = List.from(bestSolution)..shuffle();
        currentFitness = evaluateFlujoTotalParallel(currentSolution);
        tabuMap.clear();
        sinMejora = 0;
      }
    }

    inputJobs = bestSolution;

    _clearSchedule();
    _assignJobsToMachines();

    print("Tiempo del tabu parallel: $bestFitness");
  }
}