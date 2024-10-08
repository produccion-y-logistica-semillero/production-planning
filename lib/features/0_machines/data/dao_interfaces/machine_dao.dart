
abstract class MachineDao{
  Future<bool> delete(int id);
  Future<bool> deleteWhere(String field, int value);
  Future<int> insertMachine(Map<String, dynamic> machineJson);
  Future<int> getMachinesCount(int machineTypeId);
  Future<List<Map<String, dynamic>>> getMachinesByType(int machineTypeId);
}