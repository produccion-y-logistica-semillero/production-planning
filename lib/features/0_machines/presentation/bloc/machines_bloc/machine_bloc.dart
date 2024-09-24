import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/add_machine_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/delete_machine_id_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_use_case.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machines_bloc/machines_event.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machines_bloc/machines_state.dart';

class MachineBloc extends Bloc<MachinesEvent, MachinesState> {
  final GetMachinesUseCase _getMachinesUseCase;
  final DeleteMachineUseCase _deleteMachineUseCase;
  final AddMachineUseCase _addMachineUseCase;

  MachineBloc(this._getMachinesUseCase, this._deleteMachineUseCase, this._addMachineUseCase)
  :super(MachinesStateInitial(null, null)){
    //event for when we at first seek the machines
    on<OnMachinesRetrieving>(
      (event, emit)async {
        //emit so it shows loading
        emit(MachinesRetrieving(null, state.typeId));

        final response = await _getMachinesUseCase(p: event.typeId);
        response.fold( 
          (f)=> emit(MachinesRetrievingError(null, state.typeId)),
          (machines)=> emit(MachinesRetrievingSuccess(machines, state.typeId))
        );
    });

    on<OnNewMachine>(
      (event, emit) async{
        List<MachineEntity> machines = [];
        if(state is MachinesRetrievingSuccess) machines = state.machines??[];
        final capacity = Duration(
          hours: int.parse(event.capacity.substring(0,2)),
          minutes: int.parse(event.capacity.substring(3,5)),
        );
        final preparation = Duration(
          hours: int.parse(event.preapartion.substring(0,2)),
          minutes: int.parse(event.preapartion.substring(3,5)),
        );
        final rest = Duration(
          hours: int.parse(event.rest.substring(0,2)),
          minutes: int.parse(event.capacity.substring(3,5)),
        );
        final continueCap = int.parse(event.continueCapacity);
        //here we should call domain and get as response the machine entity to add

        final response = await _addMachineUseCase(p: {
          "status": null,
          "machine_name" : event.machineName,
          "machine_type_id" : event.typeId,
          "processing_time": capacity,
          "preparation_time" : preparation,
          "rest_time" : rest,
          "continue_capacity" : continueCap
        });

      response.fold(
        (f)=> MachinesRetrievingSuccess(machines, state.typeId), 
        (mac){
          //NEED TO CHECK BECAUSE WHEN ADDING THE NEW MACHINE IT SAYS ID IS NULL EVEN TOUGH IS NOT
          emit(MachinesRetrievingSuccess(machines, state.typeId));
        });
    });

    on<OnDeleteMachine>(
      (event, emit) async{
        List<MachineEntity> machines = state.machines??[];

        final response = await _deleteMachineUseCase(p:event.machineID);

        response.fold(
          (failure) => emit(MachineDeletionError(machines, state.typeId)),
          (boolean){
            if(boolean){
              machines.removeWhere((machine) => machine.id == event.machineID);
              emit(MachineDeletionSuccess(machines, state.typeId));
            }
          }
        );
      }
    );

    on<OnMachinesExpansionCollpased>(
      (event, emit){
        emit(MachinesStateInitial(null, state.typeId));
      }
    );

    on<OnMachinesSetType>(
      (event, emit){
        emit(MachineTypeIdSet(state.machines, event.typeId));
      }
    );
  }
}
