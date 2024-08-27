import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/machines/domain/use_cases/get_machines_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machines_event.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machines_state.dart';

class MachineBloc extends Bloc<MachinesEvent, MachinesState>{

  final GetMachinesUseCase _getMachinesUseCase;

  MachineBloc(this._getMachinesUseCase)
  :super(MachinesStateInitial()){
    //event for when we at first seek the machines
    on<OnMachinesRetrieving>(
      (event, emit)async {
        //emit so it shows loading
        emit(MachinesRetrieving());

        List<MachineEntity> machines = [
          MachineEntity(status: "hello", processingTime: Duration(), preparationTime: Duration(), id:10),
          MachineEntity(status: "hello", processingTime: Duration(), preparationTime: Duration(), id:12),
          MachineEntity(status: "hello", processingTime: Duration(), preparationTime: Duration(), id:13),
        ];
        emit(MachinesRetrievingSuccess(machines));
        /*final response  = await _getMachinesUseCase(p:event.typeId);

        response.fold(
          (failure)=>emit(MachinesRetrievingError()), 
          (machines)=>emit(MachinesRetrievingSuccess(machines))
        );*/

      }
    );

    on<OnMachinesExpansionCollpased>(
      (event, emit){
        emit(MachinesStateInitial());
      }
    );
  }

}