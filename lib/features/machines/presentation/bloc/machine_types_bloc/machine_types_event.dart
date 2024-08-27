sealed class MachineTypeEvent{}

//Event for when a new Machine type added
class OnAddNewMachineType implements MachineTypeEvent{
  final String name;
  final String description;

  OnAddNewMachineType(this.name, this.description);
}

//Events for when retrieving all machine types
class OnMachineTypeRetrieving implements MachineTypeEvent{}

//Event for when a machine type deleted
class OnDeleteMachineType implements MachineTypeEvent{
  final int id;
  final int index;
  OnDeleteMachineType(this.id, this.index);
}
