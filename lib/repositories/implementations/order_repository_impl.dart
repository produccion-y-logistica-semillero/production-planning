import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/daos/interfaces/tasks_dao.dart';
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
import 'package:production_planning/repositories/interfaces/order_repository.dart';

class OrderRepositoryImpl implements OrderRepository{
  final OrderDao orderDao;
  final JobDao jobDao;
  final EnviromentDao enviromentDao;
  final DispatchRulesDao dispatchRulesDao;
  final SequencesDao sequencesDao;
  final TasksDao tasksDao;

  OrderRepositoryImpl({
    required this.orderDao, 
    required this.jobDao, 
    required this.enviromentDao, 
    required this.dispatchRulesDao,
    required this.sequencesDao,
    required this.tasksDao,
  });

  @override
  Future<Either<Failure, List<OrderEntity>>> getAllOrders() async {
    try {
      // 1. Obtener todas las órdenes
      final orderModels = await orderDao.getAllOrders();
      List<OrderEntity> orders = [];

      for (var orderModel in orderModels) {
        final List<JobModel> jobs = await jobDao.getJobsByOrderId(orderModel.orderId!);
        List<JobEntity> jobsEntities = [];
        for(final model in jobs){
          final sequenceModel = await sequencesDao.getSequenceById(model.sequenceId);
          final List<TaskModel> tasks = await tasksDao.getTasksBySequenceId(sequenceModel!.sequenceId!);

          jobsEntities.add(
            JobEntity(
              model.jobId, 
              SequenceEntity(
                sequenceModel.sequenceId, 
                tasks.map((mod)=> mod.toEntity()).toList(),
                sequenceModel.name
              ), 
              model.amount, 
              model.dueDate, 
              model.priority, 
              model.availableDate
            )
          );
        }
        orders.add(OrderEntity(orderModel.orderId, orderModel.regDate, jobsEntities));
      }

      return Right(orders);
    } on Failure catch (error) {
      return Left(error);
    }
  }

  @override
  Future<Either<Failure, EnvironmentEntity>> getEnvironmentByName(String name) async {
    try{
      final EnviromentModel env = await enviromentDao.getEnviromentByName(name);
      final dispatchRules = await dispatchRulesDao.getDispatchRules(env.id);
      print(dispatchRules);
      return Right(EnvironmentEntity(env.id, env.name, dispatchRules));
    }
    on Failure catch(error){
      return Left(error);
    }
  }

  @override
  Future<Either<Failure, OrderEntity>> getFullOrder(int id) async{
    try{
      final OrderModel order = await orderDao.getOrderById(id);
      final List<JobModel> jobs = await jobDao.getJobsByOrderId(id);
      List<JobEntity> jobsEntities = [];
      for(final model in jobs){
        final sequenceModel = await sequencesDao.getSequenceById(model.sequenceId);
        final List<TaskModel> tasks = await tasksDao.getTasksBySequenceId(sequenceModel!.sequenceId!);

        jobsEntities.add(
          JobEntity(
            model.jobId, 
            SequenceEntity(
              sequenceModel.sequenceId, 
              tasks.map((mod)=> mod.toEntity()).toList(),
              sequenceModel.name
            ), 
            model.amount, 
            model.dueDate, 
            model.priority, 
            model.availableDate
          )
        );
      }
      return Right(
        OrderEntity(order.orderId, order.regDate, jobsEntities)
      );
    }
    on Failure catch(error){
      return Left(error);
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
  Future<Either<Failure, bool>> deleteOrder(int orderId) async{
    try{
      await jobDao.deleteJobsFromOrder(orderId);
      await orderDao.deleteOrder(orderId);
      return const Right(true);
    }on Failure catch(error){
      return Left(error);
    }
  }
}
