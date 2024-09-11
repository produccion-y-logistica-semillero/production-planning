import 'package:production_planning/features/1_sequences/domain/entities/task_entity.dart';

class SequenceEntity{
  final String name;
  final List<TaskEntity>? tasks;
  
  SequenceEntity(this.tasks, this.name);
}