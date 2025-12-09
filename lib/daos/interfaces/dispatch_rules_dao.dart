import 'package:dartz/dartz.dart';

abstract class DispatchRulesDao{
  Future<List<Tuple2<int, String>>> getDispatchRules(int enviromentId);
}

