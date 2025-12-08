import 'package:production_planning/entities/order_entity.dart';

abstract class OrdersState {}

class OrdersInitialState extends OrdersState {}

class OrdersLoadingState extends OrdersState {}

class OrdersLoadedState extends OrdersState {
  final List<OrderEntity> orders;

  OrdersLoadedState(this.orders);
}

class OrdersErrorState extends OrdersState {
  final String message;

  OrdersErrorState(this.message);
}
