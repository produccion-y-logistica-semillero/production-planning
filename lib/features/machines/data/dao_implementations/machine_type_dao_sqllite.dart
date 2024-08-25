import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/machines/data/models/machine_type_model.dart';
import 'package:sqflite/sqflite.dart';

class MachineTypeDaoSQLlite implements MachineTypeDao{

  final Database db;
  MachineTypeDaoSQLlite(this.db);

  @override
  Future<List<MachineTypeModel>> getAllMachines() async {
    //await db.rawQuery('SELECT * FROM machine_types');
    try{
      return (await db.query('MACHINE_TYPES'))
      .map((map)=> MachineTypeModel.fromJson(map))
      .toList();
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> insertMachine(MachineTypeModel model) async{
    try{
      int id = await db.insert('MACHINE_TYPES', model.toJson());
      return id;
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }

}