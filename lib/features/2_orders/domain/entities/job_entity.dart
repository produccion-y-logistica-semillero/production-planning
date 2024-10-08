//Job entity is the entity for what would be sequence_x_order in the database,
//here in application layer we will call it job

import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';

class JobEntity {
  int? jobId;
  int? orderId;
  final SequenceEntity sequence;
  final int amount;
  final DateTime dueDate;
  final int priority;

  JobEntity(
      this.jobId, this.sequence, this.amount, this.dueDate, this.priority);
}
