import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';

abstract class SequencesEvent{}


class OnUseModeEvent implements SequencesEvent{
  final bool isNewOrder;
  OnUseModeEvent(this.isNewOrder);
}

class OnSelectMachine implements SequencesEvent{
  final MachineTypeEntity machine;
  OnSelectMachine(this.machine);
}

class OnSequencesMachineRetrieve implements SequencesEvent{}

class OnSequencesSaveProcess implements SequencesEvent{
  final String processName;

  OnSequencesSaveProcess(this.processName);
}

class OnMachinesModalChanged implements SequencesEvent{
  final bool isVisible;

  OnMachinesModalChanged(this.isVisible);

}

class OnMachinesSuccessModalChanged implements SequencesEvent{
  final bool isVisible;

  OnMachinesSuccessModalChanged(this.isVisible);
}