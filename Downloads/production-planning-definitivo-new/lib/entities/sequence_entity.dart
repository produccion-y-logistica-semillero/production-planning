
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
class SequenceEntity{

  final int? id;
  final String name;
  List<TaskEntity>? tasks;
  List<TaskDependencyEntity>? dependencies;
  SequenceEntity(this.id, this.tasks, this.name, this.dependencies);

}

