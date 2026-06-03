import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/job_dao.dart';
import 'package:production_planning/entities/job_interruption_policy.dart';
import 'package:production_planning/repositories/models/job_model.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:sqflite/sqflite.dart';

class JobDaoSQLlite implements JobDao {
  final Database db;

  JobDaoSQLlite(this.db);

  @override
  Future<List<JobModel>> getJobsByOrderId(int orderId) async {
    final List<Map<String, dynamic>> maps = await db.query(
      'jobs',
      where: 'order_id = ?',
      whereArgs: [orderId],
    );


    // Cargar preemption matrix para cada job
    List<JobModel> jobs = [];
    for (var map in maps) {
      final jobId = map['job_id'] as int;

      // Obtener matriz de pre-emption para este job
      final preemptionMaps = await db.query(
        'job_preemption',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );

      // Convertir a Map<int, int>
      Map<int, int>? preemptionMatrix;
      if (preemptionMaps.isNotEmpty) {
        preemptionMatrix = {};
        for (var pm in preemptionMaps) {
          preemptionMatrix[pm['machine_id'] as int] = pm['can_preempt'] as int;
        }
      }

      // Obtener tiempos por tarea/máquina si existen
      final timesMaps = await db.query(
        'job_task_machine_times',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );

      Map<int, Map<int, Map<String, int>>>? taskMachineTimes;
      if (timesMaps.isNotEmpty) {
        taskMachineTimes = {};
        for (var tm in timesMaps) {
          final tId = tm['task_id'] as int;
          final mId = tm['machine_id'] as int;
          final processingMinutes = tm['processing_minutes'] as int;
          final preparationMinutes = tm['preparation_minutes'] as int;
          final restMinutes = tm['rest_minutes'] as int;
          print(
              'JobDao: loaded time for job $jobId task $tId machine $mId = $processingMinutes/$preparationMinutes/$restMinutes minutes');
          taskMachineTimes.putIfAbsent(tId, () => {})[mId] = {
            'processing': processingMinutes,
            'preparation': preparationMinutes,
            'rest': restMinutes,
          };
        }
      }

      // Obtener estados finales por máquina
      final statesMaps = await db.query(
        'job_machine_states',
        where: 'job_id = ?',
        whereArgs: [jobId],
      );

      Map<int, String>? machineFinalStates;
      if (statesMaps.isNotEmpty) {
        machineFinalStates = {};
        for (var sm in statesMaps) {
          machineFinalStates[sm['machine_type_id'] as int] = sm['state_char'] as String;
        }
      }

      JobInterruptionPolicy? interruptionPolicy;
      final policyMaps = await db.query(
        'job_interruption_policy',
        where: 'job_id = ?',
        whereArgs: [jobId],
        limit: 1,
      );
      if (policyMaps.isNotEmpty) {
        interruptionPolicy =
            JobInterruptionPolicy.fromDatabaseMap(policyMaps.first);
      }

      jobs.add(JobModel(
        jobId,
        map['sequence_id'] as int,
        map['amount'] as int,
        map['job_name'] as String?,
        DateTime.parse(map['due_date'] as String),
        map['priority'] as int,
        DateTime.parse(map['available_date'] as String),
        preemptionMatrix: preemptionMatrix,
        interruptionPolicy: interruptionPolicy,
        taskMachineTimesMinutes: taskMachineTimes,
        machineFinalStates: machineFinalStates,
      ));
    }

    return jobs;
  }

  @override
  Future<void> insertJob(JobEntity job, int orderId) async {
    try {
      await db.transaction((txn) async {
        // map job data for data base
        final jobMap = {
          'sequence_id': job.sequence!.id,
          'order_id': orderId,
          'amount': job.amount,
          'job_name': job.jobName,
          'due_date': job.dueDate.toIso8601String(), // due date
          'priority': job.priority,
          'available_date': job.availableDate.toIso8601String(),
        };

        // insert job to data base
        final jobId = await txn.insert('jobs', jobMap);

        // Insertar preemption matrix si existe
        if (job.preemptionMatrix != null && job.preemptionMatrix!.isNotEmpty) {
          for (var entry in job.preemptionMatrix!.entries) {
            await txn.insert('job_preemption', {
              'job_id': jobId,
              'machine_id': entry.key,
              'can_preempt': entry.value,
            });
          }
        }

        if (job.interruptionPolicy != null) {
          await txn.insert(
            'job_interruption_policy',
            job.interruptionPolicy!.toDatabaseMap(jobId),
          );
        }
        // Insertar tiempos por tarea/máquina si existen
        if (job.taskMachineTimes != null && job.taskMachineTimes!.isNotEmpty) {
          for (final entry in job.taskMachineTimes!.entries) {
            final taskId = entry.key;
            final inner = entry.value;
            for (final e in inner.entries) {
              final processingMinutes = e.value.processing.inMinutes;
              final preparationMinutes = e.value.preparation.inMinutes;
              final restMinutes = e.value.rest.inMinutes;
              print(
                  'JobDao: inserting time for job $jobId task $taskId machine ${e.key} = $processingMinutes/$preparationMinutes/$restMinutes minutes');
              await txn.insert('job_task_machine_times', {
                'job_id': jobId,
                'task_id': taskId,
                'machine_id': e.key,
                'processing_minutes': processingMinutes,
                'preparation_minutes': preparationMinutes,
                'rest_minutes': restMinutes,
              });
            }
          }
        }
        
        // Insertar estados finales por máquina si existen
        if (job.machineFinalStates != null && job.machineFinalStates!.isNotEmpty) {
          for (var entry in job.machineFinalStates!.entries) {
            await txn.insert('job_machine_states', {
              'job_id': jobId,
              'machine_type_id': entry.key,
              'state_char': entry.value,
            });
          }
        }
      });
    } catch (error) {
      print("ERROR AL INSERTAR JOB EN DAO: ${error.toString()}");
      throw LocalStorageFailure();
    }
  }


  @override
  Future<void> deleteJobsFromOrder(int orderId) async {
    try {
      // Obtener job_ids antes de eliminar
      final jobs = await db.query(
        'jobs',
        columns: ['job_id'],
        where: 'order_id = ?',
        whereArgs: [orderId],
      );

      // Eliminar registros de job_preemption para cada job
      for (var job in jobs) {
        await db.delete(
          'job_preemption',
          where: 'job_id = ?',
          whereArgs: [job['job_id']],
        );
        await db.delete(
          'job_interruption_policy',
          where: 'job_id = ?',
          whereArgs: [job['job_id']],
        );
      }

      // Eliminar registros de job_machine_states para cada job
      for (var job in jobs) {
        await db.delete(
          'job_machine_states',
          where: 'job_id = ?',
          whereArgs: [job['job_id']],
        );
      }

      // Eliminar jobs
      await db.delete(
        'jobs',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
    } catch (error) {
      throw LocalStorageFailure();
    }
  }
}
