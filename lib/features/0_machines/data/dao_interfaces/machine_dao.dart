import 'package:production_planning/features/machines/data/models/machine_model.dart';
import 'package:production_planning/features/machines/domain/entities/machine_entity.dart';

abstract class MachineDao{
  Future<bool> delete(int id);
  Future<bool> deleteWhere(String field, int value);
  Future<int> insertMachine(Map<String, dynamic> machineJson);

  Future<List<Map<String, dynamic>>> getMachinesByType(int machineTypeId);
}