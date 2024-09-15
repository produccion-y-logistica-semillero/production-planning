import 'package:flutter/material.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';

class TaskEntity{
  int? id;
  final int execOrder;
  final TimeOfDay processingUnits;
  final String description;
  final int machineTypeId;
  String? machineName;

  TaskEntity({
    this.id,
    required this.execOrder,
    required this.processingUnits,
    required this.description,
    required this.machineTypeId,
    required this.machineName,
  });

}