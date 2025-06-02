import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/presentation/1_sequences/request_models/new_task_model.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_state.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/presentation/1_sequences/widgets/high_order_widgets/graph_editor.dart';
import 'package:production_planning/services/machines_service.dart';
import 'package:production_planning/services/sequences_service.dart';

class SequencesBloc extends Cubit<SequencesState>{

  final SequencesService seqService;
  final MachinesService  machinesService;

  SequencesBloc(
    this.seqService, this.machinesService

  ): super(SequencesInitialState(false, null, false, false, null,/* */ null)) {
    //initial state
    retrieveSequencesMachine();
  }

  void retrieveSequencesMachine() async{
    emit(SequencesRetrievingMachines(state.isNewOrder, null, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines, state.dependencies));
    final response = await machinesService.getMachineTypes();
    response.fold(
      (f) => emit(SequencesMachineFailure(state.isNewOrder, null, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines, state.dependencies)),
      (machines) => emit(SequencesMachinesSuccess(state.isNewOrder,machines, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines, state.dependencies)) 
      );
  }

  void selectMachine(MachineTypeEntity m)async{
    //emit the state with the new machine selected
    List<NewTaskModel> selectedMachines = [];
    if(state.selectedMachines != null) selectedMachines = state.selectedMachines!;
    final newTask = NewTaskModel(m.id!, const Duration(hours: 1, minutes: 0), "", 0, m.name);
    emit(SequencesMachineAdded(state.isNewOrder,state.machines, state.isSuccessModalVisible , state.isNoMachinesModalVisible,selectedMachines..add(newTask), state.dependencies));
  }

  void useMode(bool isNewOrder)async{
    emit(SequencesModeChanged(isNewOrder, state.machines, state.isSuccessModalVisible, state.isNoMachinesModalVisible, state.selectedMachines, state.dependencies));
  }
  


void saveProcess(String processName, List<MachineTypeEntity> nodes, List<Connection> connections) async {
  // 1. Crear tareas a partir de los nodos del grafo
  final tasks = nodes.map((machine) => NewTaskModel(
    machine.id!,
    const Duration(hours: 1), // Ajusta según tu UI
    machine.description ?? "",
    0, // Orden, puedes calcularlo si tu lógica lo requiere
    machine.name
  )).toList();

  // 2. Crear dependencias a partir de las conexiones del grafo
  final dependencies = connections.map((conn) => {
    'from': conn.source,
    'to': conn.target,
  }).toList();

  // 3. Guardar la secuencia con tareas y dependencias
  final response = await seqService.addSequenceWithGraph(tasks, dependencies, processName);

  response.fold(
    (f) => modelChanged(true),
    (success) => emit(SequencesProcessAdded(true, state.machines, true, false, null, null)),
  );
  GetIt.instance.get<SeeProcessBloc>().retrieveSequences();
}


  void modelChanged(bool isVisible) async{
    emit(SequencesMinimumStateChange(state.isNewOrder, state.machines, state.isSuccessModalVisible, isVisible, state.selectedMachines, state.dependencies));
  }

  void machinesSuccessModalChanged(bool isVisible)async{
    emit(SequencesMinimumStateChange(state.isNewOrder, state.machines, isVisible, state.isNoMachinesModalVisible, state.selectedMachines, state.dependencies));
  }

  void tsaskUpdated(int index, String description, String hour) async{
    state.selectedMachines![index].description = description;
    state.selectedMachines![index].processingUnit = Duration(
      hours: int.parse(hour.substring(0,2) ), 
      minutes:int.parse(hour.substring(3,5) ), 
    );
    emit(SequencesMachineAdded(state.isNewOrder, state.machines, state.isSuccessModalVisible, state.isSuccessModalVisible, state.selectedMachines, state.dependencies));
  }

  void taskRemoved(int index) async{
    state.selectedMachines!.removeAt(index);
    emit(SequencesMachineAdded(state.isNewOrder, state.machines, state.isSuccessModalVisible, state.isSuccessModalVisible, state.selectedMachines, state.dependencies));
  }
}