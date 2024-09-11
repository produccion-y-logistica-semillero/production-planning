import 'package:production_planning/features/1_sequences/data/models/task_model.dart';

abstract class TasksDao{
  Future<int> createTask(TaskModel task);
  Future<List<TaskModel>> getTasksBySequenceId(int id);
}