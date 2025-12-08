import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/presentation/1_sequences/request_models/new_task_model.dart';

abstract class SequencesState {
  bool isNewOrder;
  List<MachineTypeEntity>? machines;
  List<TaskDependencyEntity>? dependencies;
  bool isSuccessModalVisible;
  bool isNoMachinesModalVisible;
  List<NewTaskModel>? selectedMachines;

  SequencesState(this.isNewOrder, this.machines, this.isSuccessModalVisible,
      this.isNoMachinesModalVisible, this.selectedMachines, this.dependencies);
}

class SequencesInitialState extends SequencesState {
  SequencesInitialState(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}

class SequencesRetrievingMachines extends SequencesState {
  SequencesRetrievingMachines(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}

class SequencesMachinesSuccess extends SequencesState {
  SequencesMachinesSuccess(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}

class SequencesMachineFailure extends SequencesState {
  SequencesMachineFailure(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}

class SequencesModeChanged extends SequencesState {
  SequencesModeChanged(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}

class SequencesMachineAdded extends SequencesState {
  SequencesMachineAdded(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}

class SequencesMinimumStateChange extends SequencesState {
  SequencesMinimumStateChange(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}

class SequencesProcessAdded extends SequencesState {
  SequencesProcessAdded(
      super.isNewOrder,
      super.machines,
      super.isSuccessModalVisible,
      super.isNoMachinesModalVisible,
      super.selectedMachines,
      super.dependencies);
}
