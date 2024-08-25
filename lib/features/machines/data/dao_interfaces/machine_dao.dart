import 'package:production_planning/features/machines/data/models/machine_model.dart';

abstract class MachineDao{
   Future<List<MachineModel>> getAllMachines() ;
    Future<int> insertMachine(MachineModel model);
}