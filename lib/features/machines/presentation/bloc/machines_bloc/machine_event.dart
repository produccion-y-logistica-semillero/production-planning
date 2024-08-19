sealed class MachineEvent{}

class OnAddNewMachine extends MachineEvent{
  final String name;
  final String description;

  OnAddNewMachine(this.name, this.description);
}

class OnMachineRetrieving extends MachineEvent{

}