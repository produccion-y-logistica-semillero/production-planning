import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/sequences/data/dao_interfaces/sequences_dao.dart';
import 'package:production_planning/features/sequences/data/dao_interfaces/tasks_dao.dart';
import 'package:production_planning/features/sequences/data/models/sequence_model.dart';
import 'package:production_planning/features/sequences/data/models/task_model.dart';
import 'package:production_planning/features/sequences/domain/entities/job_entity.dart';
import 'package:production_planning/features/sequences/domain/entities/task_entity.dart';
import 'package:production_planning/features/sequences/domain/repositories/sequences_repository.dart';

class SequencesRepositoryImpl implements SequencesRepository{
  final SequencesDao sequencesDao;
  final TasksDao tasksDao;

  SequencesRepositoryImpl({required this.sequencesDao, required this.tasksDao});

  @override
  Future<Either<Failure, bool>> createSequence(JobEntity job) async {
    try{
      int sequenceId = await sequencesDao.createSequence(SequenceModel.fromEntity(job));
      for(TaskEntity task in job.tasks){
        await tasksDao.createTask(TaskModel.fromEntity(task, sequenceId));
      }
      return Right(true);
    }
    on LocalStorageFailure catch(f){
      return Left(f);
    }
  }
}