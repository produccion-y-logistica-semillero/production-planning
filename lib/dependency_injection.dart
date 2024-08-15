


import 'package:get_it/get_it.dart';
import 'package:production_planning/features/machines/domain/use_cases/add_machine_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machines_bloc/machine_bloc.dart';

final depIn = GetIt.instance;

Future<void> initDependencies() async{
  //Machine use cases
  depIn.registerLazySingleton<AddMachineUseCase>(() => AddMachineUseCase());
  //Bloc machine
  depIn.registerFactory<MachineBloc>(
    ()=> MachineBloc(GetIt.instance.get<AddMachineUseCase>())
  );
}