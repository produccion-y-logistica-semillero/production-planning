import 'package:flutter/material.dart';
import 'package:production_planning/features/machines/presentation/pages/machines_list_page.dart';
import 'package:production_planning/features/main_page/presentation/pages/welcome_page.dart';

class MainNavigator extends StatelessWidget{
  final GlobalKey<NavigatorState> _navigatorKey;

  MainNavigator(this._navigatorKey);

  @override
  Widget build(BuildContext context) {
    return Navigator(
              key: _navigatorKey,
              initialRoute: '/welcomePage',
              onGenerateRoute: (RouteSettings settings) {
                WidgetBuilder builder;
                switch (settings.name) {
                  case '/machines':
                    builder = (BuildContext _) => MachinesListPage();
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