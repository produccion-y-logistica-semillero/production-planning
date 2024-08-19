import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/machines/data/models/machine_model.dart';
import 'package:sqflite/sqflite.dart';

class MachineDataSourceSqllite {

  final Database db;
  MachineDataSourceSqllite(this.db);

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


  Future<void> insertMachine(MachineModel model) async{
    try{
      await db.insert('MACHINE_TYPES', model.toJson());
    }
    catch(error){
      print("ERORRRRRRRRRRRRRRRRRRRRRR ${error.toString()}");
      throw LocalStorageFailure();
    }
  }

}