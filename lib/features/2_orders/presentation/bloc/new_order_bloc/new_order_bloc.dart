import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_state.dart';

class NewOrderBloc extends Bloc<NewOrderEvent, NewOrderState>{

  NewOrderBloc(): super(NewOrderInitialState());
}