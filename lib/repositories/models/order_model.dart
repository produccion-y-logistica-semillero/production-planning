import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/order_entity.dart';

class OrderModel {
  final int? orderId;
  DateTime regDate;
  Map<String, Map<String, Map<String, int>>>? setupTimeMatrix;

  OrderModel(this.orderId, this.regDate, {this.setupTimeMatrix});

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      json['order_id'],
      DateTime.parse(json['reg_date']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'reg_date': regDate.toIso8601String(),
    };
  }

  OrderEntity toEntity(List<JobEntity> jobs) {
    return OrderEntity(
      orderId,
      regDate,
      jobs,
      setupTimeMatrix: setupTimeMatrix,
    );
  }
}
