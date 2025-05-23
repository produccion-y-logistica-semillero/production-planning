import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/presentation/1_sequences/request_models/new_task_model.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/services/machines_service.dart';
import 'package:production_planning/services/sequences_service.dart';

class SequencesBloc extends Cubit<SequencesState>{

  final SequencesService seqService;
  final MachinesService  machinesService;

  SequencesBloc(
    this.seqService, this.machinesService

  ): super(SequencesInitialState(false, null, false, false, null));

  void retrieveSequencesMachine() async{
    emit(SequencesRetrievingMachines(state.isNewOrder, null, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines));
    final response = await machinesService.getMachineTypes();
    response.fold(
      (f) => emit(SequencesMachineFailure(state.isNewOrder, null, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines)),
      (machines) => emit(SequencesMachinesSuccess(state.isNewOrder,machines, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines)) 
      );
  }

  void selectMachine(MachineTypeEntity m)async{
    //emit the state with the new machine selected
    List<NewTaskModel> selectedMachines = [];
    if(state.selectedMachines != null) selectedMachines = state.selectedMachines!;
    final newTask = NewTaskModel(m.id!, const Duration(hours: 1, minutes: 0), "", 0, m.name);
    emit(SequencesMachineAdded(state.isNewOrder,state.machines, state.isSuccessModalVisible , state.isNoMachinesModalVisible,selectedMachines..add(newTask)));
  }

  void useMode(bool isNewOrder)async{
    emit(SequencesModeChanged(isNewOrder, state.machines, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines));
  }
  

  void saveProcess(String processName)async{
    List<dynamic> parameters = [processName];
    for(int i = 0; i < state.selectedMachines!.length; i++){
      state.selectedMachines![i].execOrder = i+1;
    }
    parameters.add(state.selectedMachines);
    final response = await seqService.addSequence(state.selectedMachines!, processName);
    response.fold((f){
        modelChanged(true);
      },
      (success){
        emit(SequencesProcessAdded(true, state.machines, true, false, null));
      }
    );
    GetIt.instance.get<SeeProcessBloc>().retrieveSequences();
  }


  void modelChanged(bool isVisible) async{
    emit(SequencesMinimumStateChange(state.isNewOrder, state.machines, state.isSuccessModalVisible, isVisible, state.selectedMachines));
  }

  void machinesSuccessModalChanged(bool isVisible)async{
    emit(SequencesMinimumStateChange(state.isNewOrder, state.machines, isVisible, state.isNoMachinesModalVisible, state.selectedMachines));
  }

  void tsaskUpdated(int index, String description, String hour) async{
    state.selectedMachines![index].description = description;
    state.selectedMachines![index].processingUnit = Duration(
      hours: int.parse(hour.substring(0,2) ), 
      minutes:int.parse(hour.substring(3,5) ), 
    );
    emit(SequencesMachineAdded(state.isNewOrder, state.machines, state.isSuccessModalVisible, state.isSuccessModalVisible, state.selectedMachines));
  }

  void taskRemoved(int index) async{
    state.selectedMachines!.removeAt(index);
    emit(SequencesMachineAdded(state.isNewOrder, state.machines, state.isSuccessModalVisible, state.isSuccessModalVisible, state.selectedMachines));
  }
}