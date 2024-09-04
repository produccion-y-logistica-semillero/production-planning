import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/core/themes/theme.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/features/machines/domain/use_cases/add_machine_type_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/delete_machine_type_use_case.dart';
import 'package:production_planning/features/machines/domain/use_cases/get_machines_type_use_case.dart';
import 'package:production_planning/features/machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/machines/presentation/widgets/low_order_widgets/add_machine_dialog.dart';
import 'package:production_planning/features/main_page/presentation/pages/main_page.dart';

void logMessage(String message) {
  final logFile = File('log.txt');
  logFile.writeAsStringSync(message + '\n', mode: FileMode.append);
}

void main() async {
  logMessage('App started');
  await initDependencies();
  logMessage('dependencies started');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // return MaterialApp(
    //   title: 'Flutter Demo',
    //   theme: lightTheme,
    //   home: MainPage(),
    //   debugShowCheckedModeBanner: false,
    // );

    return MultiBlocProvider(
        providers: [
          BlocProvider(
              create: (context) => MachineTypesBloc(
                  GetIt.instance<AddMachineTypeUseCase>(),
                  GetIt.instance<GetMachineTypesUseCase>(),
                  GetIt.instance<DeleteMachineTypeUseCase>())),
        ],
        child: MaterialApp(
          title: 'Flutter Demo',
          theme: lightTheme,
          home: MainPage(),
          debugShowCheckedModeBanner: false,
        ));
  }
}
