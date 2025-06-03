import 'package:production_planning/core/data/db/sqllite_database_provider.dart';
import 'package:production_planning/core/factories/factory.dart';
import 'package:production_planning/daos/implementations/machine_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/machine_type_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/status_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/task_dependency_dao_sqllite.dart';
import 'package:production_planning/daos/interfaces/machine_dao.dart';
import 'package:production_planning/daos/interfaces/machine_type_dao.dart';
import 'package:production_planning/daos/interfaces/status_dao.dart';
import 'package:production_planning/daos/implementations/sequences_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/tasks_dao_sqllite.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/daos/interfaces/task_dependency_dao.dart';
import 'package:production_planning/daos/interfaces/tasks_dao.dart';
import 'package:production_planning/daos/implementations/dispatch_rules_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/enviroment_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/job_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/order_dao_sqllite.dart';
import 'package:production_planning/daos/interfaces/dispatch_rules_dao.dart';
import 'package:production_planning/daos/interfaces/enviroment_dao.dart';
import 'package:production_planning/daos/interfaces/job_dao.dart';
import 'package:production_planning/daos/interfaces/order_dao.dart';
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
  TaskDependencyDao? taskDependencyDao;


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
  TaskDependencyDao getTaskDependencyDao() {
    return taskDependencyDao ??= TaskDependencyDaoSqllite(db);
  }

  @override
  void closeDatabase() {
    SQLLiteDatabaseProvider.closeDatabaseConnection();
  }
}