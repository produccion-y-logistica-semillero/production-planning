import 'package:dartz/dartz.dart';

class EnvironmentEntity {
  final int environmentId;
  final String name;
  List<Tuple2<int, String>> rules;

  EnvironmentEntity(this.environmentId, this.name, this.rules);
}
