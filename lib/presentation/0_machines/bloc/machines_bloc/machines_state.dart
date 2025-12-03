import 'package:production_planning/entities/machine_entity.dart';

sealed class MachinesState{
  final List<MachineEntity>? machines;
  final int? typeId;
  MachinesState(this.machines, this.typeId);
}

class MachinesStateInitial extends MachinesState{
  MachinesStateInitial(super.machines, super.typeId);
}

class MachinesRetrieving extends MachinesState{
  MachinesRetrieving(super.machines,  super.typeId);
}

class MachinesRetrievingSuccess extends MachinesState{
  MachinesRetrievingSuccess(super.machines,  super.typeId);
}

class MachinesRetrievingError extends MachinesState{
  MachinesRetrievingError(super.machines,  super.typeId);
}

class MachineDeletionError extends MachinesState{
  MachineDeletionError(super.machines,  super.typeId);
}

class MachineDeletionSuccess extends MachinesState{
  MachineDeletionSuccess(super.machines,  super.typeId);
}

class MachineTypeIdSet extends MachinesState{
  MachineTypeIdSet(super.machines,  super.typeId);
}