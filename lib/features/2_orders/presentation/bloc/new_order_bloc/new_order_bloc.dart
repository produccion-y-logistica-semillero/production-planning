
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/get_sequences_use_case.dart';
import 'package:production_planning/features/2_orders/domain/request_models/new_order_request_model.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/add_order_use_case.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_event.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/features/2_orders/presentation/widgets/high_order/add_job.dart';

class NewOrderBloc extends Bloc<NewOrderEvent, NewOrderState>{
  final AddOrderUseCase addOrderUseCase;
  final GetSequencesUseCase getSequencesUseCase;

  NewOrderBloc(this.addOrderUseCase, this.getSequencesUseCase)
  :super(NewOrdersInitialState()){
    on<OnRetrieveSequences>(
      (event, emit)async{
        final response = await getSequencesUseCase();

        response.fold(
          (f)=> emit(NewOrdersFailureState()), 
          (sequences){
            emit(NewOrdersState([], sequences.map((s)=>Tuple2<int, String>(s.id!, s.name)).toList()));
          }
        );
      }
    );

    on<OnAddJob>(
      (event, emit)async{
        List<AddJobWidget> jobs = [];
        List<Tuple2<int, String>> sequences = [];
        if(state is NewOrdersState){
          jobs = (state as NewOrdersState).jobs;
          sequences = (state as NewOrdersState).sequences;
        }
        int index = 0;
        for(final job in jobs){
          if(job.index > index) index = job.index;
        }
        jobs.add(AddJobWidget(
          availableDate: null, 
          dueDate:  null,
          priorityController: TextEditingController(), 
          quantityController: TextEditingController(), 
          index: index+1, 
          sequences: sequences)
        );
        emit(NewOrdersState(jobs, sequences));
      }
    );

    on<OnRemoveJob>(
      (event, emit)async{
        List<AddJobWidget> jobs = [];
        List<Tuple2<int, String>> sequences = [];
        if(state is NewOrdersState){
          jobs = (state as NewOrdersState).jobs;
          sequences = (state as NewOrdersState).sequences;
        }
        jobs.removeWhere((widget)=> widget.index == event.index);
        emit(NewOrdersState(jobs, sequences));
      }
    );

    on<OnSaveOrder>(
      (event, emit)async{
        if(state is NewOrdersState){
          final List<NewOrderRequestModel> jobs = (state as NewOrdersState).jobs
            .map((wid)=> 
              NewOrderRequestModel(
                wid.selectedSequence!, 
                wid.dueDate!,
                wid.availableDate!, 
                int.parse(wid.priorityController!.text), 
                int.parse(wid.quantityController!.text), 
              )
            ).toList();
          final response = await addOrderUseCase.call(p: jobs);
          response.fold(
            (f){
              final newState = NewOrdersState((state as NewOrdersState).jobs, (state as NewOrdersState).sequences);
              newState.justSaved = false;
              emit(newState);
            }, 
            (suc){
              final newState = NewOrdersState([], (state as NewOrdersState).sequences);
              newState.justSaved = true;
              emit(newState);
            });
        }
      }
    );

    on<OnNewOrder>(
      (event, emit)async{
        emit(NewOrdersInitialState());
      },
    );
    on<OnNewJob>(
      (event, emit){
        emit(NewOrdersInitialState());
      }
    );
  }
}