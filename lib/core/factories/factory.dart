import 'package:production_planning/features/machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/machine_type_dao.dart';

abstract class Factory{
  MachineTypeDao getMachineTypeDao();
  MachineDao getMachineDao();
  void closeDatabase();
}