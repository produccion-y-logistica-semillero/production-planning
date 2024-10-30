import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';

sealed class NewOrderEvent{

}

class OnNewOrder implements NewOrderEvent{
  final int? orderId;
  final DateTime regDate;
  final List<JobEntity> orderJobs;

  OnNewOrder(this.orderId, this.regDate, this.orderJobs);
}

class OnNewJob implements NewOrderEvent{
  final int? jobId;
  final SequenceEntity? sequence;
  final int amount;
  final DateTime availableDate;
  final DateTime dueDate;
  final int priority;

  OnNewJob(this.jobId, this.sequence, this.amount, this.availableDate, this.dueDate, this.priority);
}