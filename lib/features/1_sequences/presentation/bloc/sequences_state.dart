import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';

abstract class SequencesState{
  bool isNewOrder;
  List<MachineTypeEntity>? machines;

  SequencesState(this.isNewOrder, this.machines);

}

class SequencesInitialState extends SequencesState{
  SequencesInitialState(super.isNewOrder, super.machines);
}


class SequencesRetrievingMachines extends SequencesState{
  SequencesRetrievingMachines(super.isNewOrder, super.machines);
}


class SequencesMachinesSuccess extends SequencesState{
  SequencesMachinesSuccess(super.isNewOrder, super.machines);
}


class SequencesMachineFailure extends SequencesState{
  SequencesMachineFailure(super.isNewOrder, super.machines);
}

class SequencesModeChanged extends SequencesState{
  SequencesModeChanged(super.isNewOrder, super.machines);
}
