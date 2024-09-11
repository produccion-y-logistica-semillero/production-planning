import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';

class OrderEntity{
  final int? orderId;
  final DateTime regDate; 
  List<JobEntity>? orderJobs;

  OrderEntity(this.orderId, this.regDate, this.orderJobs);
}