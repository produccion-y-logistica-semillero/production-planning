import 'package:flutter/material.dart';

class NewTaskModel{
  final int machineTypeId;
  final TimeOfDay processingUnit;
  final String description;
  final int execOrder;

  NewTaskModel(this.machineTypeId, this.processingUnit, this.description, this.execOrder);

}