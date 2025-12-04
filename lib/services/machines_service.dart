import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/entities/machine_standard_times.dart';
import 'package:production_planning/entities/machine_type_entity.dart';
import 'package:production_planning/repositories/interfaces/machine_repository.dart';

class MachinesService {
  final MachineRepository repository;
  final Map<int, MachineStandardTimes> _standardTimesCache = {};
  final Map<int, MachineStandardTimes> _machineOverrides = {};

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
      return machines.map(_applyOverrides).toList();
    });
  }

  MachineStandardTimes getStandardTimesForType(int machineTypeId) {
    return _standardTimesCache[machineTypeId] ?? MachineStandardTimes.defaults();
  }

  Future<void> updateStandardTimesForType(
    int machineTypeId,
    MachineStandardTimes times,
  ) async {
    _standardTimesCache[machineTypeId] = times;
    await repository.updateMachineTimesByType(machineTypeId, times);
  }

  Future<Either<Failure, bool>> updateMachineTimes({
    required int machineId,
    required MachineStandardTimes times,
    int? machineTypeId,
  }) async {
    _machineOverrides[machineId] = times;

    if (machineTypeId != null && _standardTimesCache.containsKey(machineTypeId)) {
      final cached = _standardTimesCache[machineTypeId]!;
      _standardTimesCache[machineTypeId] = cached.copyWith(
        processing: times.processing,
        preparation: times.preparation ?? cached.preparation,
        rest: times.rest ?? cached.rest,
      );
    }

    return repository.updateMachineTimes(machineId, times);
  }

  MachineEntity _applyOverrides(MachineEntity machine) {
    final override =
        machine.id != null ? _machineOverrides[machine.id!] : null;
    if (override == null) return machine;

    return MachineEntity(
      id: machine.id,
      machineTypeId: machine.machineTypeId,
      status: machine.status,
      name: machine.name,
      processingTime: override.processing,
      preparationTime: override.preparation ?? machine.preparationTime,
      restTime: override.rest ?? machine.restTime,
      continueCapacity: machine.continueCapacity,
      availabilityDateTime: machine.availabilityDateTime,
      scheduledInactivities: machine.scheduledInactivities,
    );
  }

  Future<Either<Failure, bool>> updateAutomaticInactivity({
    required int machineId,
    required int continueCapacity,
    Duration? restTime,
  }) {
    return repository.updateAutomaticInactivity(
      machineId: machineId,
      continueCapacity: continueCapacity,
      restTime: restTime,
    );
  }

  Future<Either<Failure, List<MachineInactivityEntity>>> getMachineInactivities(int machineId) {
    return repository.getMachineInactivities(machineId);
  }

  Future<Either<Failure, MachineInactivityEntity>> addMachineInactivity(MachineInactivityEntity inactivity) {
    return repository.insertMachineInactivity(inactivity);
  }

  Future<Either<Failure, MachineInactivityEntity>> updateMachineInactivity(MachineInactivityEntity inactivity) {
    return repository.updateMachineInactivity(inactivity);
  }

  Future<Either<Failure, bool>> deleteMachineInactivity(int inactivityId) {
    return repository.deleteMachineInactivity(inactivityId);
  }
}
