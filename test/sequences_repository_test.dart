// Saving process routes against a real (in-memory) SQLite database:
// editing a route keeps the task ids of the stations that stay — so the
// per-job times saved programs hold for them survive — and removing a
// station, or a whole route, leaves nothing orphaned.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/daos/implementations/machine_type_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/sequences_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/task_dependency_dao_sqllite.dart';
import 'package:production_planning/daos/implementations/tasks_dao_sqllite.dart';
import 'package:production_planning/entities/route_draft.dart';
import 'package:production_planning/repositories/implementations/sequences_repository_impl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openSchema() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false));
  await db.execute('''CREATE TABLE MACHINE_TYPES(
      machine_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, description TEXT)''');
  await db.execute('''CREATE TABLE sequences (
      sequence_id INTEGER PRIMARY KEY AUTOINCREMENT,
      name VARCHAR(100) NOT NULL)''');
  await db.execute('''CREATE TABLE tasks (
      task_id INTEGER PRIMARY KEY AUTOINCREMENT,
      n_proc_units TIMESTAMP NOT NULL, description VARCHAR(100),
      sequence_id INTEGER NOT NULL, machine_type_id INTEGER NOT NULL,
      allow_preemption INTEGER NOT NULL DEFAULT 0)''');
  await db.execute('''CREATE TABLE TaskDependency (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      predecessor_id INTEGER NOT NULL, successor_id INTEGER NOT NULL,
      sequence_id INTEGER NOT NULL,
      CONSTRAINT unique_dependency UNIQUE (predecessor_id, successor_id),
      CONSTRAINT no_self_dependency CHECK (predecessor_id <> successor_id))''');
  await db.execute('''CREATE TABLE jobs (
      job_id INTEGER PRIMARY KEY AUTOINCREMENT,
      sequence_id INTEGER NOT NULL)''');
  await db.execute('''CREATE TABLE job_task_machine_times (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id INTEGER NOT NULL, task_id INTEGER NOT NULL,
      machine_id INTEGER NOT NULL, processing_minutes INTEGER NOT NULL)''');
  for (final name in ['Mezcladora', 'Horno', 'Empaque']) {
    await db.insert('MACHINE_TYPES', {'name': name, 'description': ''});
  }
  return db;
}

SequencesRepositoryImpl repositoryOn(Database db) => SequencesRepositoryImpl(
      sequencesDao: SequencesDaoSqllite(db),
      tasksDao: TasksDaoSqllite(db),
      machineTypeDao: MachineTypeDaoSQLlite(db),
      taskDependencyDao: TaskDependencyDaoSqllite(db),
    );

RouteNode station(int key, int machineTypeId,
        {int? taskId, Duration time = const Duration(hours: 1)}) =>
    RouteNode(
      key: key,
      taskId: taskId,
      machineTypeId: machineTypeId,
      machineName: 'M$machineTypeId',
      processing: time,
    );

void main() {
  late Database db;
  late SequencesRepositoryImpl repo;

  setUp(() async {
    db = await openSchema();
    repo = repositoryOn(db);
  });

  tearDown(() => db.close());

  Future<int> create() async {
    final result = await repo.saveSequenceGraph(RouteDraft(
      name: 'Pan',
      nodes: [station(-1, 1), station(-2, 2)],
      arrows: const [RouteArrow(-1, -2)],
    ));
    return result.getOrElse(() => fail('create failed'));
  }

  test('creating saves tasks, times and arrows', () async {
    final id = await create();
    final route = (await repo.getFullSequence(id)).getOrElse(() => null)!;

    expect(route.name, 'Pan');
    expect(route.tasks!.map((t) => t.machineName), ['Mezcladora', 'Horno']);
    expect(route.dependencies, hasLength(1));
  });

  test('editing adds a station and keeps the ids of the others', () async {
    final id = await create();
    final before = RouteDraft.fromSequence(
        (await repo.getFullSequence(id)).getOrElse(() => null)!);
    final mixId = before.nodes[0].taskId!;
    final ovenId = before.nodes[1].taskId!;
    // A saved program has a time for the oven task.
    await db.insert('jobs', {'sequence_id': id});
    await db.insert('job_task_machine_times',
        {'job_id': 1, 'task_id': ovenId, 'machine_id': 5, 'processing_minutes': 45});

    final edited = RouteDraft(
      sequenceId: id,
      name: 'Pan integral',
      nodes: [
        before.nodes[0]..processing = const Duration(minutes: 30),
        before.nodes[1],
        station(-1, 3),
      ],
      arrows: [
        RouteArrow(mixId, ovenId),
        RouteArrow(ovenId, -1),
      ],
    );
    expect((await repo.saveSequenceGraph(edited)).isRight(), isTrue);

    final after = (await repo.getFullSequence(id)).getOrElse(() => null)!;
    expect(after.name, 'Pan integral');
    expect(after.tasks!.map((t) => t.id).take(2), [mixId, ovenId]);
    expect(after.tasks!.first.processingUnits, const Duration(minutes: 30));
    expect(after.tasks, hasLength(3));
    expect(after.dependencies, hasLength(2));
    // The program's time for the oven survives.
    expect(await db.query('job_task_machine_times'), hasLength(1));
    expect((await repo.countJobsUsing(id)).getOrElse(() => -1), 1);
  });

  test('removing a station deletes its arrows and per-job times', () async {
    final id = await create();
    final before = RouteDraft.fromSequence(
        (await repo.getFullSequence(id)).getOrElse(() => null)!);
    final ovenId = before.nodes[1].taskId!;
    await db.insert('job_task_machine_times',
        {'job_id': 1, 'task_id': ovenId, 'machine_id': 5, 'processing_minutes': 45});

    await repo.saveSequenceGraph(RouteDraft(
      sequenceId: id,
      name: 'Pan',
      nodes: [before.nodes[0]],
    ));

    expect(await db.query('tasks'), hasLength(1));
    expect(await db.query('TaskDependency'), isEmpty);
    expect(await db.query('job_task_machine_times'), isEmpty);
  });

  test('a route with no stations can be deleted, arrows and all', () async {
    final empty = (await repo.saveSequenceGraph(const RouteDraft(name: 'Vacía')))
        .getOrElse(() => fail('create failed'));
    expect((await repo.deleteSequence(empty)).getOrElse(() => false), isTrue);

    final id = await create();
    expect((await repo.deleteSequence(id)).getOrElse(() => false), isTrue);
    expect(await db.query('sequences'), isEmpty);
    expect(await db.query('tasks'), isEmpty);
    expect(await db.query('TaskDependency'), isEmpty);
  });

  test('a failure halfway leaves nothing behind', () async {
    // The arrows are written last; with their table gone that step fails
    // after the route and its tasks were already inserted.
    await db.execute('DROP TABLE TaskDependency');

    final result = await repo.saveSequenceGraph(RouteDraft(
      name: 'Rota',
      nodes: [station(-1, 1), station(-2, 2)],
      arrows: const [RouteArrow(-1, -2)],
    ));

    expect(result.isLeft(), isTrue);
    expect(await db.query('sequences'), isEmpty);
    expect(await db.query('tasks'), isEmpty);
  });
}
