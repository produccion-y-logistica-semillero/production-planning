import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';

class JobModel {
  final int jobId;
  final int sequenceId;
  final int amount;
  final DateTime dueDate;
  final int priority;

  JobModel(
      this.jobId, this.sequenceId, this.amount, this.dueDate, this.priority);

  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      json['job_id'],
      json['sequence_id'],
      json['amount'],
      DateTime.parse(json['due_date']),
      json['priority'],
    );
  }

  JobEntity toEntity() {
    SequenceEntity sequence = SequenceEntity(sequenceId, [], 'Sequence Name');

    return JobEntity(
      jobId,
      sequence,
      amount,
      dueDate,
      priority,
    );
  }
}
