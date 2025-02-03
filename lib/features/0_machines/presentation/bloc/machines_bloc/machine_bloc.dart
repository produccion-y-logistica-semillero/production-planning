import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/add_machine_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/delete_machine_id_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_use_case.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machines_bloc/machines_state.dart';

class MachineBloc extends Cubit<MachinesState> {
  final GetMachinesUseCase _getMachinesUseCase;
  final DeleteMachineUseCase _deleteMachineUseCase;
  final AddMachineUseCase _addMachineUseCase;

  MachineBloc(this._getMachinesUseCase, this._deleteMachineUseCase, this._addMachineUseCase)
  :super(MachinesStateInitial(null, null));


  void retrieveMachines(int typeId) async{
    //emit so it shows loading
    emit(MachinesRetrieving(null, state.typeId));
    final response = await _getMachinesUseCase(p: typeId);
    response.fold( 
      (f)=> emit(MachinesRetrievingError(null, state.typeId)),
      (machines)=> emit(MachinesRetrievingSuccess(machines, state.typeId))
    );
  }

  void addNewMachine(String capacity, String preparation, String continueCapacity, String rest, String machineName, int typeId)async{
    List<MachineEntity> machines = [];
    if(state is MachinesRetrievingSuccess) machines = state.machines??[];
    final cap = Duration(
      hours: int.parse(capacity.substring(0,2)),
      minutes: int.parse(capacity.substring(3,5)),
    );
    final prep = Duration(
      hours: int.parse(preparation.substring(0,2)),
      minutes: int.parse(preparation.substring(3,5)),
    );
    final rst = Duration(
      hours: int.parse(rest.substring(0,2)),
      minutes: int.parse(rest.substring(3,5)),
    );
    final continueCap = int.parse(continueCapacity);
    //here we should call domain and get as response the machine entity to ad
    final response = await _addMachineUseCase(p: {
      "status": null,
      "machine_name" : machineName,
      "machine_type_id" : typeId,
      "processing_time": cap,
      "preparation_time" : prep,
      "rest_time" : rst,
      "continue_capacity" : continueCap
    });
    response.fold(
      (f)=> MachinesRetrievingSuccess(machines, state.typeId), 
      (mac){
        //NEED TO CHECK BECAUSE WHEN ADDING THE NEW MACHINE IT SAYS ID IS NULL EVEN TOUGH IS NOT
        emit(MachinesRetrievingSuccess(machines, state.typeId));
      });
  }


  void deleteMachine(int machineID) async{
    List<MachineEntity> machines = state.machines??[];

    final response = await _deleteMachineUseCase(p:machineID);
    response.fold(
      (failure) => emit(MachineDeletionError(machines, state.typeId)),
      (boolean){
        if(boolean){
          machines.removeWhere((machine) => machine.id == machineID);
          emit(MachineDeletionSuccess(machines, state.typeId));
        }
      }
    );
  } 

  void machinesExpansionCollapses() async{
    emit(MachinesStateInitial(null, state.typeId));
  }

  void machineSetType(int typeId) async{
     emit(MachineTypeIdSet(state.machines, typeId));
  }
}
