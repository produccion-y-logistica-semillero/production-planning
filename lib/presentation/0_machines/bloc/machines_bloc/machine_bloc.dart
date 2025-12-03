import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machines_state.dart';
import 'package:production_planning/services/machines_service.dart';

class MachineBloc extends Cubit<MachinesState> {

  final MachinesService service;
  MachineBloc(this.service):super(MachinesStateInitial(null, null));

  void retrieveMachines(int typeId) async{
    //emit so it shows loading
    emit(MachinesRetrieving(null, state.typeId));
    final response = await service.getMachines(typeId);
    response.fold( 
      (f)=> emit(MachinesRetrievingError(null, state.typeId)),
      (machines)=> emit(MachinesRetrievingSuccess(machines, state.typeId))
    );
  }

  void addNewMachine(
    Duration processingTime,
    Duration preparationTime,
    int continueCapacity,
    Duration restTime,
    String machineName,
    int typeId,
    String availabilityDateTimeStr,
  ) async {
    List<MachineEntity> machines = [];
    print("Adding new machine with typeId: $typeId");
    if(state is MachinesRetrievingSuccess) machines = state.machines??[];
    final availabilityDateTime = DateTime.parse(availabilityDateTimeStr);
    //here we should call domain and get as response the machine entity to ad
    print("------------------------------------------------");
    print("Adding new machine with name: $machineName, typeId: $typeId, proc: $processingTime, prep: $preparationTime, rst: $restTime, continueCap: $continueCapacity, availabilityDateTime: $availabilityDateTime");
    final response = await service.addMachine(typeId, machineName, null, processingTime, preparationTime, restTime, continueCapacity, availabilityDateTime);
    print("Response from service: $response");
    response.fold(
      (f)=> MachinesRetrievingSuccess(machines, state.typeId), 
      (mac){
        //NEED TO CHECK BECAUSE WHEN ADDING THE NEW MACHINE IT SAYS ID IS NULL EVEN TOUGH IS NOT
        emit(MachinesRetrievingSuccess(machines, state.typeId));
      });
  }


  void deleteMachine(int machineID) async{
    List<MachineEntity> machines = state.machines??[];

    final response = await service.deleteMachine(machineID);
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
