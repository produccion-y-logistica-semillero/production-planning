
class NewOrderRequestModel{
  final int sequenceId;
  final DateTime dueDate;
  final DateTime availableDate;
  final int priority;
  final String? jobName;

  final Map<int, int>? preemptionMatrix;
  // Map<taskId, Map<machineId, Map<'processing'|'preparation'|'rest', minutes>>>
  final Map<int, Map<int, Map<String, int>>>? taskMachineTimesMinutes;
  final Map<int, String>? machineFinalStates;

  NewOrderRequestModel(this.sequenceId, this.dueDate, this.availableDate,
      this.priority, this.jobName,
           {this.preemptionMatrix, this.taskMachineTimesMinutes, this.machineFinalStates});
}
