import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/add_machine_type_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/delete_machine_type_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_type_use_case.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machine_types_bloc/machine_types_state.dart';

class MachineTypesBloc extends Cubit<MachineTypeState>{

  final AddMachineTypeUseCase _addMachineTUseCase;
  final GetMachineTypesUseCase _getMachineTUseCase;
  final DeleteMachineTypeUseCase _deleteMachineTUseCase;


  MachineTypesBloc(this._addMachineTUseCase, this._getMachineTUseCase, this._deleteMachineTUseCase): super(MachineTypeInitial([]));

  void retrieveMachineTypes() async{
    //emit initial event so we show loading
    emit(MachineTypesRetrieving(null));
    //getting machines
    final response = await _getMachineTUseCase();
    //if success emit machines, if not emit error
    response.fold(
      (failure)=> emit(MachineTypesRetrievingError(null)),
      (machines) => emit(MachineTypesRetrievingSuccess(machines))
    );
  }

  void addNewMachineType(String name, String description) async{
    //retrieving already loaded machines on screen
    List<MachineTypeEntity> machineTypes = state.machineTypes ==null? []: state.machineTypes!;
    //IMPORTANT, FOR NOW WE WILL PASS THE ENTITY VALUES IN A MAP
    //BUT WE LOOSE TYPE SAFETY WITH THIS, SO THIS NEEDS TO BE ANALYZED IN ORDER TO IMPROVE IT
    final response = await _addMachineTUseCase(p: {"name" :name, "description":description});
    //If success show, if not success show
    response.fold(
      (failure) => emit(MachineTypesAddingError(machineTypes)), 
      (newMach){
        machineTypes.add(newMach);
        emit(MachineTypesAddingSuccess(machineTypes));
      }
    );
  }

  void deleteMachineType(int id, int index) async{
    final response = await _deleteMachineTUseCase(p: id);
    response.fold(
      (failure) => emit(MachineTypeDeletionError(state.machineTypes)),
      (boolean){
        if(boolean) {
          state.machineTypes?.removeAt(index);
          emit(MachineTypeDeletionSuccess(state.machineTypes));
        }
      }
    );
  }
}