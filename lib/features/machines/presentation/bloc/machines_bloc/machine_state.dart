import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

sealed class MachineState{
  //Since we want all states to still have the list, we move this attribute here
  //so all states have it
  List<MachineTypeEntity>? machineTypes;
  MachineState(this.machineTypes);
}

final class MachineInitial extends MachineState{
  MachineInitial(super.machineTypes);
}

final class MachineRetrieving extends MachineState{
  MachineRetrieving(super.machineTypes);
}

final class MachineRetrievingError extends MachineState{
  MachineRetrievingError(super.machineTypes);
}

final class MachineRetrievingSuccess extends MachineState{
  MachineRetrievingSuccess(super.machineTypes);
}

final class MachineAddingSuccess extends MachineState{
  MachineAddingSuccess(super.machineTypes);
}

final class MachineAddingError extends MachineState{
  MachineAddingError(super.machineTypes);
}

