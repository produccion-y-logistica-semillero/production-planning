import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';

abstract class OrdersEvent {}

class FetchOrdersEvent extends OrdersEvent {}

class FetchOrders extends OrdersEvent {
  int orderId;
  DateTime regDate; 
  List<JobEntity> orderJobs;

  FetchOrders(this.orderId, this.regDate, this.orderJobs);
}

class FetchOrdersId extends OrdersEvent {
  int orderId;
  FetchOrdersId(this.orderId);
}

class DeleteOrder extends OrdersEvent{
  int orderId;
  DeleteOrder(this.orderId);
}