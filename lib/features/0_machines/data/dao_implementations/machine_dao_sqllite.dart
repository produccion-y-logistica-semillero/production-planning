import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_dao.dart';
import 'package:sqflite/sqflite.dart';

class MachineDaoSqllite implements MachineDao{

  final Database db;

  MachineDaoSqllite(this.db);

  @override
  Future<bool> delete(int id) async {
    try {
      int n = await db.delete(
        'MACHINES',
        where: 'machine_id = ?',
        whereArgs: [id],
      );
      return n > 1 ? true : false;
    } catch (error) {
      print("Error deleting machine with id ${id}: ${error.toString()}");
      throw LocalStorageFailure();
    }
  }


  
  @override
  Future<bool> deleteWhere(String field, int value) async{
    try{
      int n = await db.delete('MACHINES', where: '? = ?', whereArgs: [field, value]);
      return n == 1 ? true: false;
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
}