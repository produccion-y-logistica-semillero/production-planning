import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/machines/data/models/machine_model.dart';
import 'package:sqflite/sqflite.dart';

class MachineDaoSQLlite implements MachineDao{

  final Database db;
  MachineDaoSQLlite(this.db);

  Future<List<MachineModel>> getAllMachines() async {
    print("trying to get all the machinessss");
    try{
      return (await db.query('MACHINE_TYPES'))
      .map((map)=> MachineModel.fromJson(map))
      .toList();
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }


  Future<int> insertMachine(MachineModel model) async{
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