import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/sequences/data/dao_interfaces/tasks_dao.dart';
import 'package:production_planning/features/sequences/data/models/task_model.dart';
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
  
}