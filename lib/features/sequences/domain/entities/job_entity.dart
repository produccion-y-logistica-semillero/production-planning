import 'package:production_planning/features/sequences/domain/entities/task_entity.dart';

class JobEntity{
  final String name;
  final List<TaskEntity> tasks;
  
  JobEntity(this.tasks, this.name);
}