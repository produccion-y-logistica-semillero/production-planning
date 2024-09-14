import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/1_sequences/domain/request_models/new_task_model.dart';

abstract class SequencesState{
  bool isNewOrder;
  List<MachineTypeEntity>? machines;
  bool isSuccessModalVisible;
  bool isNoMachinesModalVisible;
  List<NewTaskModel>? selectedMachines;


  SequencesState(this.isNewOrder, this.machines, this.isSuccessModalVisible, this.isNoMachinesModalVisible, this.selectedMachines);

}

class SequencesInitialState extends SequencesState{
  SequencesInitialState(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}


class SequencesRetrievingMachines extends SequencesState{
  SequencesRetrievingMachines(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}


class SequencesMachinesSuccess extends SequencesState{
  SequencesMachinesSuccess(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}


class SequencesMachineFailure extends SequencesState{
  SequencesMachineFailure(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}

class SequencesModeChanged extends SequencesState{
  SequencesModeChanged(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}

class SequencesMachineAdded extends SequencesState{
  SequencesMachineAdded(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}

class SequencesMinimumStateChange extends SequencesState{
  SequencesMinimumStateChange(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}

class SequencesProcessAdded extends SequencesState{
   SequencesProcessAdded(super.isNewOrder, super.machines, super.isSuccessModalVisible, super.isNoMachinesModalVisible, super.selectedMachines);
}