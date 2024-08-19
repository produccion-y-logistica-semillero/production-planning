import 'package:dartz/dartz.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

sealed class MachineState{
  //Since we want all states to still have the list, we move this attribute here
  //so all states have it
  List<MachineEntity>? machines;
  MachineState(this.machines);
}

final class MachineInitial extends MachineState{
  MachineInitial(super.machines);
}

final class MachineRetrieving extends MachineState{
  MachineRetrieving(super.machines);
}

final class MachineRetrievingError extends MachineState{
  MachineRetrievingError(super.machines);
}

final class MachineRetrievingSuccess extends MachineState{
  MachineRetrievingSuccess(super.machines);
}

final class MachineAddingSuccess extends MachineState{
  MachineAddingSuccess(super.machines);
}

final class MachineAddingError extends MachineState{
  MachineAddingError(super.machines);
}

