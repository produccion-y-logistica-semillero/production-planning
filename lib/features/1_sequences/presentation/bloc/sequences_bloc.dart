import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_type_use_case.dart';

import 'package:production_planning/features/1_sequences/presentation/bloc/sequences_event.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/sequences_state.dart';

class SequencesBloc extends Bloc<SequencesEvent, SequencesState>{

  final GetMachineTypesUseCase _getMachineTypesUseCase;

  SequencesBloc(
    this._getMachineTypesUseCase
  ): super(SequencesInitialState()){

    on<OnSequencesMachineRetrieve>(
      (event, emit) async {
        emit(SequencesRetrievingMachines());
        final response = await _getMachineTypesUseCase();

        response.fold(
          (f) => emit(SequencesMachineFailure()),
          (machines) => emit(SequencesMachinesSuccess(machines)) 
          );
      },
    );

    //TO IMPLEMENT
    on<OnSelectMachine>(
      (event, emit){

      }
    );

    //to change to emita new instance and trigger re rendering
    on<OnUseModeEvent>(
      (event, emit){
        print(state.isNewOrder);
        state.isNewOrder = event.isNewOrder;
        print(state.isNewOrder);
        emit(state);
      }
    );

  }
  
}