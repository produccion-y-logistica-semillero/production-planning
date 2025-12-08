//Job entity is the entity for what would be sequence_x_order in the database,
//here in application layer we will call it job

import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/machine_times.dart';

class JobEntity {
  int? jobId;
  final SequenceEntity? sequence;
  final int amount;
  final DateTime availableDate;
  final DateTime dueDate;
  final int priority;
  final Map<int, int>? preemptionMatrix; // Map<machineId, canPreempt (0 o 1)>
  // Map<taskId, Map<machineId, MachineTimes>>: optional explicit processing/setup/rest times
  final Map<int, Map<int, MachineTimes>>? taskMachineTimes;

  JobEntity(this.jobId, this.sequence, this.amount, this.dueDate, this.priority,
      this.availableDate,
      {this.preemptionMatrix, this.taskMachineTimes});
}
