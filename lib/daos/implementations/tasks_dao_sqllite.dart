import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/tasks_dao.dart';
import 'package:production_planning/repositories/models/task_model.dart';
import 'package:sqflite/sqflite.dart';

class TasksDaoSqllite implements TasksDao{

  final Database db;

  TasksDaoSqllite(this.db);

  @override
  Future<int> createTask(TaskModel task, {DatabaseExecutor? executor}) async{
    try{
      int id = await (executor ?? db).insert('TASKS', task.toJson());
      return id;
    }catch(error){
      throw LocalStorageFailure();
    }
  }

  @override
  Future<List<TaskModel>> getTasksBySequenceId(int id,
      {DatabaseExecutor? executor}) async{
    try{
      return (await (executor ?? db)
              .query('TASKS', where: 'sequence_id = ?', whereArgs: [id]))
      .map((json) {
        return TaskModel.fromJson(json);
      })
      .toList();
    }catch(error){
      throw LocalStorageFailure();
    }
  }

  @override
  Future<bool> deleteTasks(int id, {DatabaseExecutor? executor}) async{
    try{
      int nDeleted = await (executor ?? db)
          .delete('TASKS', where: 'sequence_id = ?', whereArgs: [id]);
      return nDeleted > 0;
    }catch(error){
      throw LocalStorageFailure();
    }
  }

  @override
  Future<void> updateTask(TaskModel task, {DatabaseExecutor? executor}) async {
    if (task.taskId == null) throw LocalStorageFailure();
    try {
      final values = task.toJson()..remove('sequence_id');
      await (executor ?? db)
          .update('TASKS', values, where: 'task_id = ?', whereArgs: [task.taskId]);
    } catch (error) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<void> deleteTaskById(int taskId, {DatabaseExecutor? executor}) async {
    try {
      final DatabaseExecutor e = executor ?? db;
      // Foreign keys are not enforced in this database, so the rows that
      // point at the task are removed explicitly instead of left orphaned.
      await e.delete('TaskDependency',
          where: 'predecessor_id = ? OR successor_id = ?',
          whereArgs: [taskId, taskId]);
      await e.delete('job_task_machine_times',
          where: 'task_id = ?', whereArgs: [taskId]);
      await e.delete('TASKS', where: 'task_id = ?', whereArgs: [taskId]);
    } catch (error) {
      throw LocalStorageFailure();
    }
  }

}
