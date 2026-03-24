import 'package:production_planning/repositories/models/enviroment_model.dart';

abstract class EnviromentDao {
  Future<EnviromentModel> getEnviromentByName(String name);
}
