import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/tasks_dao.dart';
import 'package:production_planning/features/1_sequences/data/models/task_model.dart';
import 'package:sqflite/sqflite.dart';

class TasksDaoSqllite implements TasksDao{

  final Database db;

  TasksDaoSqllite(this.db);

  @override
  Future<int> createTask(TaskModel task) async{
    try{
      int id = await db.insert('TASKS', task.toJson());
      return id;
    }catch(error){
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<List<TaskModel>> getTasksBySequenceId(int id) async{
    try{
      return (await db.query('TASKS', where: 'sequence_id = ?', whereArgs: [id]))
      .map((json) { 
        return TaskModel.fromJson(json);
      })
      .toList();
    }catch(error){
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<bool> deleteTasks(int id) async{
    try{
      int nDeleted = await  db.delete('TASKS', where: 'sequence_id = ?', whereArgs: [id]);
      return nDeleted > 0;
    }catch(error){
      throw LocalStorageFailure();
    }
  }
  
}