class NewTaskModel {
  final int machineTypeId;
  Duration processingUnit;
  String description;
  final String machineName;
  bool allowPreemption;

  NewTaskModel(this.machineTypeId, this.processingUnit, this.description,
      this.machineName,
      {this.allowPreemption = false});
}
