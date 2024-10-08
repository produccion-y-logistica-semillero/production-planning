import 'package:flutter/material.dart';

class NewTaskModel{
  final int machineTypeId;
  Duration processingUnit;
  String description;
  int execOrder;
  final String machineName;

  NewTaskModel(this.machineTypeId, this.processingUnit, this.description, this.execOrder, this.machineName);

}