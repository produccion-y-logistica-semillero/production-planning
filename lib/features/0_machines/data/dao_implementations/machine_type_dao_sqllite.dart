import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/0_machines/data/models/machine_type_model.dart';
import 'package:sqflite/sqflite.dart';

class MachineTypeDaoSQLlite implements MachineTypeDao{

  final Database db;
  MachineTypeDaoSQLlite(this.db);


  @override
  String getTableName() => "MACHINE_TYPES";
  
  @override
  String getTablePK() => "machine_type_id";

  //THE ERRORS PRINTED HERE ARE JUST BY NOW, OBVIOUSLY WE HAVE TO CHANGE THOSE 
  //TO LOGS, AND THEN TO LITERALLLLY MANAGING ALL POSSIBLE ERRORS
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

  @override
  Future<bool> deleteMachine(int id) async {
    try{
      await db.delete('MACHINE_TYPES', where: 'machine_type_id = ?', whereArgs: [id]);
      return true;
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<String> getMachineName(int id) async {
    try{
      final response = await db.query('MACHINE_TYPES', where: 'machine_type_id = ?', whereArgs: [id]);
      return response[0]["name"].toString();
    }
    catch(error){
      throw LocalStorageFailure();
    }
  }

}