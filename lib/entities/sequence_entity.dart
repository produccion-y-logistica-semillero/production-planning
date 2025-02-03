import 'package:production_planning/entities/task_entity.dart';

class SequenceEntity{
  final int? id;
  final String name;
  List<TaskEntity>? tasks;
  
  SequenceEntity(this.id, this.tasks, this.name);
}