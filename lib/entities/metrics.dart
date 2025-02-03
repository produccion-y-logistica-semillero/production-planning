class Metrics{
  final Duration idle;
  final int totalJobs;
  final Duration maxDelay;
  final Duration avarageProcessingTime;
  final Duration avarageDelayTime;  //delay has to be positive, if it ended before then its 0
  final Duration avarageLatenessTime;   //latness can be negative
  final int delayedJobs;
  final double percentageDelayedJobs;

  Metrics({
    required this.idle,
    required this.totalJobs,
    required this.maxDelay,
    required this.avarageProcessingTime,
    required this.avarageDelayTime,
    required this.avarageLatenessTime,
    required this.delayedJobs
  }): percentageDelayedJobs = (delayedJobs/totalJobs)*100;


}