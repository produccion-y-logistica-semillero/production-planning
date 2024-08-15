import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

sealed class MachineState{}

final class MachineList extends MachineState{
  final List<MachineEntity> machines;

  MachineList(this.machines);

}

final class MachineInitial extends MachineState{
  
}
