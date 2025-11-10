import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_standard_times.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';

class MachinesService {
  final MachineRepository repository;
  final Map<int, MachineStandardTimes> _standardTimesCache = {};

  MachinesService(this.repository);


  Future<Either<Failure, MachineTypeEntity>> addMachineType(String name, String description) async{
    final machine = MachineTypeEntity(name: name, description: description);
    final response = await repository.insertMachineType(machine);
    return response.fold(
      (f) => Left(f),
      (id) {
        machine.id = id;
        return Right(machine);
      }
    ); 
  }

  Future<Either<Failure, MachineEntity>> addMachine(int machineTypeId, String name, String? status, Duration processingTime, Duration preparationTime, Duration restTime, int continueCapacity, DateTime availabilityDateTime) async{
    final machine = MachineEntity(
      machineTypeId: machineTypeId,
      name:    name,
      status          : status, 
      processingTime  : processingTime, 
      preparationTime : preparationTime, 
      restTime        : restTime, 
      continueCapacity: continueCapacity,
      availabilityDateTime: availabilityDateTime,  
    );
    print("Adding new machine: $machine");
    final response = await repository.insertMachine(machine);
    return response.fold(
      (f) => Left(f),
      (id) {
        machine.id = id;
        return Right(machine);
      }
    );
  }

  Future<Either<Failure, bool>> deleteMachine(int id) async {
    return repository.deleteMachine(id);
  }

  Future<Either<Failure, bool>> deleteMachineType(int id) async {
    return repository.deleteMachineType(id);
  }

  Future<Either<Failure,List<MachineTypeEntity>>> getMachineTypes() async {
    return repository.getAllMachineTypes();
  }


  Future<Either<Failure, List<MachineEntity>>> getMachines(int typeId) async {
    final response = await repository.getAllMachinesFromType(typeId);
    return response.map((machines) {
      if (machines.isNotEmpty) {
        final fallback = _standardTimesCache[typeId];
        final candidate = MachineStandardTimes.fromMachine(
          machines.first,
          fallback: fallback,
        );

        _standardTimesCache[typeId] = fallback == null
            ? candidate
            : fallback.copyWith(
                preparation: fallback.preparation ?? candidate.preparation,
                rest: fallback.rest ?? candidate.rest,
              );
      }
      return machines;
    });
  }

  MachineStandardTimes getStandardTimesForType(int machineTypeId) {
    return _standardTimesCache[machineTypeId] ?? MachineStandardTimes.defaults();
  }

  void updateStandardTimesForType(int machineTypeId, MachineStandardTimes times) {
    _standardTimesCache[machineTypeId] = times;
  }
}
