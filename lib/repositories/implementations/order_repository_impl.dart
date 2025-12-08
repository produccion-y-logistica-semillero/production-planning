import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/daos/interfaces/task_dependency_dao.dart';
import 'package:production_planning/daos/interfaces/tasks_dao.dart';
import 'package:production_planning/repositories/models/task_dependency_model.dart';
import 'package:production_planning/repositories/models/task_model.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/daos/interfaces/dispatch_rules_dao.dart';
import 'package:production_planning/daos/interfaces/enviroment_dao.dart';
import 'package:production_planning/daos/interfaces/order_dao.dart';
import 'package:production_planning/daos/interfaces/job_dao.dart';
import 'package:production_planning/repositories/models/enviroment_model.dart';
import 'package:production_planning/repositories/models/job_model.dart';
import 'package:production_planning/repositories/models/order_model.dart';
import 'package:production_planning/entities/environment_entity.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/machine_times.dart';
import 'package:production_planning/repositories/interfaces/order_repository.dart';

class OrderRepositoryImpl implements OrderRepository {
  final OrderDao orderDao;
  final JobDao jobDao;
  final EnviromentDao enviromentDao;
  final DispatchRulesDao dispatchRulesDao;
  final SequencesDao sequencesDao;
  final TasksDao tasksDao;
  final TaskDependencyDao taskDependencyDao;

  OrderRepositoryImpl(
      {required this.orderDao,
      required this.jobDao,
      required this.enviromentDao,
      required this.dispatchRulesDao,
      required this.sequencesDao,
      required this.tasksDao,
      required this.taskDependencyDao});

  @override
  Future<Either<Failure, List<OrderEntity>>> getAllOrders() async {
    try {
      final orderModels = await orderDao.getAllOrders();
      List<OrderEntity> orders = [];

      for (var orderModel in orderModels) {
        final List<JobModel> jobs =
            await jobDao.getJobsByOrderId(orderModel.orderId!);
        List<JobEntity> jobsEntities = [];
        for (final model in jobs) {
          final sequenceModel =
              await sequencesDao.getSequenceById(model.sequenceId);
          final List<TaskModel> tasks =
              await tasksDao.getTasksBySequenceId(sequenceModel!.sequenceId!);
          final List<TaskDependencyModel> dependenciesM =
              await taskDependencyDao
                  .getDependenciesBySequenceId(sequenceModel.sequenceId!);
          // Convert optional taskMachineTimesMinutes (minutes) to MachineTimes map
          Map<int, Map<int, MachineTimes>>? taskTimes;
          if (model.taskMachineTimesMinutes != null) {
            taskTimes = {};
            model.taskMachineTimesMinutes!.forEach((taskId, mm) {
              final inner = <int, MachineTimes>{};
              mm.forEach((machineId, mMap) {
                inner[machineId] = MachineTimes(
                  processing: Duration(minutes: mMap['processing'] ?? 0),
                  preparation: Duration(minutes: mMap['preparation'] ?? 0),
                  rest: Duration(minutes: mMap['rest'] ?? 0),
                );
              });
              taskTimes![taskId] = inner;
            });
          }

          JobEntity jobEntity = JobEntity(
              model.jobId,
              SequenceEntity(
                  sequenceModel.sequenceId,
                  tasks.map((mod) => mod.toEntity()).toList(),
                  sequenceModel.name,
                  dependenciesM.map((dep) => dep.toEntity()).toList()),
              model.amount,
              model.dueDate,
              model.priority,
              model.availableDate,
              preemptionMatrix: model.preemptionMatrix,
              taskMachineTimes: taskTimes);

          jobsEntities.add(jobEntity);
        }
        orders.add(
            OrderEntity(orderModel.orderId, orderModel.regDate, jobsEntities));
      }

      return Right(orders);
    } on Failure catch (error) {
      return Left(error);
    } catch (error, stack) {
      print('OrderRepositoryImpl.getAllOrders error: ' + error.toString());
      print(stack.toString());
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, EnvironmentEntity>> getEnvironmentByName(
      String name) async {
    try {
      final EnviromentModel env = await enviromentDao.getEnviromentByName(name);
      final dispatchRules = await dispatchRulesDao.getDispatchRules(env.id);

      return Right(EnvironmentEntity(env.id, env.name, dispatchRules));
    } on Failure catch (error) {
      return Left(error);
    }
  }

  @override
  Future<Either<Failure, OrderEntity>> getFullOrder(int id) async {
    try {
      final OrderModel order = await orderDao.getOrderById(id);
      final List<JobModel> jobs = await jobDao.getJobsByOrderId(id);
      List<JobEntity> jobsEntities = [];
      for (final model in jobs) {
        final sequenceModel =
            await sequencesDao.getSequenceById(model.sequenceId);
        final List<TaskModel> tasks =
            await tasksDao.getTasksBySequenceId(sequenceModel!.sequenceId!);
        final List<TaskDependencyModel> dependenciesM = await taskDependencyDao
            .getDependenciesBySequenceId(sequenceModel.sequenceId!);

        // Convert optional taskMachineTimesMinutes (minutes) to MachineTimes map
        Map<int, Map<int, dynamic>>? taskTimes;
        if (model.taskMachineTimesMinutes != null) {
          taskTimes = {};
          model.taskMachineTimesMinutes!.forEach((taskId, mm) {
            final inner = <int, dynamic>{};
            mm.forEach((machineId, mMap) {
              final processing = Duration(minutes: mMap['processing'] ?? 0);
              final preparation = Duration(minutes: mMap['preparation'] ?? 0);
              final rest = Duration(minutes: mMap['rest'] ?? 0);
              inner[machineId] = {
                'processing': processing,
                'preparation': preparation,
                'rest': rest,
              };
            });
            taskTimes![taskId] = inner;
          });
        }

        // Build MachineTimes objects using the sequence/tasks context
        Map<int, Map<int, MachineTimes>>? machineTimesMap;
        if (taskTimes != null) {
          machineTimesMap = {};
          taskTimes.forEach((taskId, mm) {
            final inner = <int, MachineTimes>{};
            mm.forEach((machineId, mvals) {
              inner[machineId] = MachineTimes(
                processing: mvals['processing'],
                preparation: mvals['preparation'],
                rest: mvals['rest'],
              );
            });
            machineTimesMap![taskId] = inner;
          });
        }

        JobEntity jobEntity = JobEntity(
            model.jobId,
            SequenceEntity(
                sequenceModel.sequenceId,
                tasks.map((mod) => mod.toEntity()).toList(),
                sequenceModel.name,
                dependenciesM.map((dep) => dep.toEntity()).toList()),
            model.amount,
            model.dueDate,
            model.priority,
            model.availableDate,
            preemptionMatrix: model.preemptionMatrix,
            taskMachineTimes: machineTimesMap);

        jobsEntities.add(jobEntity);
      }
      return Right(OrderEntity(order.orderId, order.regDate, jobsEntities));
    } on Failure catch (error) {
      return Left(error);
    } catch (error, stack) {
      print('OrderRepositoryImpl.getFullOrder error: ' + error.toString());
      print(stack.toString());
      return Left(LocalStorageFailure());
    }
  }

  @override
  Future<Either<Failure, bool>> createOrder(OrderEntity order) async {
    try {
      //insert order in data base and get orderId to create job
      final int orderId = await orderDao.insertOrder(order);

      if (order.orderJobs != null) {
        // insert each job from the orderJobs (list) on data base
        for (var job in order.orderJobs!) {
          await jobDao.insertJob(job, orderId);
        }
      }
      // return if order created sucessfully.
      return const Right(true);
    } on Failure catch (error) {
      return Left(error);
    }
  }

  @override
  Future<Either<Failure, bool>> deleteOrder(int orderId) async {
    try {
      await jobDao.deleteJobsFromOrder(orderId);
      await orderDao.deleteOrder(orderId);
      return const Right(true);
    } on Failure catch (error) {
      return Left(error);
    }
  }
}
