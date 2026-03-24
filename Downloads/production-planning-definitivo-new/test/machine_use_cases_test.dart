import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';

import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_type_use_case.dart';


class MockMachineRepository extends Mock implements MachineRepository{}

void main(){
  test('get machine type use case', () async{
    //setup 
    final mockRepository = MockMachineRepository();
    final useCase = GetMachineTypesUseCase(repository: mockRepository);

    final machineList = [
      MachineTypeEntity(id: 1, name: 'maquina1', description: 'es la maquina1'),
      MachineTypeEntity(id: 2, name: 'maquina2', description: 'es la maquina2'),
    ];

    //simulating repository response

    when(()=>mockRepository.getAllMachineTypes()).thenAnswer((_)async => Right(machineList));

    //do
    final result = await useCase();

    //assert
    expect(result, equals(Right(machineList)));
    verify(() => mockRepository.getAllMachineTypes()).called(1);  //make sure that it was called exactly once

  });
}

