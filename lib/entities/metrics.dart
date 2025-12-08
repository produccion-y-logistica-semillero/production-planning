class Metrics {
  final Duration idle;
  final int totalJobs;
  final Duration maxDelay;
  final Duration avarageProcessingTime;
  final Duration
      avarageDelayTime; //delay has to be positive, if it ended before then its 0
  final Duration avarageLatenessTime; //latness can be negative
  final int delayedJobs;
  final double percentageDelayedJobs;
  // New metrics
  final Duration makespan;
  final Duration totalFlow;
  final Duration totalWeightedDelay;

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
      required this.totalWeightedDelay})
      : percentageDelayedJobs =
            totalJobs == 0 ? 0.0 : (delayedJobs / totalJobs) * 100;
}
