import 'package:production_planning/entities/job_interruption_policy.dart';

class NewOrderRequestModel{
  final int sequenceId;
  final DateTime dueDate;
  final DateTime availableDate;
  final int priority;
  final int amount;
  final String? jobName;

  final Map<int, int>? preemptionMatrix;
  final JobInterruptionPolicy? interruptionPolicy;
  // Map<taskId, Map<machineId, Map<'processing'|'preparation'|'rest', minutes>>>
  final Map<int, Map<int, Map<String, int>>>? taskMachineTimesMinutes;
  final Map<int, String>? machineFinalStates;

  NewOrderRequestModel(this.sequenceId, this.dueDate, this.availableDate,
      this.priority, this.amount, this.jobName,
      {this.preemptionMatrix,
      this.interruptionPolicy,
      this.taskMachineTimesMinutes,
      this.machineFinalStates});
}
