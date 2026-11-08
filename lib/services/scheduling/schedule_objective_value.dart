// lib/services/scheduling/schedule_objective_value.dart
//
// One evaluation of the objective chosen for a metaheuristic, shared by the
// genetic algorithm of every environment, so "Tardanza total" means the same
// Σ Tj whether the schedule came from a single machine or a job shop.
// Notation of Pinedo (2016): rj release, dj due date, Cj completion.

import 'package:production_planning/entities/schedule_objective.dart';

/// What the objective needs to know about one scheduled job.
class JobCompletion {
  final DateTime release; // rj
  final DateTime due; // dj
  final DateTime completion; // Cj

  const JobCompletion(this.release, this.due, this.completion);
}

/// Value of [objective] over [jobs], in minutes (or jobs for
/// [ScheduleObjective.tardyJobs]); lower is better. Makespan is measured
/// from [start] to the last completion, as in the metrics table.
///
/// Ties in a count objective are frequent, so total flow time is added as a
/// tie-break scaled below one job: two schedules with the same number of
/// tardy jobs are told apart by how long jobs stay in the system.
double scheduleObjectiveValue(
  ScheduleObjective objective,
  Iterable<JobCompletion> jobs,
  DateTime start,
) {
  double minutes(Duration d) => d.inSeconds / 60.0;
  double flow = 0;
  double tardiness = 0;
  double earliness = 0;
  int tardy = 0;
  DateTime last = start;
  for (final j in jobs) {
    flow += minutes(j.completion.difference(j.release));
    final lateness = minutes(j.completion.difference(j.due));
    if (lateness > 0) {
      tardiness += lateness;
      tardy++;
    } else {
      earliness -= lateness;
    }
    if (j.completion.isAfter(last)) last = j.completion;
  }
  return switch (objective) {
    ScheduleObjective.totalFlow => flow,
    ScheduleObjective.makespan => minutes(last.difference(start)),
    ScheduleObjective.totalTardiness => tardiness,
    ScheduleObjective.tardyJobs => tardy + flow / 1e9,
    ScheduleObjective.totalEarliness => earliness,
  };
}

/// Latest end time per job id over [entries] (a job may appear once per
/// operation or stage).
Map<int, DateTime> completionByJob<T>(
  Iterable<T> entries,
  int Function(T) jobId,
  DateTime Function(T) end,
) {
  final out = <int, DateTime>{};
  for (final e in entries) {
    final id = jobId(e);
    final t = end(e);
    final prev = out[id];
    if (prev == null || t.isAfter(prev)) out[id] = t;
  }
  return out;
}
