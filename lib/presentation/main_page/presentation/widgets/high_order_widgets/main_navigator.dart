import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/presentation/0_machines/pages/machines_list_page.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/presentation/2_orders/bloc/orders_bloc/orders_bloc.dart';
import 'package:production_planning/presentation/2_orders/pages/orders_page.dart';
import 'package:production_planning/presentation/main_page/presentation/pages/welcome_page.dart';
import 'package:production_planning/presentation/1_sequences/pages/sequences_page.dart';

class MainNavigator extends StatelessWidget {
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
            builder = (BuildContext _) => BlocProvider<SequencesBloc>(
                create: (context) => GetIt.instance.get<SequencesBloc>(),
                child: const SequencesPage());
            break;
          case '/orders':
            builder = (BuildContext _) => BlocProvider(
                  create: (context) => GetIt.instance.get<OrderBloc>(),
                  child: const OrdersPage(),
                );
            break;
          case '/machines':
            //IMPORTANT, WE PROVIDE THE PROVIDER HERE, AS NEAR TO THE PART OF THE WIDGET TREE
            //IT WILL BE USED, THIS IS TO ONLY HAVE THAT INFO IN MEMORY WHEN WE ARE IN THIS PAGE.
            builder = (BuildContext _) => BlocProvider(
                create: (context) => GetIt.instance.get<MachineTypesBloc>(),
                child: MachinesListPage());
            break;
          case '/welcomePage':
            builder = (BuildContext _) => const WelcomePage();
            break;
          default:
            builder = (BuildContext _) => const WelcomePage(); // Fallback route
        }
        return MaterialPageRoute(builder: builder, settings: settings);
      },
    );
  }
}
