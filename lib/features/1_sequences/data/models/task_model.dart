import 'package:flutter/material.dart';
import 'package:production_planning/features/1_sequences/domain/entities/task_entity.dart';

class TaskModel{
  int? taskId;
  final int execOrder;
  final TimeOfDay nProcUnits;
  final String description;
  final int sequenceId;
  final int machineTypeId;

  TaskModel({
    this.taskId,
    required this.execOrder, 
    required this.nProcUnits,
    required this.description, 
    required this.sequenceId, 
    required this.machineTypeId
  });

  factory TaskModel.fromEntity(TaskEntity entity, int sequenceId){
    return TaskModel(
      execOrder: entity.execOrder, 
      nProcUnits: entity.processingUnits,
      description: entity.description, 
      sequenceId: sequenceId, 
      machineTypeId: entity.machineTypeId);
  }

  factory TaskModel.fromJson(Map<String, dynamic> map){
    return TaskModel(
      execOrder: map["exec_order"], 
      nProcUnits: map["n_proc_units"], 
      description: map["description"], 
      sequenceId: map["sequence_id"], 
      machineTypeId: map["machine_type_id"]
    );
  }

  Map<String, dynamic> toJson(){
    String timeStamp = '${nProcUnits.hour.toString().padLeft(2, '0')}:${nProcUnits.minute.toString().padLeft(2, '0')}:00'; 
    return {
      "sequence_id": sequenceId,
      "machine_type_id" : machineTypeId,
      "exec_order" : execOrder,
      "n_proc_units" : '1970-01-01 $timeStamp', //the default date since we only care about the time, not date
      "description" : description
    };
  }

  TaskEntity toEntity(){
    return TaskEntity(
      execOrder: execOrder, 
      processingUnits: nProcUnits, 
      description: description, 
      machineTypeId: machineTypeId);
  }

}