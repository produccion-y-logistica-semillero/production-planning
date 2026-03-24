abstract class MachineInactivityDao {
  Future<List<Map<String, dynamic>>> getByMachineId(int machineId);

  Future<int> insert(Map<String, dynamic> inactivityJson);

  Future<bool> update(int inactivityId, Map<String, dynamic> inactivityJson);

  Future<bool> delete(int inactivityId);
}
