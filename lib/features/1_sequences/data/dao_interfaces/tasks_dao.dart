import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/1_sequences/data/models/task_model.dart';

abstract class TasksDao{
  Future<int> createTask(TaskModel task);
}