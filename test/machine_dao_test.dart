
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:production_planning/daos/implementations/machine_type_dao_sqllite.dart';
import 'package:production_planning/daos/interfaces/machine_type_dao.dart';
import 'package:production_planning/repositories/models/machine_type_model.dart';
import 'package:sqflite/sqflite.dart';


class MockDatabase extends Mock implements Database{}


void main() async {

   test('machine data retrieval',() async {
      //setup
      final mockDatabase = MockDatabase();
      final MachineTypeDao dao = MachineTypeDaoSQLlite(mockDatabase);
      final expected = [
        MachineTypeModel(id: 1, name: 'maquina1', description: 'es la maquina 1')
      ];
    
      //simulate database returning
      when(()=> mockDatabase.query('MACHINE_TYPES'))
      .thenAnswer((_)async => [
        {'machine_type_id':1, 'name': 'maquina1', 'description':'es la maquina 1'}
      ]);

      //do
      final result = await dao.getAllMachines();

      //assert
      expect(result[0].name, equals(expected[0].name));
      expect(result[0].id, equals(expected[0].id));
    }
  );
   test('simple insert test', () async {
    //setup
    final mockDatabase = MockDatabase();
    final MachineTypeDao dao = MachineTypeDaoSQLlite(mockDatabase);
    final machineTypeModel = MachineTypeModel(id: null, name: 'maquina1', description: 'es la maquina 1');

    const expected = 1;

    // Mock the insert method to return a Future<int>
    when(() => mockDatabase.insert('MACHINE_TYPES', {
      'name': 'maquina1',
      'description': 'es la maquina 1',
    })).thenAnswer((_) async => 1);

     //do
    final result = await dao.insertMachine(machineTypeModel);

    // Assert the expected result
    expect(result, equals(expected));
  });
}