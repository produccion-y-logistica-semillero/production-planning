import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/machines/domain/use_cases/add_machine_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/get_machines_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_state.dart';

class MachineBloc extends Bloc<MachineEvent, MachineState>{

  final AddMachineUseCase _addMachineUseCase;
  final GetMachinesUseCase _getMachinesUseCase;


  MachineBloc(this._addMachineUseCase, this._getMachinesUseCase): super(MachineInitial([]))
  {
    //Handler for event onMachineRetrieving
    on<OnMachineRetrieving>(
      (event, emit) async{
        //emit initial event so we show loading
        emit(MachineRetrieving(null));
        //getting machines
        final response = await _getMachinesUseCase();
        //if success emit machines, if not emit error
        response.fold(
          (failure)=> emit(MachineRetrievingError(null)),
          (machines) => emit(MachineRetrievingSuccess(machines))
        );
      }
    );

    //Handler for event on add new machine
    on<OnAddNewMachine>(
      (event, emit) async{
        //retrieving already loaded machines on screen
        List<MachineEntity> machines = state.machines ==null? []: state.machines!;
        //IMPORTANT, FOR NOW WE WILL PASS THE ENTITY VALUES IN A MAP
        //BUT WE LOOSE TYPE SAFETY WITH THIS, SO THIS NEEDS TO BE ANALYZED IN ORDER TO IMPROVE IT
        final response = await _addMachineUseCase(p: {"name" :event.name, "description":event.description});

        //If success show, if not success show
        response.fold(
          (failure) => emit(MachineAddingError(machines)), 
          (newMach){
            machines.add(newMach);
            print(machines);
            emit(MachineAddingSuccess(machines));
          }
        );
      }
    );



    //trigger initial event to get machines
    add(OnMachineRetrieving());

  }

}