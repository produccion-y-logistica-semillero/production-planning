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
          MachineEntity(status: "Disponible", processingTime: Duration(), preparationTime: Duration(), restTime: Duration(), continueCapacity: 5, id:10),
          MachineEntity(status: "Disponible", processingTime: Duration(), preparationTime: Duration(), restTime: Duration(), continueCapacity: 5, id:12),
          MachineEntity(status: "Disponible", processingTime: Duration(), preparationTime: Duration(), restTime: Duration(), continueCapacity: 5, id:13),
        ];
        emit(MachinesRetrievingSuccess(machines));
        /*final response  = await _getMachinesUseCase(p:event.typeId);

        response.fold(
          (failure)=>emit(MachinesRetrievingError()), 
          (machines)=>emit(MachinesRetrievingSuccess(machines))
        );*/
      }
    );

    on<OnNewMachine>(
      (event, emit) async{
        List<MachineEntity> machines = [];
        if(state is MachinesRetrievingSuccess) machines = (state as MachinesRetrievingSuccess).machines;
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

        machines.add(MachineEntity(id: 100, status: "Disponible", processingTime: capacity, preparationTime: preparation, restTime: rest, continueCapacity: continueCap));

        emit(MachinesRetrievingSuccess(machines));
      }
    );

    on<OnMachinesExpansionCollpased>(
      (event, emit){
        emit(MachinesStateInitial());
      }
    );
  }

}