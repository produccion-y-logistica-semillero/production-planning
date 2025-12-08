import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/status_dao.dart';
import 'package:sqflite/sqflite.dart';

class StatusDaoSqllite implements StatusDao {
  final Database db;
  StatusDaoSqllite(this.db);

  @override
  Future<String> getNameById(int id) async {
    try {
      List<Map<String, dynamic>> table = (await db.query('STATUS',
          columns: ['status'], where: 'status_id = ?', whereArgs: [id]));
      return table[0]['status'];
    } catch (error) {
      print("ERORR FROM GET NAME BY ID STATUS ${error.toString()}");
      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> getIdByName(String? name) async {
    try {
      List<Map<String, dynamic>> table = (await db.query('STATUS',
          columns: ['status_id'], where: 'status = ?', whereArgs: [name]));
      return table[0]['status_id'];
    } catch (error) {
      print("ERORR FROM GETIDBYNAME STATUS ${error.toString()}");
      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> getDefaultStatusId() async {
    try {
      return 1;
    } catch (error) {
      print("ERORR FROM GETDEFAULT STATUS ID FROM STATUS ${error.toString()}");
      throw LocalStorageFailure();
    }
  }
}
