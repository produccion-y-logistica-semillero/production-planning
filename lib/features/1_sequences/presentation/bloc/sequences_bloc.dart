import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_type_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/request_models/new_task_model.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/add_sequence_use_case.dart';

import 'package:production_planning/features/1_sequences/presentation/bloc/sequences_event.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/sequences_state.dart';

class SequencesBloc extends Bloc<SequencesEvent, SequencesState>{

  final GetMachineTypesUseCase _getMachineTypesUseCase;
  final AddSequenceUseCase _addSequenceUseCase;

  SequencesBloc(
    this._getMachineTypesUseCase,
    this._addSequenceUseCase
  ): super(SequencesInitialState(false, null, false, false, null)){

    on<OnSequencesMachineRetrieve>(
      (event, emit) async {
        emit(SequencesRetrievingMachines(state.isNewOrder, null, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines));
        final response = await _getMachineTypesUseCase();

        response.fold(
          (f) => emit(SequencesMachineFailure(state.isNewOrder, null, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines)),
          (machines) => emit(SequencesMachinesSuccess(state.isNewOrder,machines, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines)) 
          );
      },
    );

    //TO IMPLEMENT
    on<OnSelectMachine>(
      (event, emit){
        //emit the state with the new machine selected
        List<MachineTypeEntity> selectedMachines = [];
        if(state.selectedMachines != null) selectedMachines = state.selectedMachines!;
        emit(SequencesMachineAdded(state.isNewOrder,state.machines, state.isSuccessModalVisible , state.isNoMachinesModalVisible,selectedMachines..add(event.machine)));
      }
    );

    //to change to emita new instance and trigger re rendering
    on<OnUseModeEvent>(
      (event, emit){
        emit(SequencesModeChanged(event.isNewOrder, state.machines, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines));
      }
    );

    on<OnSequencesSaveProcess>(
      (event, emit) async{

        List<dynamic> parameters = [event.processName];
        List<NewTaskModel> machines = [];

        for(int i = 0; i < state.machines!.length; i++){
          MachineTypeEntity m = state.machines![i];
          machines.add(NewTaskModel(m.id!, TimeOfDay(hour: 1, minute: 10), "empty by now", i+1));
        }
        parameters.add(machines);
        final response = await _addSequenceUseCase(p: parameters);
        response.fold((f){
          add(OnMachinesModalChanged(true));
        },
        (success){
          emit(SequencesProcessAdded(true, state.machines, true, false, null));
        }
        );
      }
    );

    on<OnMachinesModalChanged>(
      (event, emit){
        emit(SequencesMinimumStateChange(state.isNewOrder, state.machines, state.isSuccessModalVisible, event.isVisible, state.selectedMachines));
      }
    );

    on<OnMachinesSuccessModalChanged>(
      (event, emit){
        emit(SequencesMinimumStateChange(state.isNewOrder, state.machines, event.isVisible, state.isNoMachinesModalVisible, state.selectedMachines));
      }
    );

  }
  
}