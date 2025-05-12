
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/presentation/2_orders/request_models/new_order_request_model.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/services/sequences_service.dart';

class NewOrderBloc extends Cubit<NewOrderState> {

  final OrdersService orderService;
  final SequencesService seqService;

  NewOrderBloc(this.orderService, this.seqService)
      : super(NewOrdersInitialState());

  Future<void> retrieveSequences() async {
    final response = await seqService.getSequences();
    response.fold(
      (failure) => emit(NewOrdersFailureState()),
      (sequences) {
        emit(NewOrdersState(
          [],
          sequences.map((s) => Tuple2<int, String>(s.id!, s.name)).toList(),
        ));
      },
    );
  }

  void addJob() {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);
      List<Tuple2<int, String>> sequences = currentState.sequences;

      int index = jobs.isNotEmpty ? jobs.map((job) => job.index).reduce((a, b) => a > b ? a : b) : 0;
      
      jobs.add(AddJobWidget(
        availableDate: null,
        dueDate: null,
        availableHour: null,
        dueHour: null,
        priorityController: TextEditingController(),
        quantityController: TextEditingController(),
        idController: TextEditingController(),
        index: index + 1,
        sequences: sequences,
      ));

      emit(NewOrdersState(jobs, sequences));
    }
  }

  void removeJob(int index) {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);
      List<Tuple2<int, String>> sequences = currentState.sequences;

      jobs.removeWhere((widget) => widget.index == index);
      emit(NewOrdersState(jobs, sequences));
    }
  }

  Future<void> saveOrder() async {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      final List<NewOrderRequestModel> jobs = currentState.jobs.map((wid) {
        return NewOrderRequestModel(
          wid.selectedSequence!,
          wid.dueDate!,
          wid.availableDate!,
          int.parse(wid.priorityController!.text),
          int.parse(wid.quantityController!.text),
        );
      }).toList();

      final response = await orderService.addOrder(jobs);
      response.fold(
        (failure) {
          final newState = NewOrdersState(currentState.jobs, currentState.sequences);
          newState.justSaved = false;
          emit(newState);
        },
        (success) {
          final newState = NewOrdersState([], currentState.sequences);
          newState.justSaved = true;
          emit(newState);
        },
      );
    }
  }

  void newOrder() {
    emit(NewOrdersInitialState());
  }

  void newJob() {
    emit(NewOrdersInitialState());
  }
}
