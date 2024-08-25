import 'package:production_planning/features/machines/data/models/machine_type_model.dart';

abstract class MachineTypeDao{
  Future<List<MachineTypeModel>> getAllMachines() ;
  Future<int> insertMachine(MachineTypeModel model);
}