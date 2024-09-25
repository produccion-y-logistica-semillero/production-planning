class GanttTaskDTO{
  final int sequenceId;
  final String sequenceName;
  final int taskId;
  final int numberProcess;  //this is for instance, if in the order we put 2 items of sequence x, then there would be x1 and x2
  final DateTime startDate;
  final DateTime endDate;

  GanttTaskDTO({
    required this.sequenceId,
    required this.sequenceName,
    required this.taskId,
    required this.numberProcess,
    required this.startDate, 
    required this.endDate,
  });
}