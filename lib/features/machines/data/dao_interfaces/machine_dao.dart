import 'package:production_planning/features/machines/data/models/machine_model.dart';

abstract class MachineDao{
  Future<bool> delete(int id);
  Future<bool> deleteWhere(String field, int value);
  Future<int> insertMachine(Map<String, dynamic> modelJson);
}