import 'package:production_planning/repositories/models/task_model.dart';

abstract class TasksDao{
  Future<int> createTask(TaskModel task);
  Future<List<TaskModel>> getTasksBySequenceId(int id);
  Future<bool> deleteTasks(int id);
}