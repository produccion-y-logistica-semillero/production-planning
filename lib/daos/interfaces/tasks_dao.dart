import 'package:production_planning/repositories/models/task_model.dart';

abstract class TasksDao {
  Future<int> createTask(TaskModel task);
  Future<List<TaskModel>> getTasksBySequenceId(int id);
  Future<bool> deleteTasks(int id);

  /// Updates the time, description and interruptible default of an existing
  /// task, keeping its id.
  Future<void> updateTask(TaskModel task);

  /// Deletes one task, its arrows and the per-job times stored for it.
  Future<void> deleteTaskById(int taskId);
}
