import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/features/0_machines/presentation/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/features/0_machines/presentation/pages/machines_list_page.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/features/1_sequences/presentation/bloc/see_processes_bloc/see_process_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/bloc/orders_bloc/orders_bloc.dart';
import 'package:production_planning/features/2_orders/presentation/pages/orders_page.dart';
import 'package:production_planning/features/main_page/presentation/pages/welcome_page.dart';
import 'package:production_planning/features/1_sequences/presentation/pages/sequences_page.dart';

class MainNavigator extends StatelessWidget{
  final GlobalKey<NavigatorState> _navigatorKey;

  const MainNavigator(this._navigatorKey, {super.key});

  @override
  Widget build(BuildContext context) {
    return Navigator(
              key: _navigatorKey,
              initialRoute: '/welcomePage',
              onGenerateRoute: (RouteSettings settings) {
                WidgetBuilder builder;
                switch (settings.name) {
                  case '/sequences':
                    builder = (BuildContext _) => MultiBlocProvider(
                      providers: [
                        BlocProvider<SequencesBloc> (
                          create: (context) => GetIt.instance.get<SequencesBloc>(),
                        ),
                        BlocProvider<SeeProcessBloc> (
                          create: (context) => GetIt.instance.get<SeeProcessBloc>(),
                        ),
                      ],
                      child: SequencesPage()
                    );
                    break;
                  case '/orders':
                    builder = (BuildContext _) => BlocProvider(
                        create: (context) => GetIt.instance.get<OrdersBloc>(),
                        child: OrdersPage(),
                    );
                    break;
                  case '/machines':
                  //IMPORTANT, WE PROVIDE THE PROVIDER HERE, AS NEAR TO THE PART OF THE WIDGET TREE
                  //IT WILL BE USED, THIS IS TO ONLY HAVE THAT INFO IN MEMORY WHEN WE ARE IN THIS PAGE.
                    builder = (BuildContext _) => BlocProvider(
                      create: (context)=>GetIt.instance.get<MachineTypesBloc>(),
                      child: MachinesListPage()
                    );
                    break;
                  case '/welcomePage':
                    builder = (BuildContext _) => WelcomePage();
                    break;
                  default:
                    builder = (BuildContext _) => WelcomePage(); // Fallback route
                }
                return MaterialPageRoute(builder: builder, settings: settings);
              },
            );
  }
}