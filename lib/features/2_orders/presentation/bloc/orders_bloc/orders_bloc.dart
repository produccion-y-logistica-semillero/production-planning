import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_state.dart';

class OrdersBloc extends Bloc<OrdersEvent, OrdersState>{

  OrdersBloc() : super(OrdersInitialState());
}