import 'package:production_planning/entities/job_entity.dart';

class OrderEntity{
  final int? orderId;
  final DateTime regDate; 
  List<JobEntity>? orderJobs;
  final Map<String, Map<String, Map<String, int>>>? setupTimeMatrix;

  OrderEntity(this.orderId, this.regDate, this.orderJobs, {this.setupTimeMatrix});
}

