abstract class MachineDao{
  Future<bool> delete(int id);
  Future<bool> deleteWhere(String field, int value);
}