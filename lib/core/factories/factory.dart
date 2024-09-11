import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/sequences_dao.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/tasks_dao.dart';

abstract class Factory{
  MachineTypeDao getMachineTypeDao();
  MachineDao getMachineDao();
  SequencesDao getSequenceDao();
  TasksDao getTaskDao();
  void closeDatabase();
}