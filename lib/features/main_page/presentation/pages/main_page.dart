import 'package:flutter/material.dart';
import 'package:flutter_side_menu/flutter_side_menu.dart';
import 'package:production_planning/features/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/features/main_page/presentation/widgets/high_order_widgets/main_navigator.dart';
import 'package:provider/provider.dart';

class MainPage extends StatelessWidget {

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _isNavigating = false; // Add this to track navigation status

  bool _menuExpanded = true; //To control to hide or expand the side menu manually

  int selected = 0; //this variable keeps track of the option selected in the menu


  @override
  Widget build(BuildContext context) {
    Color primaryContainer = Theme.of(context).colorScheme.primaryContainer;
    Color onPrimaryContainer = Theme.of(context).colorScheme.onPrimaryContainer;
    Color secondaryContainer = Theme.of(context).colorScheme.secondaryContainer;
    Color onSecondaryContainer = Theme.of(context).colorScheme.onSecondaryContainer;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: secondaryContainer,
        toolbarHeight: 40,
        title: Center(child: Text("Planeacion de producción", style: TextStyle(fontSize: 15, color: onSecondaryContainer),)),
        //to manually control if the side menu is expanded or not
        leading:  GestureDetector(
          child: IconButton(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.all(0))
            ),
            icon: Center(child: Icon(Icons.menu, color: onSecondaryContainer,)),
            onPressed: (){
               Provider.of<SideMenuProvider>(context, listen: false).changeExpansion();
            },
          ),
        )
      ),
      body: Row(
        children: [
          //we wrap the side menu in a consumer of the provider to only re render the side menu
          Consumer<SideMenuProvider>(
            builder: (context, provider, _) {
              return SideMenu(
                hasResizerToggle: false,
                mode: provider.expanded ? SideMenuMode.auto : SideMenuMode.compact,
                minWidth: 70,
                maxWidth: 300,
                backgroundColor: primaryContainer ,
                builder: (data)=> SideMenuData(
                  header: Container(
                    margin: const EdgeInsets.symmetric(vertical: 20),
                    child: Icon(
                      Icons.schedule,
                      weight: 100,
                      size: 70,
                      color: onPrimaryContainer,
                    )
                  ),
                  items : [
                     SideMenuItemDataTile(
                            isSelected: provider.selectedOption == 1 ? true : false,  //checks if the selected option is its one
                            onTap: (){
                              provider.changeOption(1);
                              _navigateTo('/machines');
                            },
                            title: 'Maquinas',
                            titleStyle: TextStyle(color: onPrimaryContainer, fontSize: 20),
                            itemHeight: 60,
                            hoverColor: secondaryContainer,
                            icon: const Icon(Icons.build),
                          ),
                      SideMenuItemDataTile(
                            isSelected: provider.selectedOption == 2 ? true : false, //checks if the selected option is its one
                            onTap: (){
                              provider.changeOption(2);
                               _navigateTo('/sequences');
                            },
                            title: 'Secuencias',
                            titleStyle: TextStyle(color: onPrimaryContainer, fontSize: 20),
                            itemHeight: 60,
                            hoverColor: secondaryContainer,
                            icon: const Icon(Icons.work_history),
                          ),
                       
                  ],
                  footer: const Text('Pontificia universidad Javeriana'),
                )
              );
            }
          ),
          Expanded(
            child: MainNavigator(_navigatorKey)
          ),
        ],
      ),
    );
  }

  //Function to navigate
  void _navigateTo(String routeName) async {
    if (!_isNavigating && _navigatorKey.currentState != null) {
        _isNavigating = true;
         await _navigatorKey.currentState!.pushNamed(routeName);
        _isNavigating = false;
    }
  }
}
