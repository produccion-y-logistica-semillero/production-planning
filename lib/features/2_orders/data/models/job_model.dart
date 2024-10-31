
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';

class JobModel {
  final int jobId;
  final int sequenceId;
  final int amount;
  final DateTime dueDate;
  final DateTime availableDate;
  final int priority;

  JobModel(
      this.jobId, this.sequenceId, this.amount, this.dueDate, this.priority, this.availableDate);


  factory JobModel.fromJson(Map<String, dynamic> json) {
    return JobModel(
      json['job_id'],
      json['sequence_id'],
      json['amount'],
      DateTime.parse(json['due_date']),
      json['priority'],
      DateTime.parse(json['available_date'])

    );
  }

  JobEntity toEntity() {
    return JobEntity(
      jobId,
      null,
      amount,
      dueDate,
      priority,
      availableDate
    );
  }
}
