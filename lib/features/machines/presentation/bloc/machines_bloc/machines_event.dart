sealed class MachinesEvent{

}

class OnMachinesRetrieving implements MachinesEvent{
  final int typeId;
  OnMachinesRetrieving(this.typeId);
}

class OnMachinesExpansionCollpased implements MachinesEvent{
}