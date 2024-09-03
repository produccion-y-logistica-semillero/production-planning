import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/core/factories/factory.dart';
import 'package:production_planning/features/machines/data/dao_implementations/machine_dao_sqllite.dart';
import 'package:production_planning/features/machines/data/dao_implementations/machine_type_dao_sqllite.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:sqflite/sqflite.dart';

class SqlLiteFactory implements Factory{

  final Database db;

  //static factory constructor to perform async operation
  static Future<SqlLiteFactory> create() async{
    Database db = await  SQLLiteDatabaseProvider.open();
    return SqlLiteFactory(db);
  }

  SqlLiteFactory(this.db);

  @override
  MachineTypeDao getMachineTypeDao() => MachineTypeDaoSQLlite(db);
  @override
  MachineDao getMachineDao() => MachineDaoSqllite(db);

  @override
  void closeDatabase() {
    SQLLiteDatabaseProvider.closeDatabaseConnection();
  }
}