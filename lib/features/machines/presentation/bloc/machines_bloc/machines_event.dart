sealed class MachinesEvent{

}

class OnMachinesRetrieving implements MachinesEvent{
  final int typeId;
  OnMachinesRetrieving(this.typeId);
}

class OnMachinesExpansionCollpased implements MachinesEvent{
}

class OnNewMachine implements MachinesEvent{
  final String capacity;
  final String preapartion;
  final String rest;
  final String continueCapacity;

  OnNewMachine(this.capacity, this.preapartion, this.rest, this.continueCapacity);
}