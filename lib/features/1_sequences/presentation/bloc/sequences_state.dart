import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';

abstract class SequencesState{
  bool isNewOrder = false;
}

class SequencesInitialState extends SequencesState{}


class SequencesRetrievingMachines extends SequencesState{}


class SequencesMachinesSuccess extends SequencesState{
  List<MachineTypeEntity> machines;

  SequencesMachinesSuccess(this.machines);
}


class SequencesMachineFailure extends SequencesState{}
