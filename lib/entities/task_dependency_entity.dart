import 'package:production_planning/repositories/models/task_dependency_model.dart';

class TaskDependencyEntity {
  int? id;
  final int successor_id;
  final int predecessor_id;
  final int sequenceId;

  TaskDependencyEntity({
    this.id,
    required this.successor_id,
    required this.predecessor_id,
    required this.sequenceId,
  });

  TaskDependencyModel toModel() {
    print('Converting TaskDependencyEntity to TaskDependencyModel');
    return TaskDependencyModel(
      id: id,
      successor_id: successor_id,
      predecessor_id: predecessor_id,
      sequenceId: sequenceId,
    );
  }
}