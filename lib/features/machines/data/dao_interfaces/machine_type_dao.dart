import 'package:production_planning/features/machines/data/models/machine_type_model.dart';

abstract class MachineTypeDao{

  //get methods for database schema info, we use these so that 
  //the repository can call them if it needs schema info, since repository should only coordinate
  //daos and only daos should now specific database schema implementation
  String getTableName();
  String getTablePK();

  //operations
  Future<List<MachineTypeModel>> getAllMachines() ;
  Future<int> insertMachine(MachineTypeModel model);
  Future<bool> deleteMachine(int id);

  
}