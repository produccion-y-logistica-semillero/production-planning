import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_dao.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/machine_type_dao.dart';
import 'package:production_planning/features/0_machines/data/dao_interfaces/status_dao.dart';
import 'package:production_planning/features/0_machines/data/models/machine_type_model.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_entity.dart';
import 'package:production_planning/features/0_machines/domain/entities/machine_type_entity.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';

class MachineRepositoryImpl implements MachineRepository {
  final MachineTypeDao machineTypeDao;
  final MachineDao machineDao;
  final StatusDao statusDao;

  MachineRepositoryImpl({required this.machineTypeDao, required this.machineDao, required this.statusDao});

  @override
  Future<Either<Failure, List<MachineTypeEntity>>> getAllMachineTypes() async {
    try {
      return Right((await machineTypeDao.getAllMachines())
          .map((model) => model.toEntity())
          .toList());
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  //need to check if it's good to get only the ID or if it could be better to get the entire entry
  @override
  Future<Either<Failure, int>> insertMachineType(
      MachineTypeEntity machine) async {
    try {
      int id = await machineTypeDao
          .insertMachine(MachineTypeModel.fromEntity(machine));
      return Right(id);
    } on Failure catch (failure) {
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, bool>> deleteMachineType(int id) async{
    try{
      await machineDao.deleteWhere(machineTypeDao.getTablePK(), id);  //we delete first all the machines associated with that machine type
      bool res = await machineTypeDao.deleteMachine(id);
      return Right (res);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

  @override
  Future<Either<Failure, List<MachineEntity>>> getAllMachinesFromType(int machineTypeId) async {
    try{
      final machines =  (await machineDao.getMachinesByType(machineTypeId)).map((map)async => await jsonToEntity(map)).toList();
      List<MachineEntity> machinesReady = [];
      for(final mach in machines){
        final future = await mach;
        machinesReady.add(future);
      }
      return Right(machinesReady);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

  //Machines Specific Implementations

  Future<Either<Failure, bool>> deleteMachine(int id) async{
    try{
      bool res = await machineDao.delete(id);
      return Right(res);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }
  
  @override
  Future<Either<Failure, int>> insertMachine(MachineEntity machine) async{
     try{
      int id = await machineDao.insertMachine(machineEntityToJson(machine));
      return Right(id);
    }
    on Failure catch(failure){
      return Left(failure);
    }
  }

   Map<String, dynamic> machineEntityToJson(MachineEntity entity){
    return {
      if(entity.id != null) 
      "machine_id"        : entity.id,
      "machine_type_id"   : entity.machineTypeId,
      "status_id"         : statusDao.getIdByName(entity.status),
      "processing_time"   : entity.processingTime,
      "preparation_time"  : entity.preparationTime,
      "rest_time"         : entity.restTime,
      "continue_capacity" : entity.continueCapacity
    };
  }

  Future<MachineEntity> jsonToEntity(Map<String, dynamic> map) async {
    return MachineEntity(
      id: map["machine_id"],
      status: await statusDao.getNameById(map["status_id"]), 
      processingTime: Duration(
        hours: int.parse(map["processing_time"].toString().substring(11, 13)), 
        minutes: int.parse(map["processing_time"].toString().substring(14, 16))
      ), 
      preparationTime: map["preparation_time"] != null ? Duration(
        hours: int.parse(map["preparation_time"].toString().substring(11, 13)), 
        minutes: int.parse(map["preparation_time"].toString().substring(14, 16))
      ) : null, 
      restTime: map["rest_time"] != null ? Duration(
        hours: int.parse(map["rest_time"].toString().substring(11, 13)), 
        minutes: int.parse(map["rest_time"].toString().substring(14, 16))
      ) : null, 
      continueCapacity: map["continue_capacity"]
    );
  }

}