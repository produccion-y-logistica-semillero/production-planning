import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/orders_bloc/orders_state.dart';
import 'package:production_planning/services/orders_service.dart';

class OrderBloc extends Cubit<OrdersState> {
  final OrdersService service;
  OrderBloc(this.service) : super(OrdersInitialState());

  Future<void> fetchOrders() async {
    emit(OrdersLoadingState());

    final Either<Failure, List<OrderEntity>> result = await service.getOrders();

    result.fold(
      (failure) {
        emit(OrdersErrorState("Error al cargar órdenes"));
      },
      (orders) {
        for (int i = 0; i < orders.length; i++) {}
        emit(OrdersLoadedState(orders));
      },
    );
  }

  Future<void> deleteOrderById(int orderId) async {
    final response = await service.deleteOrder(orderId);
    response.fold(
      (failure) {
        emit(OrdersErrorState("Error al cargar órdenes"));
      },
      (res) {
        final List<OrderEntity> orders = switch (state) {
          OrdersLoadedState(:final orders) => orders,
          _ => [],
        };
        final updatedOrders =
            orders.where((o) => o.orderId != orderId).toList();

        emit(OrdersLoadedState(updatedOrders));
      },
    );
  }
}
