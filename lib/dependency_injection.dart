import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/core/factories/factory.dart';
import 'package:production_planning/core/factories/sqllite_factory.dart';
import 'package:production_planning/repositories/implementations/machine_repository_impl.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/presentation/0_machines/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/repositories/implementations/sequences_repository_impl.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/presentation/1_sequences/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/repositories/implementations/order_repository_impl.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/orders_bloc/orders_bloc.dart';
import 'package:production_planning/presentation/2_orders/widgets/low_order/task_bloc.dart';
import 'package:production_planning/services/machines_service.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/services/sequences_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

final depIn = GetIt.instance;

TimeOfDay START_SCHEDULE = const TimeOfDay(hour: 8, minute: 0);
TimeOfDay END_SCHEDULE = const TimeOfDay(hour: 17, minute: 0);


Future<void> initDependencies(String workspace) async {
  try {
    // Initialize the sqflite FFI loader for desktop platforms
    sqflite_ffi.sqfliteFfiInit();
    // Set the database factory to FFI
    sqflite_ffi.databaseFactory = sqflite_ffi.databaseFactoryFfi;
    //registering database, I do it like this so that the app can register all the other dependencies while opening the database
    //we also register the dispose method so it closes the connection

    //creating DAO's factory
    final Factory daoFactory = await SqlLiteFactory.create(workspace);


    //repositories
    final machineRepo   = MachineRepositoryImpl(
      machineTypeDao: daoFactory.getMachineTypeDao(),
      machineDao:  daoFactory.getMachineDao(),
      statusDao: daoFactory.getStatusDao()
    );
    final sequencesRepo =  SequencesRepositoryImpl(
      sequencesDao: daoFactory.getSequenceDao(), 
      tasksDao: daoFactory.getTaskDao(),
      machineTypeDao: daoFactory.getMachineTypeDao()
      ,taskDependencyDao: daoFactory.getTaskDependencyDao()
    );
    final ordersRepo = OrderRepositoryImpl(
      orderDao: daoFactory.getOrderDao(), 
      jobDao: daoFactory.getJobDao(),
      enviromentDao: daoFactory.getEnviromentDao(),
      dispatchRulesDao: daoFactory.getDispatchRulesDao(),
      sequencesDao: daoFactory.getSequenceDao(),
      tasksDao: daoFactory.getTaskDao()
      ,taskDependencyDao: daoFactory.getTaskDependencyDao()
    );
  
    //services
    final machinesService = MachinesService(machineRepo);
    final ordersService = OrdersService(ordersRepo, machineRepo);
    final seqService = SequencesService(sequencesRepo);
    

    //Bloc
    //its factory since we want to create a new one each time we get to the point it's provided, if we wanted to mantain the state no matter where we go, we could make it singleton
    depIn.registerFactory<MachineBloc>(
      ()=> MachineBloc(machinesService)
    );
    depIn.registerFactory<MachineTypesBloc>(
      ()=> MachineTypesBloc(machinesService)
    );
    depIn.registerFactory<SequencesBloc>(
      ()=> SequencesBloc(seqService, machinesService)
    );
    depIn.registerFactory<SeeProcessBloc>(
      ()=> SeeProcessBloc(seqService)
    );

    //Bloc orders
    depIn.registerFactory<OrderBloc>(
      ()=> OrderBloc(ordersService)
    );
    depIn.registerFactory<NewOrderBloc>(
      ()=> NewOrderBloc(ordersService, seqService)
    );
    depIn.registerFactory<GanttBloc>(
      ()=> GanttBloc(ordersService)
    );

    depIn.registerFactory<TaskBloc>(
      ()=> TaskBloc(ordersRepo)
    );
  }
  catch(e){
    //to implement file logging later if needed
  }
}
