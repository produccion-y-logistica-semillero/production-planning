
class NewOrderRequestModel{
  final int sequenceId;
  final DateTime dueDate;
  final DateTime availableDate;
  final int priority;
  final int amount;
  final String? jobName;

  final Map<int, int>? preemptionMatrix;
  // Map<taskId, Map<machineId, Map<'processing'|'preparation'|'rest', minutes>>>
  final Map<int, Map<int, Map<String, int>>>? taskMachineTimesMinutes;

  NewOrderRequestModel(this.sequenceId, this.dueDate, this.availableDate,
      this.priority, this.amount, this.jobName,
      {this.preemptionMatrix, this.taskMachineTimesMinutes});
}
