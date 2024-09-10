import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:production_planning/features/machines/data/dao_implementations/status_dao_sqllite.dart';
import 'package:production_planning/features/machines/data/dao_interfaces/status_dao.dart';
import 'package:sqflite/sqflite.dart';

class MockDatabase extends Mock implements Database{}

void main(){
  test("interaction with status table", () async{
    // setup
    final mockDatabase = MockDatabase();
    StatusDao dao = StatusDaoSqllite(mockDatabase);
    final expected = 'Estado_1';

    // simulate db
    when(()=> mockDatabase.query('STATUS'))
    .thenAnswer((_)async=> [
      {'id' : 1, 'name' : 'Estado_1'},
      {'id' : 2, 'name' : 'Estado_2'}
    ]);

    // do
    final result = await dao.getStateNameById(1);

    // assert
    expect(result, expected);
  });
}