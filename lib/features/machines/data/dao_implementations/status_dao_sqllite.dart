import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/status_dao.dart';
import 'package:sqflite/sqflite.dart';

class StatusDaoSqllite implements StatusDao{
  final Database db;
  StatusDaoSqllite(this.db);

  @override
  Future<String> getNameById(int id) async{
    try{
      List<Map<String, dynamic>> table = (await db.query('STATUS', columns: ['name'], where: 'id = ?', whereArgs: [id]));
      return table[0]['name'];
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<int> getIdByName(String? name) async{
    try{
      List<Map<String, dynamic>> table = (await db.query('STATUS', columns: ['id'], where: 'name = ?', whereArgs: [name]));
      return table[0]['id'];
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
  
}