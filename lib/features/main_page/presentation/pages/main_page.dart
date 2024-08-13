import 'package:easy_sidemenu/easy_sidemenu.dart';
import 'package:flutter/material.dart';
import 'package:production_planning/features/main_page/presentation/widgets/main_navigator.dart';

class MainPage extends StatefulWidget {
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {

  //NOT USED, but needed simply because SideMenu requires it, however we manage routing manually with navigator
  final SideMenuController sideMenu = SideMenuController();

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isNavigating = false; // Add this to track navigation status


  @override
  Widget build(BuildContext context) {
    List<dynamic> items = _getMenuItems(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: Row(
        children: [
          SideMenu(
            showToggle: true,
            style: SideMenuStyle(
              displayMode: SideMenuDisplayMode.auto,
              openSideMenuWidth: 200,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              showHamburger: true,
            ),
            footer: const Text(
              'Pontificia Universidad Javeriana',
              textAlign: TextAlign.center,
            ),
            items: items,
            controller: sideMenu,   //NOT USED
          ),
          Expanded(
            child: MainNavigator(_navigatorKey)
          ),
        ],
      ),
    );
  }


  //creation of sidemenu items, is isolated but in a function because we need the build context
  List<dynamic> _getMenuItems(BuildContext context){
    return [
        SideMenuItem(
          title: 'Machines',
          icon: Icon(Icons.build, color: Theme.of(context).colorScheme.onPrimaryContainer,),
          onTap: (index, _) {
            _navigateTo('/machines');
          },
        ),
        const SideMenuExpansionItem(
          title: "Expansion",
          children: [
            SideMenuItem(
              title: "Second"
            )
          ]
      )
    ];
  }

  //Function to navigate
  void _navigateTo(String routeName) async {
    if (!_isNavigating && _navigatorKey.currentState != null) {
      setState(() {
        _isNavigating = true;
      });

      await _navigatorKey.currentState!.pushNamed(routeName);

      setState(() {
        _isNavigating = false;
      });
    }
  }
}
