import 'package:production_planning/repositories/models/task_dependency_model.dart';

abstract class TaskDependencyDao {
  Future<int> createTaskDependency(TaskDependencyModel dependency);
  Future<List<TaskDependencyModel>> getDependenciesByTaskId(int taskId);
  Future<bool> deleteDependencies(int taskId);
}