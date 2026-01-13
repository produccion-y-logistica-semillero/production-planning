import 'package:production_planning/entities/machine_type_entity.dart';

sealed class MachineTypeState{


  //Since we want all states to still have the list, we move this attribute here
  //so all states have it
  List<MachineTypeEntity>? machineTypes;
  MachineTypeState(this.machineTypes);
}

final class MachineTypeInitial extends MachineTypeState {
  MachineTypeInitial(super.machineTypes);
}

final class MachineTypesRetrieving extends MachineTypeState {
  MachineTypesRetrieving(super.machineTypes);
}

final class MachineTypesRetrievingError extends MachineTypeState {
  MachineTypesRetrievingError(super.machineTypes);
}

final class MachineTypesRetrievingSuccess extends MachineTypeState {
  MachineTypesRetrievingSuccess(super.machineTypes);
}

final class MachineTypesAddingSuccess extends MachineTypeState {
  MachineTypesAddingSuccess(super.machineTypes);
}

final class MachineTypesAddingError extends MachineTypeState {
  MachineTypesAddingError(super.machineTypes);
}

final class MachineTypeDeletionError extends MachineTypeState {
  MachineTypeDeletionError(super.machineTypes);
}

final class MachineTypeDeletionSuccess extends MachineTypeState {
  MachineTypeDeletionSuccess(super.machineTypes);
}