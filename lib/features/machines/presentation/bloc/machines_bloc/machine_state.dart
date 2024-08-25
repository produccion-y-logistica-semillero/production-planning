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

final class MachineTypesRetrieving extends MachineState{
  MachineTypesRetrieving(super.machineTypes);
}

final class MachineTypesRetrievingError extends MachineState{
  MachineTypesRetrievingError(super.machineTypes);
}

final class MachineTypesRetrievingSuccess extends MachineState{
  MachineTypesRetrievingSuccess(super.machineTypes);
}

final class MachineTypesAddingSuccess extends MachineState{
  MachineTypesAddingSuccess(super.machineTypes);
}

final class MachineTypesAddingError extends MachineState{
  MachineTypesAddingError(super.machineTypes);
}

final class MachineTypeDeletionError extends MachineState{
  MachineTypeDeletionError(super.machineTypes);
}

final class MachineTypeDeletionSuccess extends MachineState{
  MachineTypeDeletionSuccess(super.machineTypes);
}

