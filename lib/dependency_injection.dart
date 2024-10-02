import 'package:get_it/get_it.dart';
import 'package:production_planning/core/factories/factory.dart';
import 'package:production_planning/core/factories/sqllite_factory.dart';
import 'package:production_planning/features/0_machines/data/repositories/machine_repository_impl.dart';
import 'package:production_planning/features/0_machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/add_machine_type_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/add_machine_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/delete_machine_id_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/delete_machine_type_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_type_use_case.dart';
import 'package:production_planning/features/0_machines/domain/use_cases/get_machines_use_case.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machines_bloc/machine_bloc.dart';
import 'package:production_planning/features/1_sequences/data/repositories/sequences_repository_impl.dart';
import 'package:production_planning/features/1_sequences/domain/repositories/sequences_repository.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/add_sequence_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/delete_sequence_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/get_sequence_use_case.dart';
import 'package:production_planning/features/1_sequences/domain/use_cases/get_sequences_use_case.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/features/2_orders/data/repositories/order_repository_impl.dart';
import 'package:production_planning/features/2_orders/domain/repositories/order_repository.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/add_order_use_case.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/get_order_environment.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/get_orders_use_case.dart';
import 'package:production_planning/features/2_orders/domain/use_cases/schedule_order_use_case.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_bloc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;

final depIn = GetIt.instance;

Future<void> initDependencies() async {
  try {
    // Initialize the sqflite FFI loader for desktop platforms
    sqflite_ffi.sqfliteFfiInit();
    // Set the database factory to FFI
    sqflite_ffi.databaseFactory = sqflite_ffi.databaseFactoryFfi;
    //registering database, I do it like this so that the app can register all the other dependencies while opening the database
    //we also register the dispose method so it closes the connection

    //creating DAO's factory
    final Factory daoFactory = await SqlLiteFactory.create();


    //Machine repositories
    depIn.registerLazySingleton<MachineRepository>(()=>MachineRepositoryImpl(
      machineTypeDao: daoFactory.getMachineTypeDao(),
      machineDao:  daoFactory.getMachineDao(),
      statusDao: daoFactory.getStatusDao()
    ));
    
    //Sequences repositories
    depIn.registerLazySingleton<SequencesRepository>(()=> SequencesRepositoryImpl(
      sequencesDao: daoFactory.getSequenceDao(), 
      tasksDao: daoFactory.getTaskDao(),
      machineTypeDao: daoFactory.getMachineTypeDao()
    ));

    //Orders repositories
    depIn.registerLazySingleton<OrderRepository>(()=> OrderRepositoryImpl(
      orderDao: daoFactory.getOrderDao(), 
      jobDao: daoFactory.getJobDao()
    ));

    //Machine use cases
    depIn.registerLazySingleton<AddMachineTypeUseCase>(() => AddMachineTypeUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<GetMachineTypesUseCase>(() => GetMachineTypesUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<DeleteMachineTypeUseCase>(()=>DeleteMachineTypeUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<GetMachinesUseCase>(()=> GetMachinesUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<DeleteMachineUseCase>(()=> DeleteMachineUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<AddMachineUseCase>(()=>AddMachineUseCase(repository: depIn.get<MachineRepository>()));

    //Sequences use cases
    depIn.registerLazySingleton<AddSequenceUseCase>(()=> AddSequenceUseCase(depIn.get<SequencesRepository>()));
    depIn.registerLazySingleton<GetSequenceUseCase>(()=> GetSequenceUseCase(depIn.get<SequencesRepository>()));
    depIn.registerLazySingleton<GetSequencesUseCase>(()=> GetSequencesUseCase(depIn.get<SequencesRepository>()));
    depIn.registerLazySingleton<DeleteSequenceUseCase>(()=> DeleteSequenceUseCase(depIn.get<SequencesRepository>()));

    //Orders use cases
    depIn.registerLazySingleton<AddOrderUseCase>(()=> AddOrderUseCase());
    depIn.registerLazySingleton<GetOrderEnvironment>(()=> GetOrderEnvironment(depIn.get<OrderRepository>(), depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<GetOrdersUseCase>(()=> GetOrdersUseCase(repository: depIn.get<OrderRepository>()));
    depIn.registerLazySingleton<ScheduleOrderUseCase>(()=> ScheduleOrderUseCase());
    
    //Bloc machine
    //its factory since we want to create a new one each time we get to the point it's provided, if we wanted to mantain the state no matter where we go, we could make it singleton
    depIn.registerFactory<MachineBloc>(
      ()=> MachineBloc(
        depIn.get<GetMachinesUseCase>(),
        depIn.get<DeleteMachineUseCase>(),
        depIn.get<AddMachineUseCase>()
      )
    );
    depIn.registerFactory<MachineTypesBloc>(
      ()=> MachineTypesBloc(
        depIn.get<AddMachineTypeUseCase>() , 
        depIn.get<GetMachineTypesUseCase>(),
        depIn.get<DeleteMachineTypeUseCase>(),
      )
    );
    depIn.registerFactory<SequencesBloc>(
      ()=> SequencesBloc(
        depIn.get<GetMachineTypesUseCase>(),
        depIn.get<AddSequenceUseCase>()
      )
    );
    depIn.registerFactory<SeeProcessBloc>(
      ()=> SeeProcessBloc(
        depIn.get<GetSequencesUseCase>(),
        depIn.get<GetSequenceUseCase>(),
        depIn.get<DeleteSequenceUseCase>()
      )
    );

    //Bloc orders
    depIn.registerFactory<OrdersBloc>(
      ()=> OrdersBloc()
    );
    depIn.registerFactory<NewOrderBloc>(
      ()=> NewOrderBloc()
    );
    depIn.registerFactory<GanttBloc>(
      ()=> GanttBloc(
        depIn.get<GetOrderEnvironment>(),
        depIn.get<ScheduleOrderUseCase>()
      )
    );
  }
  catch(e){
    //to implement file logging later if needed
  }
}
