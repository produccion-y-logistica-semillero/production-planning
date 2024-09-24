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
  final String machineName;
  final int typeId;

  OnNewMachine(this.capacity, this.preapartion, this.rest, this.continueCapacity, this.typeId, this.machineName);
}

class OnDeleteMachine implements MachinesEvent{
  final int machineID;
  
  OnDeleteMachine(this.machineID);
}

class OnMachinesSetType implements MachinesEvent{
  final int typeId;
  
  OnMachinesSetType(this.typeId);
}