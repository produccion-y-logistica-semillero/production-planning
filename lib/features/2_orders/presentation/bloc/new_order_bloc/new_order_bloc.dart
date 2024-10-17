
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/add_sequence_use_case.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/add_order_use_case.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/add_job.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/add_order.dart';

class NewOrderBloc extends Bloc<NewOrdersEvent, NewOrdersState>{
  //final AddOrderUseCase _addOrderUseCase;
  //final AddSequenceUseCase   _addSequenceUseCase;

  NewOrderBloc(/*this._addOrderUseCase, this._addSequenceUseCase*/)
  :super(NewOrdersInitialState(null)){
    on<OnNewOrder>(
      (event, emit)async{
        emit(NewOrdersInitialState(null));
      },
    );
    on<OnNewJob>(
      (event, emit){
        emit(NewOrdersInitialState(null));
      }
    );
  }
}