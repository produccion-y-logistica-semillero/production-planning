import 'package:production_planning/entities/order_entity.dart';

abstract class OrdersState {}

class OrdersInitialState extends OrdersState {}

class OrdersLoadingState extends OrdersState {}

class OrdersLoadedState extends OrdersState {
  final List<OrderEntity> orders;

  /// Environment of each order (orderId → name, e.g. "FLOW SHOP"), for the
  /// list's filter. An order missing here could not be classified.
  final Map<int, String> environments;

  OrdersLoadedState(this.orders, {this.environments = const {}});
}

class OrdersErrorState extends OrdersState {
  final String message;

  OrdersErrorState(this.message);
}
