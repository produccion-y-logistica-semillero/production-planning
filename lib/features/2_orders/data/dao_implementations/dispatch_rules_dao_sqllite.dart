import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/2_orders/data/dao_interfaces/dispatch_rules_dao.dart';
import 'package:sqflite/sqflite.dart';

class DispatchRulesDaoSqllite implements DispatchRulesDao{
  final Database db;

  DispatchRulesDaoSqllite(this.db);

  @override
  Future<List<Tuple2<int, String>>> getDispatchRules(int enviromentId) async{
    try{
      return (await db.rawQuery(
        'SELECT dr.dispatch_rule_id as id, dr.name as name FROM dispatch_rules dr INNER JOIN types_x_rules tr ON tr.dispatch_rule_id = dr.dispatch_rule_id WHERE tr.environment_id = ?', [enviromentId]
      )).map((json)=> Tuple2<int, String>(int.parse(json['id'].toString()), json['name'].toString())).toList();
    }catch(error){
      throw LocalStorageFailure();
    }
  }
}