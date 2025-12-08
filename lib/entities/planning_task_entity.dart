class PlanningTaskEntity {
  final int sequenceId;
  final String sequenceName;
  final String displayName;
  final int taskId;
  final int
      numberProcess; //this is for instance, if in the order we put 2 items of sequence x, then there would be x1 and x2
  final DateTime startDate;
  final bool retarded; //if the termination is after due date
  final DateTime endDate;
  final int jobId;
  final int orderId;

  PlanningTaskEntity({
    required this.sequenceId,
    required this.sequenceName,
    required this.displayName,
    required this.taskId,
    required this.numberProcess,
    required this.startDate,
    required this.endDate,
    required this.retarded,
    required this.orderId,
    required this.jobId,
  });
}
