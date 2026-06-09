
class Metrics {
  final Duration idle;
  final int totalJobs;
  final Duration maxDelay;
  final Duration avarageProcessingTime;
  final Duration avarageDelayTime; // average tardiness, always non-negative
  final Duration avarageLatenessTime; // average lateness, can be negative
  final int delayedJobs;
  final double percentageDelayedJobs;
  final Duration makespan;
  final Duration totalFlow;
  final Duration totalTardiness;
  final Duration maxTardiness;
  final Duration totalWeightedTardiness;
  final Duration maxLateness;

  Duration get totalWeightedDelay => totalWeightedTardiness;

  Metrics(
      {required this.idle,
      required this.totalJobs,
      required this.maxDelay,
      required this.avarageProcessingTime,
      required this.avarageDelayTime,
      required this.avarageLatenessTime,
      required this.delayedJobs,
      required this.makespan,
      required this.totalFlow,
      required this.totalTardiness,
      required this.maxTardiness,
      required this.totalWeightedTardiness,
      required this.maxLateness})
      : percentageDelayedJobs =
            totalJobs == 0 ? 0.0 : (delayedJobs / totalJobs) * 100;
}