import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';

sealed class MachinesState{
  final List<MachineEntity>? machines;
  MachinesState(this.machines);
}

class MachinesStateInitial extends MachinesState{
  MachinesStateInitial(super.machines);
}

class MachinesRetrieving extends MachinesState{
  MachinesRetrieving(super.machines);
}

class MachinesRetrievingSuccess extends MachinesState{
  MachinesRetrievingSuccess(super.machines);
}

class MachinesRetrievingError extends MachinesState{
  MachinesRetrievingError(super.machines);
}

class MachineDeletionError extends MachinesState{
  MachineDeletionError(super.machines);
}

class MachineDeletionSuccess extends MachinesState{
  MachineDeletionSuccess(super.machines);
}