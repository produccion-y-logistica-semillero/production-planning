import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/delete_order_use_case.dart';
import 'orders_state.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/get_orders_use_case.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';

class OrderBloc extends Cubit<OrdersState> {
  final GetOrdersUseCase getOrdersUseCase;
  final DeleteOrderUseCase deleteOrder;

  OrderBloc(this.getOrdersUseCase, this.deleteOrder) : super(OrdersInitialState());

  Future<void> fetchOrders() async {
    emit(OrdersLoadingState());
    final Either<Failure, List<OrderEntity>> result = await getOrdersUseCase(p: null);
    result.fold(
      (failure) => emit(OrdersErrorState("Error al cargar órdenes")),
      (orders) => emit(OrdersLoadedState(orders)),
    );
  }

  Future<void> deleteOrderById(int orderId) async {
    final response = await deleteOrder.call(p: orderId);
    response.fold(
      (failure) => emit(OrdersErrorState("Error al cargar órdenes")),
      (res) {
        final List<OrderEntity> orders = switch (state) {
          OrdersLoadedState(:final orders) => orders,
          _ => [],
        };
        emit(OrdersLoadedState(orders.where((o) => o.orderId != orderId).toList()));
      },
    );
  }
}
