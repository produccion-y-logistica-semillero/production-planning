import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:production_planning/core/factories/factory.dart';
import 'package:production_planning/core/factories/sqllite_factory.dart';
import 'package:production_planning/features/machines/data/repositories/machine_repository_impl.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/machines/domain/use_cases/add_machine_type_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/delete_machine_type_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/get_machines_type_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/get_machines_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_bloc.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;


final depIn = GetIt.instance;

Future<void> initDependencies() async{
  try{
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
      machineDao:  daoFactory.getMachineDao()
    ));

    //Machine use cases
    depIn.registerLazySingleton<AddMachineTypeUseCase>(() => AddMachineTypeUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<GetMachineTypesUseCase>(() => GetMachineTypesUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<DeleteMachineTypeUseCase>(()=>DeleteMachineTypeUseCase(repository: depIn.get<MachineRepository>()));
    depIn.registerLazySingleton<GetMachinesUseCase>(()=> GetMachinesUseCase(repository: depIn.get<MachineRepository>()));
    
    //Bloc machine
    //its factory since we want to create a new one each time we get to the point it's provided, if we wanted to mantain the state no matter where we go, we could make it singleton
    depIn.registerFactory<MachineBloc>(
      ()=> MachineBloc(
        depIn.get<GetMachinesUseCase>()
      )
    );
    depIn.registerFactory<MachineTypesBloc>(
      ()=> MachineTypesBloc(
        depIn.get<AddMachineTypeUseCase>() , 
        depIn.get<GetMachineTypesUseCase>(),
        depIn.get<DeleteMachineTypeUseCase>(),
      )
    );
  }
  catch(e){
    logMessage('Dependency initialization failed: $e');
  }
}

void logMessage(String message) {
  final logFile = File('log.txt');
  logFile.writeAsStringSync(message + '\n', mode: FileMode.append);
}