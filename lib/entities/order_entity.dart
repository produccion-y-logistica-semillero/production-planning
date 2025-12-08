import 'package:production_planning/entities/job_entity.dart';

class OrderEntity {
  final int? orderId;
  final DateTime regDate;
  List<JobEntity>? orderJobs;

  OrderEntity(this.orderId, this.regDate, this.orderJobs);
}
