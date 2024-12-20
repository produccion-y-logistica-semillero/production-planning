import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/core/factories/factory.dart';
import 'package:production_planning/features/0_machines/data/dao_implementations/machine_dao_sqllite.dart';
import 'package:production_planning/features/0_machines/data/dao_implementations/machine_type_dao_sqllite.dart';
import 'package:production_planning/features/0_machines/data/dao_implementations/status_dao_sqllite.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/status_dao.dart';
import 'package:production_planning/features/1_sequences/data/dao_implementations/sequences_dao_sqllite.dart';
import 'package:production_planning/features/1_sequences/data/dao_implementations/tasks_dao_sqllite.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/sequences_dao.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/tasks_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_implementations/dispatch_rules_dao_sqllite.dart';
import 'package:production_planning/features/2_orders/data/dao_implementations/enviroment_dao_sqllite.dart';
import 'package:production_planning/features/2_orders/data/dao_implementations/job_dao_sqllite.dart';
import 'package:production_planning/features/2_orders/data/dao_implementations/order_dao_sqllite.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/dispatch_rules_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/enviroment_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/job_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/order_dao.dart';
import 'package:sqflite/sqflite.dart';

class SqlLiteFactory implements Factory{

  final Database db;
  MachineTypeDaoSQLlite? machineTypeDaoSQLlite;
  MachineDaoSqllite? machineDaoSqllite;
  SequencesDaoSqllite? sequencesDaoSqllite;
  TasksDaoSqllite? tasksDaoSqllite;
  StatusDaoSqllite? statusDaoSqllite;
  OrderDaoSqlLite? orderDaoSqlLite;
  JobDaoSQLlite? jobDaoSQLlite;
  DispatchRulesDao? dispatchRulesDao;
  EnviromentDao? enviromentDao;

  //static factory constructor to perform async operation
  static Future<SqlLiteFactory> create(String wrkspace) async{
    Database db = await  SQLLiteDatabaseProvider.open(wrkspace);
    return SqlLiteFactory(db);
  }

  SqlLiteFactory(this.db);

  @override
  MachineTypeDao getMachineTypeDao() {
    return machineTypeDaoSQLlite ??= MachineTypeDaoSQLlite(db);
  }
  @override
  MachineDao getMachineDao(){ 
    return machineDaoSqllite ??= MachineDaoSqllite(db);
  }

  @override
  SequencesDao getSequenceDao() {
    return sequencesDaoSqllite ??= SequencesDaoSqllite(db);
  }

  @override
  TasksDao getTaskDao() {
    return tasksDaoSqllite ??= TasksDaoSqllite(db);
  }

  @override
  StatusDao getStatusDao() {
     return statusDaoSqllite ??= StatusDaoSqllite(db);
  }

  @override
  JobDao getJobDao() {
    return jobDaoSQLlite ??= JobDaoSQLlite(db);
  }

  @override
  OrderDao getOrderDao() {
    return orderDaoSqlLite ??= OrderDaoSqlLite(db);
  }
  
  @override
  DispatchRulesDao getDispatchRulesDao() {
    return dispatchRulesDao ??= DispatchRulesDaoSqllite(db);
  }
  
  @override
  EnviromentDao getEnviromentDao() {
    return enviromentDao ??= EnviromentDaoSqllite(db);
  }

  @override
  void closeDatabase() {
    SQLLiteDatabaseProvider.closeDatabaseConnection();
  }
}