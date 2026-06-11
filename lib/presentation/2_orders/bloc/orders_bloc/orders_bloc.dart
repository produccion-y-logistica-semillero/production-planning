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
        print("DEBUG: Error al cargar órdenes: ${failure.toString()}");
        emit(OrdersErrorState("Error al cargar órdenes"));
      },
      (orders) {
        print(
            "DEBUG: Órdenes cargadas exitosamente: ${orders.length} órdenes");
        for (int i = 0; i < orders.length; i++) {
          print(
              "DEBUG: Orden $i - ID: ${orders[i].orderId}, Fecha: ${orders[i].regDate}");
        }
        // Sort by regDate descending; break ties by orderId descending so
        // duplicates stay grouped together (file 1).
        orders.sort((a, b) {
          final dateCompare = b.regDate.compareTo(a.regDate);
          if (dateCompare != 0) return dateCompare;
          return (b.orderId ?? 0).compareTo(a.orderId ?? 0);
        });
        emit(OrdersLoadedState(orders));
        print("DEBUG: Estado cambiado a OrdersLoadedState");
      },
    );
  }

  Future<void> deleteOrderById(int orderId) async {
    print("DEBUG: deleteOrderById($orderId) iniciado");
    final response = await service.deleteOrder(orderId);
    response.fold(
      (failure) {
        print("DEBUG: Error al eliminar orden: ${failure.toString()}");
        emit(OrdersErrorState("Error al cargar órdenes"));
      },
      (res) {
        print("DEBUG: Orden eliminada exitosamente");

        final List<OrderEntity> orders = switch (state) {
          OrdersLoadedState(:final orders) => orders,
          _ => [],
        };
        final updatedOrders =
            orders.where((o) => o.orderId != orderId).toList();
        print("DEBUG: Lista actualizada: ${updatedOrders.length} órdenes");

        emit(OrdersLoadedState(updatedOrders));
      },
    );
  }

  /// Duplicates the order identified by [orderId] and reloads the full list
  /// on success. Only present in file 1.
  Future<void> duplicateOrder(int orderId) async {
    print("DEBUG: duplicateOrder($orderId) iniciado");
    emit(OrdersLoadingState());

    final response = await service.duplicateOrder(orderId);
    response.fold(
      (failure) {
        print("DEBUG: Error al duplicar orden: ${failure.toString()}");
        emit(OrdersErrorState("Error al duplicar orden"));
      },
      (res) {
        print("DEBUG: Orden duplicada exitosamente");
        fetchOrders();
      },
    );
  }
}