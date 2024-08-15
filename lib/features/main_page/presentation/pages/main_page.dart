import 'dart:ffi';

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

  bool _menuExpanded = true; //To control to hide or expand the side menu manually


  @override
  Widget build(BuildContext context) {
    Color onPrimary = Theme.of(context).colorScheme.onPrimary;
    Color primaryContainer = Theme.of(context).colorScheme.primaryContainer;
    Color onPrimaryContainer = Theme.of(context).colorScheme.onPrimaryContainer;
    Color surface = Theme.of(context).colorScheme.surface;
    Color secondaryContainer = Theme.of(context).colorScheme.secondaryContainer;
    Color onSecondaryContainer = Theme.of(context).colorScheme.onSecondaryContainer;
    List<dynamic> items = _getMenuItems(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: secondaryContainer,
        toolbarHeight: 40,
        title: Center(child: Text("Production planning", style: TextStyle(fontSize: 15, color: onSecondaryContainer),)),
        //to manually control if the side menu is expanded or not
        leading:  GestureDetector(
          child: IconButton(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.all(0))
            ),
            icon: Center(child: Icon(Icons.menu, color: onSecondaryContainer,)),
            onPressed: (){
              setState(() {
                _menuExpanded = _menuExpanded ? false: true;
              });
            },
          ),
        )
      ),
      body: Row(
        children: [
          SideMenu(
            showToggle: true,
            title: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                child:  Center(
                  child: Icon(Icons.schedule, size: 50, color: onPrimaryContainer,), 
                ),
              ),
            style: SideMenuStyle(
              displayMode: _menuExpanded ? SideMenuDisplayMode.auto : SideMenuDisplayMode.compact,
              openSideMenuWidth: 300,
              backgroundColor: primaryContainer,
              showHamburger: false, //to hide the menu button since we implement it on our own 
              selectedColor: primaryContainer,
              selectedIconColor: onPrimaryContainer,
              unselectedIconColorExpandable: onPrimaryContainer,
              selectedTitleTextStyle: TextStyle(color: onPrimaryContainer),
              arrowCollapse: const Color.fromARGB(255, 255, 243, 209),
              selectedHoverColor: secondaryContainer,
            ),
            footer: Text(
              'Pontificia Universidad Javeriana',
              textAlign: TextAlign.center,
              style: TextStyle(color: onPrimaryContainer),
            ),
            items: items,
            controller: sideMenu,   //NOT USEDDDDDDDDDD
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
        title: 'Maquinas',
        icon: Icon(Icons.build, color: Theme.of(context).colorScheme.primaryContainer,),
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
