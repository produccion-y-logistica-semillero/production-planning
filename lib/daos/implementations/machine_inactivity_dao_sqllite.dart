import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/machine_inactivity_dao.dart';
import 'package:sqflite/sqflite.dart';

class MachineInactivityDaoSqllite implements MachineInactivityDao {
  final Database db;

  MachineInactivityDaoSqllite(this.db);

  @override
  Future<List<Map<String, dynamic>>> getByMachineId(int machineId) async {
    try {
      return await db.query(
        'MACHINE_INACTIVITIES',
        where: 'machine_id = ?',
        whereArgs: [machineId],
        orderBy: 'start_time ASC',
      );
    } catch (_) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> insert(Map<String, dynamic> inactivityJson) async {
    try {
      return await db.insert('MACHINE_INACTIVITIES', inactivityJson);
    } catch (_) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<bool> update(int inactivityId, Map<String, dynamic> inactivityJson) async {
    try {
      final updated = await db.update(
        'MACHINE_INACTIVITIES',
        inactivityJson,
        where: 'inactivity_id = ?',
        whereArgs: [inactivityId],
      );
      return updated > 0;
    } catch (_) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<bool> delete(int inactivityId) async {
    try {
      final deleted = await db.delete(
        'MACHINE_INACTIVITIES',
        where: 'inactivity_id = ?',
        whereArgs: [inactivityId],
      );
      return deleted > 0;
    } catch (_) {
      throw LocalStorageFailure();
    }
  }
}
