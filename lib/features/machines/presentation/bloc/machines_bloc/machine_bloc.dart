import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/machines/domain/use_cases/add_machine_type_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/delete_machine_type_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/get_machines_type_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_state.dart';

class MachineBloc extends Bloc<MachineEvent, MachineState>{

  final AddMachineTypeUseCase _addMachineTUseCase;
  final GetMachineTypesUseCase _getMachineTUseCase;
  final DeleteMachineTypeUseCase _deleteMachineTUseCase;


  MachineBloc(this._addMachineTUseCase, this._getMachineTUseCase, this._deleteMachineTUseCase): super(MachineInitial([]))
  {
    //Handler for event onMachineTypesRetrieving
    on<OnMachineTypeRetrieving>(
      (event, emit) async{
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
    );

    //Handler for event on add new machine type
    on<OnAddNewMachineType>(
      (event, emit) async{
        //retrieving already loaded machines on screen
        List<MachineTypeEntity> machineTypes = state.machineTypes ==null? []: state.machineTypes!;
        //IMPORTANT, FOR NOW WE WILL PASS THE ENTITY VALUES IN A MAP
        //BUT WE LOOSE TYPE SAFETY WITH THIS, SO THIS NEEDS TO BE ANALYZED IN ORDER TO IMPROVE IT
        final response = await _addMachineTUseCase(p: {"name" :event.name, "description":event.description});

        //If success show, if not success show
        response.fold(
          (failure) => emit(MachineTypesAddingError(machineTypes)), 
          (newMach){
            machineTypes.add(newMach);
            print(machineTypes);
            emit(MachineTypesAddingSuccess(machineTypes));
          }
        );
      }
    );

    //Handler for on delete machine type event
    on<OnDeleteMachineType>(
      (event, emit) async{
        final response = await _deleteMachineTUseCase(p: event.id);
        response.fold(
          (failure) => emit(MachineTypeDeletionError(state.machineTypes)),
          (success){
            state.machineTypes?.removeAt(event.index);
            emit(MachineTypeDeletionSuccess(state.machineTypes));
          }
        );
      }
    );



    //CHANGE THIS, ONLY TO BE CALLED ONCE ENTERED TO THE PAGE
    //add(OnMachineTypeRetrieving());

  }

}