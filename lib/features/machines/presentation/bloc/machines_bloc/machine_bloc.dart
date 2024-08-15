import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/machines/domain/use_cases/add_machine_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_state.dart';

class MachineBloc extends Bloc<MachineEvent, MachineState>{

  final AddMachineUseCase _addMachineUseCase;


  MachineBloc(
    this._addMachineUseCase
  ): super(MachineInitial()){
    on<OnAddNewMachine>(
      (event, emit) async{
        List<MachineEntity> machines = [];
        if(state is MachineList){
          machines = (state as MachineList).machines;
        }
        final newMachine = MachineEntity(name: event.name, description: event.description);
        machines.add(newMachine);
        emit(MachineList(machines));
        
      }
    );
  }
}