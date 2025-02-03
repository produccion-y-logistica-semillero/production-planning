import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/machine_type_dao.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/daos/interfaces/tasks_dao.dart';
import 'package:production_planning/repositories/models/sequence_model.dart';
import 'package:production_planning/repositories/models/task_model.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/repositories/interfaces/sequences_repository.dart';

class SequencesRepositoryImpl implements SequencesRepository{
  final SequencesDao sequencesDao;
  final TasksDao tasksDao;
  final MachineTypeDao machineTypeDao;

  SequencesRepositoryImpl({required this.sequencesDao, required this.tasksDao, required this.machineTypeDao});

  @override
  Future<Either<Failure, bool>> createSequence(SequenceEntity sequence) async {
    try{
      int sequenceId = await sequencesDao.createSequence(SequenceModel.fromEntity(sequence));
      for(TaskEntity task in sequence.tasks!){
        await tasksDao.createTask(TaskModel.fromEntity(task, sequenceId));
      }
      //final response = await getBasicSequences();
      return const Right(true);
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

        for(TaskEntity t in seq.tasks!){
          t.machineName = await machineTypeDao.getMachineName(t.machineTypeId);
        }
        return Right(seq);
      }
      return const Right(null);
    }
    on LocalStorageFailure catch(f){
      return Left(f);
    }
  }
  
  @override
  Future<Either<Failure, bool>> deleteSequence(int id) async {
    try{
      bool deleted = await tasksDao.deleteTasks(id);
      if(deleted){
        deleted = await sequencesDao.deleteSequence(id);
        return Right(deleted);
      }
      return const Right(false);
    }
    on LocalStorageFailure catch(f){
      return Left(f);
    }
  }
}