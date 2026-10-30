import 'package:production_planning/entities/metrics_breakdown.dart';
import 'package:production_planning/entities/tabu_run_stats.dart';

class Metrics {
  final Duration idle;
  final int totalJobs;
  final Duration maxDelay;
  final Duration avarageProcessingTime;
  final Duration avarageDelayTime; // average tardiness, always non-negative
  final Duration avarageLatenessTime; // average lateness, can be negative
  final Duration avarageEarlinessTime; // average earliness, always non-negative
  final int delayedJobs;
  final double percentageDelayedJobs;
  final Duration makespan;
  final Duration totalFlow;
  final Duration totalTardiness;
  final Duration maxTardiness;
  final Duration totalWeightedTardiness;
  final Duration maxLateness;
  final TabuRunStats? tabuStats;

  /// Breakdowns: how each machine and station spent the horizon, and
  /// whether each job (and the jobs ending at each station) met its due date.
  final List<MachineUsage> machineUsage;
  final List<StationUsage> stationUsage;
  final List<JobDelivery> jobDeliveries;
  final List<StationTardiness> stationTardiness;

  Duration get totalWeightedDelay => totalWeightedTardiness;

  Metrics(
      {required this.idle,
      required this.totalJobs,
      required this.maxDelay,
      required this.avarageProcessingTime,
      required this.avarageDelayTime,
      required this.avarageLatenessTime,
      required this.avarageEarlinessTime,
      required this.delayedJobs,
      required this.makespan,
      required this.totalFlow,
      required this.totalTardiness,
      required this.maxTardiness,
      required this.totalWeightedTardiness,
      required this.maxLateness,
      this.tabuStats,
      this.machineUsage = const [],
      this.stationUsage = const [],
      this.jobDeliveries = const [],
      this.stationTardiness = const []})
      : percentageDelayedJobs =
            totalJobs == 0 ? 0.0 : (delayedJobs / totalJobs) * 100;
}