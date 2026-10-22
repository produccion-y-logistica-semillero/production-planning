import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/scheduling/dynamic_dispatch.dart';
import 'package:production_planning/services/scheduling/preemption_engine.dart';
import 'dart:math';

class SingleMachineInput {
  final int jobId;
  final Duration machineDuration;
  final DateTime dueDate;
  final int priority;
  final DateTime availableDate;

  /// Product family / job-type label used as the row/column key in the
  /// state-based setup matrix (e.g. "A", "B", "C").
  final String jobState;

  /// Whether this job's processing on this machine may be split by a
  /// work-shift boundary, the continuous-use rest cap, or a maintenance
  /// window. False means its start is delayed until a window opens up that
  /// fits the whole duration uninterrupted.
  final bool interruptible;

  SingleMachineInput(
    this.jobId,
    this.machineDuration,
    this.dueDate,
    this.priority,
    this.availableDate, {
    this.jobState = 'A',
    this.interruptible = true,
  });
}

class SingleMachineOutput {
  final int jobId;
  final Duration processingTime;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime dueDate;
  final Duration delay;
  final List<ProcessingSegment> segments;
  final List<ProcessingSegment> setupSegments;

  SingleMachineOutput(
    this.jobId,
    this.processingTime,
    this.startDate,
    this.endDate,
    this.dueDate,
    this.delay, {
    List<ProcessingSegment>? segments,
    this.setupSegments = const [],
  }) : segments = segments ?? [ProcessingSegment(startDate, endDate)];
}

/// A fully computed placement for one job that has NOT been committed yet.
///
/// Produced by `SingleMachine._trial`, consumed by `SingleMachine._commit`.
/// Keeping the two apart is what lets the dynamic rules compare several
/// contenders and then schedule the winner with exactly the placement it was
/// judged on, instead of computing it twice and hoping the two agree.
class _SingleMachineTrial {
  final SingleMachineInput job;
  final List<ProcessingSegment> setupSegments;
  final SegmentedSchedule schedule;

  /// The machine's continuous-use streak once this job is done — carried
  /// into the next job on commit.
  final Duration continuousUsageAfter;

  const _SingleMachineTrial({
    required this.job,
    required this.setupSegments,
    required this.schedule,
    required this.continuousUsageAfter,
  });

  /// Where the machine actually starts working for this job: the setup, when
  /// there is one, otherwise the processing itself.
  DateTime get start =>
      setupSegments.isNotEmpty ? setupSegments.first.start : schedule.startDate;

  DateTime get end => schedule.completionTime;
}

class SingleMachine {
  final int machineId;
  final DateTime startDate;
  final Tuple2<TimeOfDay, TimeOfDay> workingSchedule; // like 8-17

  List<SingleMachineInput> input = [];
  List<SingleMachineOutput> output = [];

  // ── Setup-time state ──────────────────────────────────────────────────────
  // stateSetupMatrix: machineId → fromState → toState → minutes.
  // Only the entry for [machineId] is used; the map wrapper is kept so the
  // structure is identical to every other environment and the same
  // buildMachineStateSetupMatrix helper can populate it.
  final Map<int, Map<String, Map<String, int>>>? stateSetupMatrix;

  /// machineId → state letter (A-J) the machine starts this order in,
  /// before its first job.
  final Map<int, String> initialMachineState;

  // Tracks the job-state of the job that last ran on the machine.
  // Starts as the machine's configured initial state, so its first job can
  // pay a real changeover instead of always zero; with no initial state
  // configured, starts null (cold start → no setup cost for the first job),
  // same as before this field existed.
  late String? _lastJobState;

  // Machine inactivity support.
  // continueCapacity is interpreted as MINUTES of continuous processing
  // allowed before a mandatory rest of restTime — not a job count — so a
  // single long job can be preempted mid-processing, same as a run of
  // several short jobs.
  final List<MachineInactivityEntity> machineInactivities;
  final int continueCapacity;
  final Duration? restTime;

  /// How long the machine has been running continuously since its last
  /// pause (of any kind — rest, work-shift end, or maintenance).
  Duration _continuousUsage = Duration.zero;
  late final PreemptionEngine _preemptionEngine;

  SingleMachine(
    this.machineId,
    this.startDate,
    this.workingSchedule,
    this.input,
    String rule, {
    this.stateSetupMatrix,
    this.initialMachineState = const {},
    this.machineInactivities = const [],
    this.continueCapacity = 0,
    this.restTime,
  }) {
    _lastJobState = initialMachineState[machineId];
    _preemptionEngine = PreemptionEngine(
      workingSchedule: workingSchedule,
      maintenanceWindows: machineInactivities,
      continuousUseCap:
          continueCapacity > 0 ? Duration(minutes: continueCapacity) : Duration.zero,
      restDuration: restTime ?? Duration.zero,
    );
    switch (rule) {
      //case "JHONSON":jhonsonRule();break;
      case "EDD": eddRule(); break;
      case "SPT": sptRule(); break;
      case "LPT": lptRule(); break;
      case "FIFO": fifoRule(); break;
      case "WSPT": wsptRule(); break;
      case "EDD_ADAPTADO": eddRuleAdapted(); break;
      case "SPT_ADAPTADO": sptRuleAdapted(); break;
      case "LPT_ADAPTADO": lptRuleAdapted(); break;
      case "FIFO_ADAPTADO": fifoRuleAdapted(); break;
      case "WSPT_ADAPTADO": wsptRuleAdapted(); break;
      case "MINSLACK": scheduleMinimumSlack(); break;
      case "MS": scheduleMinimumSlack(); break;
      case "CR": scheduleCriticalRatio(); break;
      case "ATCS": scheduleATCS(); break;
      case "GENETICS": scheduleGeneticAlgorithm(); break;
      case "TABU": scheduleTabuSearch(); break;
      default:
        // Without this an unknown rule silently produced an empty schedule,
        // which the UI renders as "no hay nada que programar" rather than as
        // the configuration error it is.
        throw ArgumentError('Regla de despacho desconocida: "$rule"');
    }
  }

  // ── Setup-time helper ─────────────────────────────────────────────────────

  /// Returns s_{fromState → toState} for [machineId].
  /// Returns [Duration.zero] on cold start (null fromState) or missing cell.
  Duration _setupDuration(String? fromState, String toState) {
    if (stateSetupMatrix == null || fromState == null) return Duration.zero;
    final minutes = stateSetupMatrix![machineId]?[fromState]?[toState];
    return minutes != null ? Duration(minutes: minutes) : Duration.zero;
  }

  // ── Working-schedule helpers ───────────────────────────────────────────────

  DateTime _getStartTime(DateTime availableDate) {
    final workStart = DateTime(
      startDate.year, startDate.month, startDate.day,
      workingSchedule.value1.hour, workingSchedule.value1.minute,
    );
    return availableDate.isBefore(workStart) ? workStart : availableDate;
  }

  /// Pushes [current] to the next working-day start if adding [duration]
  /// would exceed the end of the current working day.
  DateTime _getAvailableStartTime(DateTime current, Duration duration) {
    final endMinutes =
        workingSchedule.value2.hour * 60 + workingSchedule.value2.minute;
    final currentMinutes =
        current.hour * 60 + current.minute + duration.inMinutes;
    if (currentMinutes > endMinutes) {
      final next = current.add(const Duration(days: 1));
      return DateTime(next.year, next.month, next.day,
          workingSchedule.value1.hour, workingSchedule.value1.minute);
    }
    return current;
  }

  // ── Core assignment ───────────────────────────────────────────────────────

  /// Simulates [job] starting no earlier than [at], WITHOUT committing
  /// anything — no field of this class is written, nothing is appended to
  /// [output].
  ///
  /// This is safe to call repeatedly on competing candidates because
  /// [PreemptionEngine.computeSegments] is a pure function of its arguments;
  /// all the state that evolves during scheduling lives here and is passed
  /// in explicitly ([_lastJobState], [_continuousUsage]).
  ///
  /// The dynamic (*_ADAPTADO) rules use it to compare contenders; [_assignJob]
  /// uses it to compute the placement it then commits, so the schedule a
  /// candidate was chosen for is exactly the schedule it gets.
  _SingleMachineTrial _trial(SingleMachineInput job, DateTime at) {
    // 1. Setup for the transition out of the machine's current state.
    final setup = _setupDuration(_lastJobState, job.jobState);

    // 2. Setup then processing, both through the preemption engine. The
    //    job's interruption flag governs the pair: interruptible → each may
    //    be split by a shift end / maintenance / rest cap; not
    //    interruptible → one contiguous block, processing starting the
    //    instant setup ends.
    final placed = _preemptionEngine.computeSetupAndProcessing(
      earliestStart: at,
      setupDuration: setup,
      processingDuration: job.machineDuration,
      priorContinuousUsage: _continuousUsage,
      interruptible: job.interruptible,
    );

    return _SingleMachineTrial(
      job: job,
      setupSegments: placed.setupSegments,
      schedule: placed.processing,
      continuousUsageAfter: placed.continuousUsageAfter,
    );
  }

  /// Commits a placement produced by [_trial]: appends the output row and
  /// advances the machine's state. Returns the new schedule pointer.
  DateTime _commit(_SingleMachineTrial trial) {
    final job = trial.job;
    final schedule = trial.schedule;
    final DateTime end = schedule.completionTime;
    final Duration delay = end.isAfter(job.dueDate)
        ? end.difference(job.dueDate)
        : Duration.zero;

    output.add(SingleMachineOutput(
      job.jobId, job.machineDuration, schedule.startDate, end, job.dueDate,
      delay,
      segments: schedule.segments,
      setupSegments: trial.setupSegments,
    ));

    // Remember this job's state and continuous-usage streak for the next
    // iteration (a pause during this job already reset the streak).
    _lastJobState = job.jobState;
    _continuousUsage = trial.continuousUsageAfter;

    return end;
  }

  /// Schedules [job] at [scheduleTime], prepending the setup duration
  /// s_{_lastJobState → job.jobState} before processing.
  ///
  /// Returns the updated schedule pointer (= end of this job's processing).
  DateTime _assignJob(SingleMachineInput job, DateTime scheduleTime) =>
      _commit(_trial(job, scheduleTime));

  /// Pushes [dt] to the start of the next working day if it falls outside
  /// working hours (i.e. at or after day-end).
  DateTime _alignToWorkingHours(DateTime dt) {
    final endH = workingSchedule.value2.hour;
    final endM = workingSchedule.value2.minute;
    if (dt.hour > endH || (dt.hour == endH && dt.minute >= endM)) {
      final next = dt.add(const Duration(days: 1));
      return DateTime(next.year, next.month, next.day,
          workingSchedule.value1.hour, workingSchedule.value1.minute);
    }
    return dt;
  }

  // ── Dispatching rules ─────────────────────────────────────────────────────

  void eddRule() {
    input.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    _runSequence();
  }

  void sptRule() {
    input.sort((a, b) => a.machineDuration.compareTo(b.machineDuration));
    _runSequence();
  }

  void lptRule() {
    input.sort((a, b) => b.machineDuration.compareTo(a.machineDuration));
    _runSequence();
  }

  void fifoRule() {
    input.sort((a, b) => a.availableDate.compareTo(b.availableDate));
    _runSequence();
  }

  void wsptRule() {
    input.sort((a, b) =>
        (b.priority / b.machineDuration.inMinutes)
            .compareTo(a.priority / a.machineDuration.inMinutes));
    _runSequence();
  }

  // ── Dynamic rules ─────────────────────────────────────────────────────────
  //
  // These do NOT pre-sort. They decide one job at a time, at the moment the
  // machine frees up, among the jobs released by then, comparing each
  // contender's EFFECTIVE span — setup out of the machine's current state
  // plus processing plus whatever the preemption engine stretches it by. See
  // _runDynamic and lib/services/scheduling/dynamic_dispatch.dart.
  //
  // MS, CR and ATCS belong here too: the literature defines their index in
  // terms of the clock t. They used to be sorted once — MS and CR against
  // each job's release date, ATCS against nominal processing times with no
  // release gate and no setup term — which froze the very quantity they
  // measure. Now t is the schedule's clock at each decision, so a machine
  // paused for maintenance eats into every pending job's slack.

  void eddRuleAdapted() => _runDynamic(DispatchCriterion.edd);
  void sptRuleAdapted() => _runDynamic(DispatchCriterion.spt);
  void lptRuleAdapted() => _runDynamic(DispatchCriterion.lpt);
  void fifoRuleAdapted() => _runDynamic(DispatchCriterion.fifo);
  void wsptRuleAdapted() => _runDynamic(DispatchCriterion.wspt);

  void scheduleMinimumSlack() => _runDynamic(DispatchCriterion.ms);
  void scheduleCriticalRatio() => _runDynamic(DispatchCriterion.cr);
  void scheduleATCS() => _runDynamic(DispatchCriterion.atcs);

  // ── Sequential runner ─────────────────────────────────────────────────────

  /// Walks the (already-sorted) [input] list in order, calling [_assignJob]
  /// for each job and threading the schedule-time pointer through.
  ///
  /// This is the single place where setup times are injected: [_assignJob]
  /// prepends s_{prev → current} before every job's processing window.
  void _runSequence() {
    // Reset state tracking so re-entrant calls (e.g. from genetics) start clean.
    _lastJobState = initialMachineState[machineId];
    _continuousUsage = Duration.zero;
    output.clear();

    if (input.isEmpty) return;
    DateTime scheduleTime = _getStartTime(input.first.availableDate);

    for (final job in input) {
      scheduleTime = _assignJob(job, scheduleTime);
    }
  }

  // ── Dynamic runner ────────────────────────────────────────────────────────

  /// Event-driven dispatch: instead of freezing an order up front, decide the
  /// next job each time the machine frees up.
  ///
  /// At every decision point only the jobs that can EFFECTIVELY start
  /// earliest compete (see selectNext), and each contender is simulated
  /// through the preemption engine so the quantity
  /// being compared is its real occupancy of the machine — including the
  /// changeover out of whatever state the previous job left, and including
  /// any split caused by a shift boundary, maintenance window or rest cap.
  /// That is what makes a job with a short nominal processing time but an
  /// expensive setup lose to one that runs clean.
  void _runDynamic(DispatchCriterion criterion) {
    // Same reset as _runSequence: the genetic and tabu searches re-enter the
    // scheduler repeatedly and must each start from a clean machine.
    _lastJobState = initialMachineState[machineId];
    _continuousUsage = Duration.zero;
    output.clear();

    if (input.isEmpty) return;

    final pending = List<SingleMachineInput>.from(input);
    final DateTime firstRelease =
        earliestRelease(pending, (job) => job.availableDate)!;
    DateTime scheduleTime = _getStartTime(firstRelease);
    final AtcsParameters? atcs = criterion == DispatchCriterion.atcs
        ? _atcsParameters(scheduleTime)
        : null;

    // Rebuilt in dispatch order so `input` reflects the sequence actually
    // scheduled — callers (and the genetic algorithm) read it as the result.
    final sequenced = <SingleMachineInput>[];

    while (pending.isNotEmpty) {
      final selected = selectNext<SingleMachineInput>(
        pending: pending,
        decisionTime: scheduleTime,
        releaseTime: (job) => job.availableDate,
        criterion: criterion,
        atcs: atcs,
        evaluate: (job, at) {
          final trial = _trial(job, at);
          return DispatchCandidate(
            job: job,
            start: trial.start,
            end: trial.end,
            span: trial.end.difference(at).isNegative
                ? Duration.zero
                : trial.end.difference(at),
            dueDate: job.dueDate,
            releaseDate: job.availableDate,
            priority: job.priority,
            jobId: job.jobId,
            setup: segmentsDuration(trial.setupSegments),
          );
        },
      );

      if (selected == null) {
        // Unreachable in practice: selectNext only returns null for an empty
        // list (it throws when every job is unplaceable). Guard anyway —
        // this runs on the UI isolate, so a spin here would freeze the app.
        // Schedule what is left in order rather than looping or dropping it.
        for (final job in pending) {
          scheduleTime = _assignJob(job, scheduleTime);
          sequenced.add(job);
        }
        pending.clear();
        break;
      }

      // selectNext is non-delay on effective starts: the winner is a job
      // that can really begin at t* = the earliest instant any job can, so
      // if the rule's favourite was held back by an interruption another
      // job took the machine, and if nobody could start at scheduleTime the
      // clock has jumped to t*. Re-run the trial from the same instant it
      // was judged from, so the committed placement is the one compared.
      final job = selected.job;
      scheduleTime = _assignJob(
        job,
        evaluationTime(job, scheduleTime, (j) => j.availableDate),
      );
      sequenced.add(job);
      pending.remove(job);
    }

    input = sequenced;
  }

  // ── Metric helpers ────────────────────────────────────────────────────────

  /// Fits the ATCS parameters to this instance (see
  /// [AtcsParameters.calibrate]). The makespan estimate is the textbook
  /// single-machine one, Σp_j + n·s̄, turned into calendar time on this
  /// machine so it is comparable with the due dates.
  AtcsParameters _atcsParameters(DateTime start) {
    final int n = input.length;
    final double meanProcessing = input.fold<double>(
            0, (sum, job) => sum + job.machineDuration.inSeconds / 60.0) /
        n;
    final double meanSetup = meanPairwiseSetupMinutes<SingleMachineInput>(
      input,
      (from, to) => _setupDuration(from.jobState, to.jobState),
    );
    final double workMinutes = n * (meanProcessing + meanSetup);

    return AtcsParameters.calibrate(
      start: start,
      dueDates: input.map((job) => job.dueDate),
      meanProcessingMinutes: meanProcessing,
      meanSetupMinutes: meanSetup,
      makespanMinutes: calendarMinutes(
        _preemptionEngine,
        start,
        Duration(minutes: workMinutes.round()),
      ),
    );
  }

  // ── Genetic algorithm ─────────────────────────────────────────────────────

  void scheduleGeneticAlgorithm() {
    print("EJECUTANDO ALGORITMO GENÉTICO EN SINGLE MACHINE");

    const int populationSize = 50;
    const int generations = 100;
    const double mutationRate = 0.1;

    List<List<SingleMachineInput>> population =
        _initializePopulation(populationSize);
    List<SingleMachineInput> bestIndividual = [];
    Duration bestFitness = const Duration(days: 9999);

    for (int generation = 0; generation < generations; generation++) {
      final evaluated = population
          .map((ind) => Tuple2(ind, _evaluateFitness(ind)))
          .toList();
      evaluated.sort((a, b) => a.value2.compareTo(b.value2));

      if (evaluated.first.value2 < bestFitness) {
        bestFitness = evaluated.first.value2;
        bestIndividual = evaluated.first.value1;
      }

      population =
          _generateNewPopulation(evaluated, populationSize, mutationRate);
    }

    input = bestIndividual;
    _runSequence();
  }

  List<List<SingleMachineInput>> _initializePopulation(int size) {
    return List.generate(size, (_) {
      final shuffled = List<SingleMachineInput>.from(input);
      shuffled.shuffle();
      return shuffled;
    });
  }

  /// Pure fitness evaluation — does NOT mutate [output] or [_lastJobState].
  /// Simulates [_runSequence] internally with a local state tracker so that
  /// concurrent genetic evaluations don't interfere with each other.
  Duration _evaluateFitness(List<SingleMachineInput> sequence) {
    if (sequence.isEmpty) return Duration.zero;

    String? localLastState;
    DateTime current = _getStartTime(sequence.first.availableDate);
    Duration totalTime = Duration.zero;

    for (final job in sequence) {
      // Mirror _assignJob logic without writing to output.
      final setup = _setupDurationRaw(localLastState, job.jobState);

      DateTime processStart = current;
      if (setup > Duration.zero) {
        processStart = _getAvailableStartTime(current, setup);
        processStart = processStart.add(setup);
        processStart = _alignToWorkingHours(processStart);
      }

      processStart = _getAvailableStartTime(processStart, job.machineDuration);
      final end = processStart.add(job.machineDuration);
      totalTime += end.difference(startDate);
      localLastState = job.jobState;
      current = end;
    }

    return totalTime;
  }

  /// Raw setup lookup that doesn't touch instance state — safe to call from
  /// fitness evaluations running over different candidate sequences.
  Duration _setupDurationRaw(String? fromState, String toState) {
    if (stateSetupMatrix == null || fromState == null) return Duration.zero;
    final minutes = stateSetupMatrix![machineId]?[fromState]?[toState];
    return minutes != null ? Duration(minutes: minutes) : Duration.zero;
  }

  List<List<SingleMachineInput>> _generateNewPopulation(
    List<Tuple2<List<SingleMachineInput>, Duration>> evaluated,
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

  List<SingleMachineInput> _selectParent(
      List<Tuple2<List<SingleMachineInput>, Duration>> evaluated) {
    const k = 5;
    final selected =
        List.generate(k, (_) => evaluated[Random().nextInt(evaluated.length)]);
    selected.sort((a, b) => a.value2.compareTo(b.value2));
    return selected.first.value1;
  }

  List<SingleMachineInput> _crossover(
      List<SingleMachineInput> p1, List<SingleMachineInput> p2) {
    final length = p1.length;
    final point = Random().nextInt(length);
    final taken = p1.sublist(0, point).map((j) => j.jobId).toSet();
    return [
      ...p1.sublist(0, point),
      ...p2.where((j) => !taken.contains(j.jobId)),
    ];
  }

  List<SingleMachineInput> _mutate(List<SingleMachineInput> individual) {
    if (individual.length < 2) return individual;
    final i = Random().nextInt(individual.length);
    final j = Random().nextInt(individual.length);
    final tmp = individual[i];
    individual[i] = individual[j];
    individual[j] = tmp;
    return individual;
  }

  Duration calcularMakespanTabuSingle(List<SingleMachineInput> jobSequence) {
    DateTime current = _getStartTime(jobSequence.first.availableDate);

    for (var job in jobSequence) {
      current = _getAvailableStartTime(current, job.machineDuration);
      current = current.add(job.machineDuration);
    }

    return current.difference(_getStartTime(jobSequence.first.availableDate));
  }

  Duration evaluateFlujoTotal(List<SingleMachineInput> seq) {
    DateTime current = _getStartTime(seq.first.availableDate);
    DateTime origin = current;

    Duration sumCompletions = Duration.zero;
    for (var job in seq) {
      current = _getAvailableStartTime(current, job.machineDuration);
      current = current.add(job.machineDuration);
      sumCompletions += current.difference(origin);
    }
    return sumCompletions;
  }

  void _generateOutput(List<SingleMachineInput> solution) {
    output.clear();
    var time = evaluateFlujoTotal(solution);
    print("Tiempo del tabu: $time");

    if (solution.isEmpty) return;

    DateTime scheduleTime = _getStartTime(solution.first.availableDate);

    for (var job in solution) {
      print("job ${job.jobId} → duración: ${job.machineDuration} | available: ${job.availableDate} | due: ${job.dueDate}");

      DateTime start = _getAvailableStartTime(scheduleTime, job.machineDuration);
      DateTime end = start.add(job.machineDuration);
      Duration delay = end.isAfter(job.dueDate) ? end.difference(job.dueDate) : Duration.zero;

      output.add(
        SingleMachineOutput(
          job.jobId,
          job.machineDuration,
          start,
          end,
          job.dueDate,
          delay,
        ),
      );

      scheduleTime = end;
    }
  }

  void scheduleTabuSearch() {
    if (input.length < 2) {
      _generateOutput(input);
      return;
    }
    const int maxIterations = 200;
    const int tabuTenure = 10;
    const int maxNoImprove = 20;
    const int vecinosPorIteracion = 7;

    // Solución inicial aleatoria
    List<SingleMachineInput> currentSolution = List.from(input)..shuffle();

    Duration currentFitness = evaluateFlujoTotal(currentSolution);
    List<SingleMachineInput> bestSolution = List.from(currentSolution);

    Duration bestFitness = currentFitness;
    Map<String, int> tabuMap = {};

    int sinMejora = 0;
    final random = Random();
    int n = currentSolution.length;

    for (int iter = 0; iter < maxIterations; iter++) {
      tabuMap.removeWhere((_, exp) => exp <= iter);

      List<SingleMachineInput>? bestNeighbor;
      Duration bestNeighborFitness = const Duration(days: 9999);
      int bestI = -1;
      int bestJ = -1;

      for (int k = 0; k < vecinosPorIteracion; k++) {
        int i = random.nextInt(n);
        int j = random.nextInt(n);

        while (i == j) {
          j = random.nextInt(n);
        }

        List<SingleMachineInput> neighbor = List.from(currentSolution);
        final temp = neighbor[i];
        neighbor[i] = neighbor[j];
        neighbor[j] = temp;

        Duration neighborFitness = evaluateFlujoTotal(neighbor);
        String key = '${i}_$j';
        bool isTabu = tabuMap.containsKey(key);
        bool aspiration = isTabu && neighborFitness < bestFitness;

        if ((!isTabu || aspiration) && neighborFitness < bestNeighborFitness) {
          bestNeighborFitness = neighborFitness;
          bestNeighbor = neighbor;
          bestI = i;
          bestJ = j;
        }
      }

      if (bestNeighbor == null) {
        continue;
      }

      currentSolution = bestNeighbor;
      currentFitness = bestNeighborFitness;
      tabuMap['${bestI}_$bestJ'] = iter + tabuTenure + random.nextInt(6) - 2;

      if (currentFitness < bestFitness) {
        bestFitness = currentFitness;
        bestSolution = List.from(currentSolution);
        sinMejora = 0;
      } else {
        sinMejora++;
      }

      if (sinMejora >= maxNoImprove) {
        currentSolution = List.from(bestSolution)..shuffle();
        currentFitness = evaluateFlujoTotal(currentSolution);
        tabuMap.clear();
        sinMejora = 0;
      }
    }

    input = bestSolution;
    _generateOutput(input);
  }

}