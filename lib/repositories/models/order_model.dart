import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/order_entity.dart';

class OrderModel {
  final int? orderId;
  final DateTime regDate;

  OrderModel(this.orderId, this.regDate);

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      json['order_id'],
      DateTime.parse(json['reg_date']),
    );
  }

  OrderEntity toEntity(List<JobEntity> jobs) {
    return OrderEntity(
      orderId,
      regDate,
      jobs,
    );
  }
}
