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
  final Duration
  makespan; // Difference between real end time and real start time
  final Duration totalFlowTime; // Sum of each job's makespan

  Metrics({
    required this.idle,
    required this.totalJobs,
    required this.maxDelay,
    required this.avarageProcessingTime,
    required this.avarageDelayTime,
    required this.avarageLatenessTime,
    required this.delayedJobs,
    required this.makespan,
    required this.totalFlowTime,
  }) : percentageDelayedJobs = (delayedJobs / totalJobs) * 100;
}
