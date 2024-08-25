sealed class MachineEvent{}

class OnAddNewMachineType extends MachineEvent{
  final String name;
  final String description;

  OnAddNewMachineType(this.name, this.description);
}

class OnMachineTypeRetrieving extends MachineEvent{}

class OnDeleteMachineType extends MachineEvent{
  final int id;
  final int index;
  OnDeleteMachineType(this.id, this.index);
}