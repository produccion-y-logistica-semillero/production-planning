import 'package:production_planning/daos/interfaces/machine_dao.dart';
import 'package:production_planning/daos/interfaces/machine_type_dao.dart';
import 'package:production_planning/daos/interfaces/status_dao.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/daos/interfaces/task_dependency_dao.dart';
import 'package:production_planning/daos/interfaces/tasks_dao.dart';
import 'package:production_planning/daos/interfaces/dispatch_rules_dao.dart';
import 'package:production_planning/daos/interfaces/enviroment_dao.dart';
import 'package:production_planning/daos/interfaces/job_dao.dart';
import 'package:production_planning/daos/interfaces/order_dao.dart';

abstract class Factory{
  MachineTypeDao getMachineTypeDao();
  MachineDao getMachineDao();
  SequencesDao getSequenceDao();
  TasksDao getTaskDao();
  StatusDao getStatusDao();
  OrderDao getOrderDao();
  JobDao getJobDao();
  EnviromentDao getEnviromentDao();
  DispatchRulesDao getDispatchRulesDao();
  TaskDependencyDao getTaskDependencyDao();

  void closeDatabase();

}