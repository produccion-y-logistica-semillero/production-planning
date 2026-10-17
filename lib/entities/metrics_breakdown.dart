// Per-machine, per-station and per-job breakdown of a schedule, computed
// next to the totals in Metrics (lib/services/adapters/metrics_breakdown.dart).

/// How one machine spent the schedule's horizon (first start to last end).
class MachineUsage {
  final int machineId;
  final String machineName;
  final String stationName;

  /// Time processing jobs.
  final Duration processing;

  /// Time in changeovers (setups).
  final Duration setup;

  /// Pauses inside operations that are not off-shift or maintenance: the
  /// rest forced by the continuous-use cap.
  final Duration rest;

  /// Off-shift and maintenance time in the horizon, when the machine could
  /// not have worked anyway.
  final Duration unavailable;

  /// Available but without work: the real idle time.
  final Duration idle;

  /// Length of the horizon.
  final Duration horizon;

  const MachineUsage({
    required this.machineId,
    required this.machineName,
    required this.stationName,
    required this.processing,
    required this.setup,
    required this.rest,
    required this.unavailable,
    required this.idle,
    required this.horizon,
  });

  /// Time the machine could have worked.
  Duration get available => horizon - unavailable;

  /// Share of the available time spent processing or in setups (0–1).
  double get utilization => available <= Duration.zero
      ? 0
      : (processing + setup).inSeconds / available.inSeconds;
}

/// Machines of one station added up.
class StationUsage {
  final String stationName;
  final int machines;
  final Duration processing;
  final Duration setup;
  final Duration rest;
  final Duration unavailable;
  final Duration idle;
  final Duration horizon;

  const StationUsage({
    required this.stationName,
    required this.machines,
    required this.processing,
    required this.setup,
    required this.rest,
    required this.unavailable,
    required this.idle,
    required this.horizon,
  });

  Duration get available => horizon - unavailable;

  /// Idle time per machine of the station.
  Duration get idlePerMachine =>
      machines == 0 ? Duration.zero : idle ~/ machines;

  double get utilization => available <= Duration.zero
      ? 0
      : (processing + setup).inSeconds / available.inSeconds;
}

/// Whether one job met its due date.
class JobDelivery {
  final int jobId;
  final String jobName;

  /// Station of the job's last operation.
  final String lastStation;
  final DateTime dueDate;
  final DateTime completion;
  final int priority;

  const JobDelivery({
    required this.jobId,
    required this.jobName,
    required this.lastStation,
    required this.dueDate,
    required this.completion,
    required this.priority,
  });

  Duration get lateness => completion.difference(dueDate);
  Duration get tardiness =>
      lateness.isNegative ? Duration.zero : lateness;
  Duration get earliness =>
      lateness.isNegative ? -lateness : Duration.zero;
  bool get isLate => tardiness > Duration.zero;
}

/// Tardiness of the jobs that finished at one station.
class StationTardiness {
  final String stationName;
  final int jobs;
  final int lateJobs;
  final Duration totalTardiness;
  final Duration maxTardiness;

  const StationTardiness({
    required this.stationName,
    required this.jobs,
    required this.lateJobs,
    required this.totalTardiness,
    required this.maxTardiness,
  });
}
