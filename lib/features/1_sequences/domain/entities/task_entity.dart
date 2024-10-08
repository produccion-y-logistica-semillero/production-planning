import 'package:flutter/material.dart';

class TaskEntity{
  int? id;
  final int execOrder;
  final Duration processingUnits;
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