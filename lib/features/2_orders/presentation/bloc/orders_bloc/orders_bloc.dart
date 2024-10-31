import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartz/dartz.dart';
import 'orders_event.dart';
import 'orders_state.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/get_orders_use_case.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';

class OrderBloc extends Bloc<OrdersEvent, OrdersState> {
  final GetOrdersUseCase getOrdersUseCase;

  OrderBloc(this.getOrdersUseCase) : super(OrdersInitialState()) {
    on<FetchOrdersEvent>((event, emit) async {
      emit(OrdersLoadingState());

      final Either <Failure, List<OrderEntity>> result = await getOrdersUseCase(p: null);

      result.fold(
        (failure) => emit(OrdersErrorState("Error al cargar órdenes")),
        (orders) => emit(OrdersLoadedState(orders)),
      );
    });
  }
}