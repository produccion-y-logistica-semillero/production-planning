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