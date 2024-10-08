import 'package:production_planning/features/2_orders/data/models/enviroment_model.dart';

abstract class EnviromentDao {
  Future<EnviromentModel> getEnviromentByName(String name);
}
