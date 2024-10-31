import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';

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
