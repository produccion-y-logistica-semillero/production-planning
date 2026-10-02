// lib/services/scheduling/dynamic_dispatch.dart
//
// Shared core of every DYNAMIC dispatching rule: the *_ADAPTADO family and
// the three literature rules whose priority index depends on the clock —
// MS (minimum slack), CR (critical ratio) and ATCS (apparent tardiness cost
// with setups).
//
// A STATIC rule sorts every job once, up front, by a fixed attribute
// (processing time, due date, ...) and then walks that frozen list. A DYNAMIC
// rule decides one job at a time, at the moment the machine actually frees
// up, using what is true *then*:
//
//   1. only jobs already released at the decision time compete,
//   2. each contender is simulated through the PreemptionEngine, so the
//      quantity being compared is its EFFECTIVE span — setup from the
//      machine's current state, plus processing, plus whatever a shift
//      boundary / maintenance window / rest cap stretches it by,
//   3. indices that involve the clock (slack, critical ratio, ATCS) are
//      evaluated at the decision time t — the schedule's own clock, never
//      the wall clock — so time the machine spends paused is time every
//      pending job loses.
//
// The second point is what "adaptado" was always meant to mean (see
// SetupTimeHelper.effectiveProcessingTime in lib/services/setup_time_matrix.dart)
// and what makes these rules produce a different schedule from their static
// counterparts instead of an identical one. For MS, CR and ATCS the third is
// the only honest way to read them: the literature defines all three in
// terms of t, so sorting them once at t = 0 is not the rule at all.
//
// With no setups and no calendar effects every index here reduces exactly
// to its textbook form, which is what the tests pin down.
//
// This file holds only the parts that do not depend on the environment: the
// release gate, the criteria, and deterministic tie-breaking. Each algorithm
// supplies its own `evaluate` closure, since the environments have no
// common job type.

import 'dart:math';

import 'package:production_planning/services/scheduling/preemption_engine.dart';

/// The ordering criterion a dynamic rule applies among the jobs that are
/// released at the decision time.
enum DispatchCriterion {
  /// Shortest effective span first.
  spt,

  /// Longest effective span first.
  lpt,

  /// Earliest due date first; ties broken by shortest span.
  edd,

  /// Earliest release date first; ties broken by shortest span.
  fifo,

  /// Highest priority-per-minute-of-effective-span first.
  wspt,

  /// Minimum slack first: `d_j − C_j(t)`, the time the job would still have
  /// in hand if dispatched now. See [slackMinutes].
  ms,

  /// Smallest critical ratio first: `(d_j − t) / work still needed`. Below
  /// 1 the job cannot make its due date. See [criticalRatio].
  cr,

  /// Highest ATCS index first (Lee, Bhaskaran & Pinedo, 1997). Needs
  /// [AtcsParameters]. See [atcsLogIndex].
  atcs,
}

/// One job simulated at a decision time, with everything the criteria need.
///
/// [span] is the whole point of the class: it is `end - decisionTime`, so it
/// carries the setup cost from the machine's current state AND the stretching
/// caused by every interruption the PreemptionEngine had to work around. A
/// job with a short nominal processing time but an expensive changeover, or
/// one that a maintenance window would split, reports a long span and loses
/// to a job that runs clean.
class DispatchCandidate<T> {
  final T job;

  /// Effective start — the beginning of setup when there is one, otherwise
  /// the beginning of processing.
  final DateTime start;

  /// Completion time after setup, processing and every interruption.
  final DateTime end;

  /// `end - decisionTime`. Never negative.
  final Duration span;

  final DateTime dueDate;
  final DateTime releaseDate;
  final int priority;

  /// Stable identity, used as the final tie-break so a schedule does not
  /// depend on `List.sort`'s unstable ordering of equal elements.
  final int jobId;

  /// Changeover this job would incur at this decision, out of the machine's
  /// current state — summed over the route in multi-stage environments.
  /// Already inside [span]; ATCS also prices it on its own.
  final Duration setup;

  /// Nominal processing the job still has to do AFTER this candidate
  /// completes. Non-zero only in operation-level environments (Job Shop,
  /// Open Shop), where a candidate is one operation of a longer job; the
  /// slack-based criteria charge it against the due date.
  final Duration remainingWork;

  const DispatchCandidate({
    required this.job,
    required this.start,
    required this.end,
    required this.span,
    required this.dueDate,
    required this.releaseDate,
    required this.priority,
    required this.jobId,
    this.setup = Duration.zero,
    this.remainingWork = Duration.zero,
  });
}

/// Scaling parameters of the ATCS index.
///
/// [k1] scales the due-date look-ahead and [k2] the setup penalty. Lee,
/// Bhaskaran & Pinedo fit both to the instance rather than fixing them;
/// [AtcsParameters.calibrate] applies their published fit.
class AtcsParameters {
  /// Floor for [k2]; see [AtcsParameters.calibrate].
  static const double minK2 = 0.01;

  final double k1;
  final double k2;

  /// p̄ — mean nominal processing time, in minutes. Never below 1.
  final double meanProcessingMinutes;

  /// s̄ — mean setup between two distinct jobs, in minutes. Zero when the
  /// instance has no setups, which switches the setup factor off.
  final double meanSetupMinutes;

  const AtcsParameters({
    required this.k1,
    required this.k2,
    required this.meanProcessingMinutes,
    required this.meanSetupMinutes,
  });

  /// Fits K₁ and K₂ to the instance, following Lee, Bhaskaran & Pinedo
  /// (1997) as presented in Pinedo, *Scheduling*, §14.2:
  ///
  ///     τ  = 1 − d̄ / Ĉmax              due-date tightness
  ///     R  = (d_max − d_min) / Ĉmax     due-date range
  ///     η  = s̄ / p̄                      setup severity
  ///     K₁ = 4.5 + R   if R ≤ 0.5,   6 − 2R   otherwise
  ///     K₂ = τ / (2·√η)
  ///
  /// Due dates are measured from [start], and [makespanMinutes] (Ĉmax) must
  /// be in the same calendar minutes — nights and weekends count on both
  /// sides of the ratio, or every instance would look loose.
  ///
  /// τ and R are clamped to [0, 1], the range the fit was derived on.
  /// Outside it the formulas turn negative — K₁ for R > 3, K₂ whenever the
  /// due dates are looser than the makespan — and a negative scale would
  /// reward exactly what the index is meant to penalise. K₂ is floored at
  /// [minK2] for the same reason, so τ = 0 (every due date comfortably past
  /// the makespan: tardiness is not in play) degrades to "cheapest
  /// changeover first", which is the sensible limit.
  factory AtcsParameters.calibrate({
    required DateTime start,
    required Iterable<DateTime> dueDates,
    required double meanProcessingMinutes,
    required double meanSetupMinutes,
    required double makespanMinutes,
  }) {
    final double p = max(meanProcessingMinutes, 1.0);
    final double s = max(meanSetupMinutes, 0.0);
    final double cmax = max(makespanMinutes, 1.0);

    double tau = 0.5;
    double range = 0.0;
    final relative =
        dueDates.map((d) => _minutes(d.difference(start))).toList();
    if (relative.isNotEmpty) {
      final double mean = relative.reduce((a, b) => a + b) / relative.length;
      tau = 1 - mean / cmax;
      range = (relative.reduce(max) - relative.reduce(min)) / cmax;
    }
    tau = tau.clamp(0.0, 1.0);
    range = range.clamp(0.0, 1.0);

    final double k1 = range <= 0.5 ? 4.5 + range : 6 - 2 * range;
    final double eta = s / p;
    final double k2 = eta > 0 ? max(tau / (2 * sqrt(eta)), minK2) : 1.0;

    return AtcsParameters(
      k1: k1,
      k2: k2,
      meanProcessingMinutes: p,
      meanSetupMinutes: s,
    );
  }
}

double _minutes(Duration d) => d.inSeconds / 60.0;

/// Total working time in [segments].
Duration segmentsDuration(Iterable<ProcessingSegment> segments) =>
    segments.fold(Duration.zero, (sum, s) => sum + s.duration);

/// Calendar minutes that [work] of machine time takes on [engine] from
/// [start] — shift ends, maintenance and rests included.
///
/// Used to turn a makespan estimate expressed in working minutes into the
/// calendar minutes due dates are measured in. Falls back to the raw work
/// when the calendar cannot place it within the engine's horizon: this is
/// an estimate feeding a heuristic, not a schedule, and must not be what
/// makes scheduling fail.
double calendarMinutes(PreemptionEngine engine, DateTime start, Duration work) {
  if (work <= Duration.zero) return 0;
  try {
    final DateTime end = engine
        .computeSegments(earliestStart: start, totalDuration: work)
        .completionTime;
    return _minutes(end.difference(start));
  } on SchedulingHorizonException {
    return _minutes(work);
  }
}

/// Mean of [setup] over every ordered pair of distinct jobs, in minutes.
///
/// This is s̄ as Lee, Bhaskaran & Pinedo define it. Pairs for which [setup]
/// returns null — two jobs that can never follow each other on any machine
/// — are left out rather than counted as free.
double meanPairwiseSetupMinutes<T>(
  List<T> jobs,
  Duration? Function(T from, T to) setup,
) {
  double total = 0;
  int count = 0;
  for (int i = 0; i < jobs.length; i++) {
    for (int j = 0; j < jobs.length; j++) {
      if (i == j) continue;
      final Duration? s = setup(jobs[i], jobs[j]);
      if (s == null) continue;
      total += _minutes(s);
      count++;
    }
  }
  return count == 0 ? 0 : total / count;
}

/// MS index, in minutes: `d_j − C_j(t) − R_j`.
///
/// `C_j(t)` is the simulated completion, so the slack already reflects the
/// changeover and every interruption the job would run into. With neither,
/// `C_j(t) = t + p_j` and this is the textbook `d_j − t − p_j`.
///
/// Not clamped at zero: a job with negative slack is already going to be
/// late and must rank ahead of one that still has time. Clamping — as the
/// old static versions did — tied every late job at 0.
double slackMinutes<T>(DispatchCandidate<T> c) =>
    _minutes(c.dueDate.difference(c.end)) - _minutes(c.remainingWork);

/// CR index: `(d_j − t) / (span + R_j)` — time left over work still needed.
///
/// Not clamped either: past its due date `d_j − t` is negative, so a late
/// job ranks ahead of every job still on time.
double criticalRatio<T>(DispatchCandidate<T> c, DateTime decisionTime) {
  final double work = max(_minutes(c.span + c.remainingWork), 1.0);
  return _minutes(c.dueDate.difference(decisionTime)) / work;
}

/// Natural log of the ATCS index:
///
///     I_j(t) = (w_j / p_j) · exp(−max(0, d_j − p_j − t) / (K₁·p̄))
///                          · exp(−s_ij / (K₂·s̄))
///
/// read against the simulated placement:
///
///   * `p_j` is the machine time the job occupies once started, minus its
///     setup: processing plus every pause the calendar forces into it.
///   * `d_j − p_j − t` is `d_j − C_j(t) + s_ij − R_j`: the slack the job
///     would have if the changeover were free, which is how the formula
///     keeps the setup out of the look-ahead term and in its own factor.
///   * `s_ij` is the changeover out of the machine's current state.
///
/// With no interruptions `C_j(t) = t + s_ij + p_j` and every term is the
/// textbook one.
///
/// Logs, not the index itself: with a tight K₂ the setup factor underflows
/// to 0.0 for every job that needs a changeover, which would tie them all.
/// Comparing logs keeps the order. Priority is the weight `w_j`; a
/// non-positive priority is treated as a vanishingly small weight so those
/// jobs still order among themselves.
double atcsLogIndex<T>(DispatchCandidate<T> c, AtcsParameters params) {
  final double setup = _minutes(c.setup);
  final double processing =
      max(_minutes(c.end.difference(c.start)) - setup, 1.0);
  final double slack = _minutes(c.dueDate.difference(c.end)) +
      setup -
      _minutes(c.remainingWork);
  final double weight = c.priority > 0 ? c.priority.toDouble() : 1e-6;

  double index = log(weight) -
      log(processing) -
      max(slack, 0.0) / (params.k1 * params.meanProcessingMinutes);
  if (params.meanSetupMinutes > 0) {
    index -= setup / (params.k2 * params.meanSetupMinutes);
  }
  return index;
}

/// Earliest release date among [pending], or null when it is empty.
///
/// [selectNext] already folds releases into each job's effective start, so
/// the dispatch loops only use this to seed their clock at the first
/// release.
DateTime? earliestRelease<T>(
  List<T> pending,
  DateTime Function(T) releaseTime,
) {
  DateTime? earliest;
  for (final job in pending) {
    final release = releaseTime(job);
    if (earliest == null || release.isBefore(earliest)) {
      earliest = release;
    }
  }
  return earliest;
}

/// The instant a dispatch loop at clock [decisionTime] should simulate [job]
/// from: the clock itself, or the job's release if that is later.
///
/// Callers re-simulate the winner of [selectNext] from exactly this instant
/// when they commit it, so what is committed is what was judged.
DateTime evaluationTime<T>(
  T job,
  DateTime decisionTime,
  DateTime Function(T) releaseTime,
) {
  final DateTime release = releaseTime(job);
  return release.isAfter(decisionTime) ? release : decisionTime;
}

/// Picks the next job to schedule when the machine frees up at
/// [decisionTime], as a NON-DELAY schedule generator (Giffler & Thompson,
/// 1960; Baker, 1974, ch. 7) built on EFFECTIVE start times:
///
///   1. Every pending job is simulated by [evaluate] from
///      `max(decisionTime, release)` — see [evaluationTime]. The simulation
///      runs through the PreemptionEngine, so the candidate's `start` is
///      when the machine could REALLY begin it: after the release, after
///      any shift end or maintenance window, and after waiting for a window
///      long enough for a non-interruptible task (with its setup).
///   2. `t* = min start` over all of them.
///   3. Only the jobs that can start exactly at `t*` compete, and the rule
///      ([criterion]) chooses among them, evaluated at `t*`.
///
/// This answers "what if the job the rule prefers cannot start at t?": it
/// does not get to hold the machine; the next candidate that CAN start at t
/// is taken instead. And if no candidate can start at t at all, the clock
/// effectively jumps to `t*`, the earliest effective start — which may be a
/// job's release, the end of a maintenance window, the next shift, or the
/// next window that fits an uninterruptible block, whichever comes first.
/// The release gate is implied: a job released after `t*` can never start
/// at `t*`.
///
/// [evaluate] must simulate WITHOUT committing anything — the
/// PreemptionEngine is a pure function of its arguments, so simulating is
/// just calling it and not writing the result back.
///
/// [atcs] is required when [criterion] is [DispatchCriterion.atcs] and
/// ignored otherwise.
///
/// Returns null only when [pending] is empty or no job is schedulable.
/// The returned candidate's `span` is re-measured from `t*`, so every
/// competitor was compared from the same instant.
///
/// A candidate whose simulation throws [SchedulingHorizonException] is
/// dropped rather than allowed to abort the whole schedule: one job with an
/// impossible calendar should not sink the other twenty. If EVERY candidate
/// fails that way the exception is rethrown, because then the configuration
/// really is unschedulable and silence would be worse.
DispatchCandidate<T>? selectNext<T>({
  required List<T> pending,
  required DateTime decisionTime,
  required DateTime Function(T) releaseTime,
  required DispatchCandidate<T>? Function(T job, DateTime at) evaluate,
  required DispatchCriterion criterion,
  AtcsParameters? atcs,
}) {
  if (criterion == DispatchCriterion.atcs && atcs == null) {
    throw ArgumentError.notNull('atcs');
  }
  if (pending.isEmpty) return null;

  final evaluated = <DispatchCandidate<T>>[];
  SchedulingHorizonException? firstFailure;

  for (final job in pending) {
    final DispatchCandidate<T>? candidate;
    try {
      candidate =
          evaluate(job, evaluationTime(job, decisionTime, releaseTime));
    } on SchedulingHorizonException catch (e) {
      firstFailure ??= e;
      continue;
    }
    if (candidate != null) evaluated.add(candidate);
  }

  if (evaluated.isEmpty) {
    // Every job failed for the same structural reason — the calendar, not
    // this particular job. Surface it instead of returning null, which the
    // caller would read as "nothing left" and silently drop the jobs.
    if (firstFailure != null) throw firstFailure;
    return null;
  }

  // t*: the earliest instant any job can really start.
  DateTime earliestStart = evaluated.first.start;
  for (final c in evaluated) {
    if (c.start.isBefore(earliestStart)) earliestStart = c.start;
  }

  DispatchCandidate<T>? best;
  for (final c in evaluated) {
    if (!c.start.isAtSameMomentAs(earliestStart)) continue;
    final DispatchCandidate<T> atStar = _measuredFrom(c, earliestStart);
    if (best == null ||
        compareCandidates(criterion, atStar, best,
                decisionTime: earliestStart, atcs: atcs) <
            0) {
      best = atStar;
    }
  }
  return best;
}

/// [c] with its span re-measured from [at] (never negative).
DispatchCandidate<T> _measuredFrom<T>(DispatchCandidate<T> c, DateTime at) {
  final Duration span = c.end.difference(at);
  return DispatchCandidate(
    job: c.job,
    start: c.start,
    end: c.end,
    span: span.isNegative ? Duration.zero : span,
    dueDate: c.dueDate,
    releaseDate: c.releaseDate,
    priority: c.priority,
    jobId: c.jobId,
    setup: c.setup,
    remainingWork: c.remainingWork,
  );
}

/// Orders two candidates under [criterion]: negative when [a] goes first.
///
/// [decisionTime] is the t the clock-dependent indices are evaluated at;
/// [atcs] must be given for [DispatchCriterion.atcs].
///
/// Every criterion ends in the same two tie-breaks — shortest span, then
/// lowest jobId — so the result is fully deterministic. That matters more
/// than it looks: `List.sort` in Dart is not stable, so without an explicit
/// final tie-break two runs over identical input could disagree.
int compareCandidates<T>(
  DispatchCriterion criterion,
  DispatchCandidate<T> a,
  DispatchCandidate<T> b, {
  required DateTime decisionTime,
  AtcsParameters? atcs,
}) {
  int cmp;
  switch (criterion) {
    case DispatchCriterion.spt:
      cmp = a.span.compareTo(b.span);
      break;
    case DispatchCriterion.lpt:
      cmp = b.span.compareTo(a.span);
      break;
    case DispatchCriterion.edd:
      cmp = a.dueDate.compareTo(b.dueDate);
      break;
    case DispatchCriterion.fifo:
      cmp = a.releaseDate.compareTo(b.releaseDate);
      break;
    case DispatchCriterion.wspt:
      // Highest weighted priority per minute of effective span. The span is
      // floored at one minute so a zero-length job cannot divide by zero.
      final double wa = a.priority / _spanMinutes(a.span);
      final double wb = b.priority / _spanMinutes(b.span);
      cmp = wb.compareTo(wa);
      break;
    case DispatchCriterion.ms:
      cmp = slackMinutes(a).compareTo(slackMinutes(b));
      break;
    case DispatchCriterion.cr:
      cmp = criticalRatio(a, decisionTime)
          .compareTo(criticalRatio(b, decisionTime));
      break;
    case DispatchCriterion.atcs:
      if (atcs == null) throw ArgumentError.notNull('atcs');
      cmp = atcsLogIndex(b, atcs).compareTo(atcsLogIndex(a, atcs));
      break;
  }
  if (cmp != 0) return cmp;

  cmp = a.span.compareTo(b.span);
  if (cmp != 0) return cmp;

  return a.jobId.compareTo(b.jobId);
}

double _spanMinutes(Duration span) {
  final int minutes = span.inMinutes;
  return minutes > 0 ? minutes.toDouble() : 1.0;
}
