import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/enviroment_dao.dart';
import 'package:production_planning/repositories/models/enviroment_model.dart';
import 'package:sqflite/sqflite.dart';


class EnviromentDaoSqllite implements EnviromentDao{

  final Database db;

  EnviromentDaoSqllite(this.db);

  @override
  Future<EnviromentModel> getEnviromentByName(String name) async {
    try {
      return (await db
              .query('environments', where: 'name = ?', whereArgs: [name]))
          .map((map) => EnviromentModel.fromJSON(map))
          .first;
    } catch (failure) {
      throw LocalStorageFailure();
    }
  }
}

