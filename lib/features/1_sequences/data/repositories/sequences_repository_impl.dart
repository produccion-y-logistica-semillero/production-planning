import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/sequences_dao.dart';
import 'package:production_planning/features/1_sequences/data/dao_interfaces/tasks_dao.dart';
import 'package:production_planning/features/1_sequences/data/models/sequence_model.dart';
import 'package:production_planning/features/1_sequences/data/models/task_model.dart';
import 'package:production_planning/features/1_sequences/domain/entities/sequence_entity.dart';
import 'package:production_planning/features/1_sequences/domain/entities/task_entity.dart';
import 'package:production_planning/features/1_sequences/domain/repositories/sequences_repository.dart';

class SequencesRepositoryImpl implements SequencesRepository{
  final SequencesDao sequencesDao;
  final TasksDao tasksDao;

  SequencesRepositoryImpl({required this.sequencesDao, required this.tasksDao});

  @override
  Future<Either<Failure, bool>> createSequence(SequenceEntity sequence) async {
    try{
      int sequenceId = await sequencesDao.createSequence(SequenceModel.fromEntity(sequence));
      for(TaskEntity task in sequence.tasks!){
        await tasksDao.createTask(TaskModel.fromEntity(task, sequenceId));
      }
      return Right(true);
    }
    on LocalStorageFailure catch(f){
      return Left(f);
    }
  }

  @override
  Future<Either<Failure, List<SequenceEntity>>> getBasicSequences() async{
    try{
      final list = (await sequencesDao.getSequences()).map(
        (model) => SequenceEntity(model.sequenceId, null, model.name)
      ).toList();
      return Right(list);
    }
    on LocalStorageFailure catch(f){
      return Left(f);
    }
  }
  
  @override
  Future<Either<Failure, SequenceEntity?>> getFullSequence(int id) async {
    try{
      final SequenceEntity?  seq = (await sequencesDao.getSequenceById(id))?.toEntity();
      if(seq != null){
        seq.tasks = (await tasksDao.getTasksBySequenceId(id)).map((model) => model.toEntity()).toList();
        return Right(seq);
      }
      return const Right(null);
    }
    on LocalStorageFailure catch(f){
      return Left(f);
    }
  }
}