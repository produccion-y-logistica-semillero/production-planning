abstract class StatusDao{
  Future<String> getNameById(int id);
  Future<int> getIdByName(String? name);
  Future<int> getDefaultStatusId();
}
