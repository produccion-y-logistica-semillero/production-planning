import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/core/use_cases/use_case.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/1_sequences/domain/entities/task_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/job_entity.dart';
import 'package:production_planning/features/2_orders/domain/entities/order_entity.dart';

class GetOrdersUseCase implements UseCase<List<OrderEntity>, void>{


  //ATTENTION ATTENTION
  //This code returns static data of orders, By now is done this way so that we can test frontend, but this is only for testing frontend
  @override
  Future<Either<Failure, List<OrderEntity>>> call({required void p}) async {

    List<OrderEntity> orders = [];
    orders.add(
      OrderEntity(1, DateTime(2024, 1, 1), 
        [
          JobEntity(1, 
            SequenceEntity(1, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 1, minute: 30), description: "AMASARPAN", machineTypeId: 2, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 30), description: "HORNEAR PAN", machineTypeId: 4, machineName: "aaa"),
              TaskEntity(execOrder: 3, processingUnits: TimeOfDay(hour: 1, minute: 30), description: "CALENTAR PAN", machineTypeId: 5, machineName: "aaa"),
            ], 
            "PAN"), 
          2, DateTime(2024, 12, 30), 2),
          JobEntity(2, 
            SequenceEntity(4, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 1, minute: 20), description: "Pintar", machineTypeId: 6, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 10), description: "Cortar", machineTypeId: 3, machineName: "aaa"),
            ], 
            "PAN"), 
          5, DateTime(2025, 5, 5), 3),
        ]
      ),
    );

    // Add 5 more orders with static data

    orders.add(
      OrderEntity(2, DateTime(2024, 2, 2), 
        [
          JobEntity(3, 
            SequenceEntity(2, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 2, minute: 0), description: "PREPARAR PIZZA", machineTypeId: 1, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 0, minute: 45), description: "HORNEAR PIZZA", machineTypeId: 4, machineName: "aaa"),
            ], 
            "PIZZA"), 
          3, DateTime(2024, 12, 15), 1),
          JobEntity(4, 
            SequenceEntity(3, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 1, minute: 10), description: "CORTAR VERDURAS", machineTypeId: 2, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 0, minute: 30), description: "PREPARAR SALSA", machineTypeId: 3, machineName: "aaa"),
            ], 
            "ENSALADA"), 
          4, DateTime(2025, 6, 1), 2),
        ]
      ),
    );

    orders.add(
      OrderEntity(3, DateTime(2024, 3, 3), 
        [
          JobEntity(5, 
            SequenceEntity(5, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 1, minute: 20), description: "PREPARAR POSTRE", machineTypeId: 7, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 0, minute: 40), description: "DECORAR POSTRE", machineTypeId: 8, machineName: "aaa"),
            ], 
            "POSTRE"), 
          4, DateTime(2024, 11, 20), 3),
          JobEntity(6, 
            SequenceEntity(6, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 2, minute: 30), description: "COCINAR SOPA", machineTypeId: 1, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 45), description: "SERVIR SOPA", machineTypeId: 2, machineName: "aaa"),
            ], 
            "SOPA"), 
          2, DateTime(2025, 4, 10), 1),
        ]
      ),
    );

    orders.add(
      OrderEntity(4, DateTime(2024, 4, 4), 
        [
          JobEntity(7, 
            SequenceEntity(7, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 3, minute: 15), description: "PREPARAR PASTEL", machineTypeId: 5, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 2, minute: 0), description: "HORNEAR PASTEL", machineTypeId: 6, machineName: "aaa"),
            ], 
            "PASTEL"), 
          3, DateTime(2024, 10, 25), 2),
          JobEntity(8, 
            SequenceEntity(8, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 1, minute: 10), description: "HACER PASTA", machineTypeId: 3, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 20), description: "COCINAR PASTA", machineTypeId: 4, machineName: "aaa"),
            ], 
            "PASTA"), 
          4, DateTime(2025, 5, 25), 3),
        ]
      ),
    );

    orders.add(
      OrderEntity(5, DateTime(2024, 5, 5), 
        [
          JobEntity(9, 
            SequenceEntity(9, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 1, minute: 45), description: "COCINAR CARNE", machineTypeId: 7, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 0), description: "SERVIR CARNE", machineTypeId: 8, machineName: "aaa"),
            ], 
            "CARNE"), 
          3, DateTime(2024, 12, 10), 1),
          JobEntity(10, 
            SequenceEntity(10, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 2, minute: 15), description: "PREPARAR ENSALADA", machineTypeId: 2, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 30), description: "SERVIR ENSALADA", machineTypeId: 3, machineName: "aaa"),
            ], 
            "ENSALADA"), 
          4, DateTime(2025, 7, 10), 2),
        ]
      ),
    );

    orders.add(
      OrderEntity(6, DateTime(2024, 6, 6), 
        [
          JobEntity(11, 
            SequenceEntity(11, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 3, minute: 0), description: "COCINAR PESCADO", machineTypeId: 6, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 45), description: "SERVIR PESCADO", machineTypeId: 7, machineName: "aaa"),
            ], 
            "PESCADO"), 
          5, DateTime(2024, 9, 20), 3),
          JobEntity(12, 
            SequenceEntity(12, 
            [
              TaskEntity(execOrder: 1, processingUnits: TimeOfDay(hour: 1, minute: 30), description: "PREPARAR SOPA", machineTypeId: 4, machineName: "aaa"),
              TaskEntity(execOrder: 2, processingUnits: TimeOfDay(hour: 1, minute: 20), description: "SERVIR SOPA", machineTypeId: 5, machineName: "aaa"),
            ], 
            "SOPA"), 
          3, DateTime(2025, 3, 15), 2),
        ]
      ),
    );

    return Right(orders);
  }
  
  
}