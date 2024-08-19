import 'package:get_it/get_it.dart';
import 'package:production_planning/core/data/db/database_provider.dart';
import 'package:production_planning/features/machines/data/data_sources/machine_data_source_sqllite.dart';
import 'package:production_planning/features/machines/data/repositories/machine_repository_impl.dart';
import 'package:production_planning/features/machines/domain/repositories/machine_repository.dart';
import 'package:production_planning/features/machines/domain/use_cases/add_machine_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/get_machines_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_bloc.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


final depIn = GetIt.instance;

Future<void> initDependencies() async{
  // Initialize the sqflite FFI loader for desktop platforms
  sqfliteFfiInit();
  // Set the database factory to FFI
  databaseFactory = databaseFactoryFfi;
  //registering database, I do it like this so that the app can register all the other dependencies while opening the database
  //we also register the dispose method so it closes the connection
  final Database db = await  DatabaseProvider.open();
  depIn.registerSingleton<Database>(db, 
      dispose: (db) async => await DatabaseProvider.closeDatabaseConnection());

  //Machine data sources
  depIn.registerLazySingleton<MachineDataSourceSqllite>(() => MachineDataSourceSqllite(depIn.get<Database>()));
  //Machine repositories
  depIn.registerLazySingleton<MachineRepository>(()=>MachineRepositoryImpl(sqlLiteSource: depIn.get<MachineDataSourceSqllite>()));
  //Machine use cases
  depIn.registerLazySingleton<AddMachineUseCase>(() => AddMachineUseCase(repository: depIn.get<MachineRepository>()));
  depIn.registerLazySingleton<GetMachinesUseCase>(() => GetMachinesUseCase(repository: depIn.get<MachineRepository>()));
  //Bloc machine
  //its factory since we want to create a new one each time we get to the point it's provided, if we wanted to mantain the state no matter where we go, we could make it singleton
  depIn.registerFactory<MachineBloc>(
    ()=> MachineBloc(depIn.get<AddMachineUseCase>() , depIn.get<GetMachinesUseCase>())
  );
}