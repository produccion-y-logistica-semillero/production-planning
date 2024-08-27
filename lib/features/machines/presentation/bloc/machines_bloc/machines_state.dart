import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

sealed class MachinesState{}

class MachinesStateInitial extends MachinesState{}

class MachinesRetrieving extends MachinesState{}

class MachinesRetrievingSuccess extends MachinesState{
  final List<MachineEntity> machines;

  MachinesRetrievingSuccess(this.machines);
}

class MachinesRetrievingError extends MachinesState{}