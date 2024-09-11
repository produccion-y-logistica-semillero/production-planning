import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/status_dao.dart';
import 'package:production_planning/features/machines/data/models/machine_model.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:sqflite/sqflite.dart';

class MachineDaoSqllite implements MachineDao{

  final Database db;

  MachineDaoSqllite(this.db);

  @override
  Future<bool> delete(int id) {
    // TODO: implement delete
    throw UnimplementedError();
  }

  

  @override
  Future<bool> deleteWhere(String field, int value) async{
    try{
      await db.delete('MACHINES', where: '? = ?', whereArgs: [field, value]);
      return true;
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> insertMachine(Map<String, dynamic> modelJson) async{
    try{
      int id = await db.insert('MACHINES', modelJson);
      return id;
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }

  
}