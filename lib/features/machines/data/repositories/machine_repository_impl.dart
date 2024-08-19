import 'package:production_planning/features/machines/data/data_sources/machine_data_source_sqllite.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';

class MachineRepositoryImpl implements MachineRepository{

  final MachineDataSourceSqllite sqlLiteSource;

  MachineRepositoryImpl({required this.sqlLiteSource});

}