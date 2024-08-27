sealed class MachineEvent{}

//Event for when a new Machine type added
class OnAddNewMachineType implements MachineEvent{
  final String name;
  final String description;

  OnAddNewMachineType(this.name, this.description);
}

//Events for when retrieving all machine types
class OnMachineTypeRetrieving implements MachineEvent{}

//Event for when a machine type deleted
class OnDeleteMachineType implements MachineEvent{
  final int id;
  final int index;
  OnDeleteMachineType(this.id, this.index);
}


//Event for when machines from certaing machine type retrieving
class OnMachinesRetrieving implements MachineEvent{
  final int id;
  final int index;
   OnMachinesRetrieving(this.id, this.index);
}