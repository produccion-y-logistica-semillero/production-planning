import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/status_dao.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/sequences_dao.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/tasks_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/dispatch_rules_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/enviroment_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/job_dao.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/order_dao.dart';

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

  void closeDatabase();
}