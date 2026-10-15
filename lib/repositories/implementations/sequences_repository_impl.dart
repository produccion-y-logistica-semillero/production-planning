import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/implementations/sequences_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/task_dependency_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/tasks_dao_sqllite.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/repositories/models/task_dependency_model.dart';
import 'package:sqflite/sqflite.dart';
import 'package:production_planning/daos/interfaces/machine_type_dao.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/daos/interfaces/task_dependency_dao.dart';
import 'package:production_planning/daos/interfaces/tasks_dao.dart';
import 'package:production_planning/entities/task_dependency_entity.dart';
import 'package:production_planning/repositories/models/sequence_model.dart';
import 'package:production_planning/repositories/models/task_model.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/repositories/interfaces/sequences_repository.dart';


class SequencesRepositoryImpl implements SequencesRepository{

  final SequencesDao sequencesDao;
  final TasksDao tasksDao;
  final MachineTypeDao machineTypeDao;
  final TaskDependencyDao taskDependencyDao;

  SequencesRepositoryImpl(
      {required this.sequencesDao,
      required this.tasksDao,
      required this.machineTypeDao,
      required this.taskDependencyDao});

  @override
  Future<Either<Failure, bool>> createSequence(SequenceEntity sequence) async {
    try {
      int sequenceId =
          await sequencesDao.createSequence(SequenceModel.fromEntity(sequence));
      for (TaskEntity task in sequence.tasks!) {

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
        (model) => SequenceEntity(model.sequenceId, null, model.name, null)
      ).toList();
      return Right(list);
    }
    on LocalStorageFailure catch(f){
      return Left(f);
    }
  }
  
@override
Future<Either<Failure, SequenceEntity?>> getFullSequence(int id) async {
  try {
    final SequenceEntity? seq = (await sequencesDao.getSequenceById(id))?.toEntity();
    if (seq != null) {
      seq.tasks = (await tasksDao.getTasksBySequenceId(id)).map((model) => model.toEntity()).toList();

      // Cargar nombres de máquina
      for (TaskEntity t in seq.tasks!) {
        t.machineName = await machineTypeDao.getMachineName(t.machineTypeId);
      }

      // Cargar dependencias y asignarlas
      final dependencies = await taskDependencyDao.getDependenciesBySequenceId(id);
      seq.dependencies = dependencies.map((model) => model.toEntity()).toList();

      return Right(seq);
    }
    return const Right(null);
  } on LocalStorageFailure catch (f) {
    return Left(f);
  }
}
  
  /// Deletes the route with its arrows and tasks, in one transaction when
  /// the DAOs are the sqflite ones.
  ///
  /// It used to delete the route only `if` some task was deleted, so a route
  /// without stations could never be deleted, and it left every arrow of
  /// the route behind.
  @override
  Future<Either<Failure, bool>> deleteSequence(int id) async {
    try {
      final bool deleted = await _inTransaction((e) async {
        await _deleteDependenciesBySequence(id, e);
        await _deleteTasks(id, e);
        return _deleteSequenceRow(id, e);
      });
      return Right(deleted);
    } on LocalStorageFailure catch (f) {
      return Left(f);
    } catch (_) {
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, int>> countJobsUsing(int sequenceId) async {
    try {
      return Right(await sequencesDao.countJobsUsing(sequenceId));
    } on LocalStorageFailure catch (f) {
      return Left(f);
    }
  }

  @override
  Future<Either<Failure, int>> saveSequenceGraph(RouteDraft draft) async {
    try {
      final int id = await _inTransaction((e) => _saveGraph(draft, e));
      return Right(id);
    } on LocalStorageFailure catch (f) {
      return Left(f);
    } catch (_) {
      return Left(LocalStorageFailure());
    }
  }

  Future<int> _saveGraph(RouteDraft draft, DatabaseExecutor? e) async {
    final String name = draft.name.trim();
    int sequenceId;
    List<int> existingTaskIds = const [];
    if (draft.sequenceId == null) {
      sequenceId = await _createSequenceRow(name, e);
    } else {
      sequenceId = draft.sequenceId!;
      await _renameSequence(sequenceId, name, e);
      existingTaskIds = [
        // Through the transaction: a plain `db` call while it is open
        // would wait for it forever.
        for (final t in await _getTasks(sequenceId, e))
          if (t.taskId != null) t.taskId!,
      ];
    }

    final diff = diffRoute(existingTaskIds, draft);
    final Map<int, int> taskIdByKey = {};

    for (final n in diff.toUpdate) {
      await _updateTask(_taskModel(n, sequenceId, taskId: n.taskId), e);
      taskIdByKey[n.key] = n.taskId!;
    }
    for (final n in diff.toInsert) {
      taskIdByKey[n.key] = await _createTask(_taskModel(n, sequenceId), e);
    }
    for (final taskId in diff.toDelete) {
      await _deleteTaskById(taskId, e);
    }

    // Arrows have nothing pointing at them: replace them all.
    await _deleteDependenciesBySequence(sequenceId, e);
    for (final a in draft.arrows.toSet()) {
      final from = taskIdByKey[a.from];
      final to = taskIdByKey[a.to];
      if (from == null || to == null || from == to) continue;
      await _createDependency(
        TaskDependencyModel(
          predecessor_id: from,
          successor_id: to,
          sequenceId: sequenceId,
        ),
        e,
      );
    }
    return sequenceId;
  }

  TaskModel _taskModel(RouteNode n, int sequenceId, {int? taskId}) =>
      TaskModel(
        taskId: taskId,
        nProcUnits: n.processing,
        description: n.description,
        sequenceId: sequenceId,
        machineTypeId: n.machineTypeId,
        allowPreemption: n.allowPreemption,
      );

  // ── Transaction plumbing ──────────────────────────────────────────────────
  //
  // When every DAO is the concrete sqflite one (always, in the app) the work
  // runs in ONE transaction on their shared connection, so a failure halfway
  // leaves no partial route. Same pattern as OrderRepositoryImpl.updateOrder.

  Future<T> _inTransaction<T>(Future<T> Function(DatabaseExecutor? e) work) {
    final dao = sequencesDao;
    if (dao is SequencesDaoSqllite &&
        tasksDao is TasksDaoSqllite &&
        taskDependencyDao is TaskDependencyDaoSqllite) {
      return dao.db.transaction((txn) => work(txn));
    }
    return work(null);
  }

  Future<int> _createSequenceRow(String name, DatabaseExecutor? e) {
    final dao = sequencesDao;
    final model = SequenceModel(name: name);
    return dao is SequencesDaoSqllite
        ? dao.createSequence(model, executor: e)
        : dao.createSequence(model);
  }

  Future<void> _renameSequence(int id, String name, DatabaseExecutor? e) {
    final dao = sequencesDao;
    return dao is SequencesDaoSqllite
        ? dao.renameSequence(id, name, executor: e)
        : dao.renameSequence(id, name);
  }

  Future<bool> _deleteSequenceRow(int id, DatabaseExecutor? e) {
    final dao = sequencesDao;
    return dao is SequencesDaoSqllite
        ? dao.deleteSequence(id, executor: e)
        : dao.deleteSequence(id);
  }

  Future<List<TaskModel>> _getTasks(int sequenceId, DatabaseExecutor? e) {
    final dao = tasksDao;
    return dao is TasksDaoSqllite
        ? dao.getTasksBySequenceId(sequenceId, executor: e)
        : dao.getTasksBySequenceId(sequenceId);
  }

  Future<int> _createTask(TaskModel task, DatabaseExecutor? e) {
    final dao = tasksDao;
    return dao is TasksDaoSqllite
        ? dao.createTask(task, executor: e)
        : dao.createTask(task);
  }

  Future<void> _updateTask(TaskModel task, DatabaseExecutor? e) {
    final dao = tasksDao;
    return dao is TasksDaoSqllite
        ? dao.updateTask(task, executor: e)
        : dao.updateTask(task);
  }

  Future<void> _deleteTaskById(int taskId, DatabaseExecutor? e) {
    final dao = tasksDao;
    return dao is TasksDaoSqllite
        ? dao.deleteTaskById(taskId, executor: e)
        : dao.deleteTaskById(taskId);
  }

  Future<bool> _deleteTasks(int sequenceId, DatabaseExecutor? e) {
    final dao = tasksDao;
    return dao is TasksDaoSqllite
        ? dao.deleteTasks(sequenceId, executor: e)
        : dao.deleteTasks(sequenceId);
  }

  Future<int> _createDependency(TaskDependencyModel dep, DatabaseExecutor? e) {
    final dao = taskDependencyDao;
    return dao is TaskDependencyDaoSqllite
        ? dao.createTaskDependency(dep, executor: e)
        : dao.createTaskDependency(dep);
  }

  Future<void> _deleteDependenciesBySequence(
      int sequenceId, DatabaseExecutor? e) {
    final dao = taskDependencyDao;
    return dao is TaskDependencyDaoSqllite
        ? dao.deleteDependenciesBySequence(sequenceId, executor: e)
        : dao.deleteDependenciesBySequence(sequenceId);
  }

  @override
  Future<int> createSequenceAndReturnId(SequenceEntity sequence) async {
    final sequenceId = await sequencesDao.createSequence(SequenceModel.fromEntity(sequence));
    return sequenceId;
  }
@override
  Future<void> createTaskForSequence(TaskEntity task, int sequenceId) async {
  await tasksDao.createTask(TaskModel.fromEntity(task, sequenceId));
}
  @override
  Future<int> createTaskForSequenceAndReturnId(TaskEntity taskEntity, int sequenceId) async {
    final taskModel = TaskModel.fromEntity(taskEntity, sequenceId);
    final taskId = await tasksDao.createTask(taskModel);
    print('Task created: ${taskEntity.description}, machineTypeId: ${taskEntity.machineTypeId}, taskId: $taskId, sequenceId: $sequenceId');

    return taskId;
  }

  @override
  Future<void> createTaskDependencyForSequence(TaskDependencyEntity dep) async {
    await taskDependencyDao.createTaskDependency(dep.toModel());
    print('Task dependency created: ${dep.predecessor_id} -> ${dep.successor_id} for sequence ID: ${dep.sequenceId}');
  }

}

