import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/task_dependency_dao.dart';
import 'package:production_planning/repositories/models/task_dependency_model.dart';
import 'package:sqflite/sqflite.dart';

class TaskDependencyDaoSqllite implements TaskDependencyDao {
  final Database db;

  TaskDependencyDaoSqllite(this.db);

  @override
  Future<int> createTaskDependency(TaskDependencyModel dependency) async {
    try {
      int id = await db.insert('TaskDependency', {
        'predecessor_id': dependency.dependsOnTaskId,
        'successor_id': dependency.taskId,
        'description': dependency.description,
        'sequence_id': dependency.sequenceId,
      });
      return id;
    } catch (error) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<List<TaskDependencyModel>> getDependenciesByTaskId(int taskId) async {
    try {
      final result = await db.query(
        'TaskDependency',
        where: 'successor_id = ?',
        whereArgs: [taskId],
      );
      return result.map((json) => TaskDependencyModel.fromJson(json)).toList();
    } catch (error) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<bool> deleteDependencies(int taskId) async {
    try {
      int nDeleted = await db.delete(
        'TaskDependency',
        where: 'successor_id = ?',
        whereArgs: [taskId],
      );
      return nDeleted > 0;
    } catch (error) {
      throw LocalStorageFailure();
    }
  }
}