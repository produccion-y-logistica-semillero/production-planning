import 'package:flutter/material.dart';
import 'package:flutter_side_menu/flutter_side_menu.dart';
import 'package:production_planning/features/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/features/main_page/presentation/widgets/high_order_widgets/main_navigator.dart';
import 'package:provider/provider.dart';

class MainPage extends StatelessWidget {

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _isNavigating = false; // Add this to track navigation status

  int selected = 0; //this variable keeps track of the option selected in the menu

  MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    Color primaryContainer = Theme.of(context).colorScheme.primaryContainer;
    Color onPrimaryContainer = Theme.of(context).colorScheme.onPrimaryContainer;
    Color tertiaryContainer = Theme.of(context).colorScheme.tertiaryContainer;
    Color onTertiaryContainer = Theme.of(context).colorScheme.onTertiaryContainer;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: tertiaryContainer,
        toolbarHeight: 40,
        title: Center(child: Text("Planeacion de producción", style: TextStyle(fontSize: 15, color: onTertiaryContainer),)),
        //to manually control if the side menu is expanded or not
        leading:  GestureDetector(
          child: IconButton(
            style: const ButtonStyle(
              padding: WidgetStatePropertyAll(EdgeInsets.all(0))
            ),
            icon: Center(child: Icon(Icons.menu, color: onTertiaryContainer,)),
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
                      createItem(provider, context, '/machines', 'Maquinas', 1, Icons.settings),
                      createItem(provider, context, '/sequences', 'Secuencias',2,  Icons.work),
                      createItem(provider, context, '/orders', 'Ordenes', 3, Icons.schedule_send_sharp),
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

  SideMenuItemDataTile createItem(SideMenuProvider provider, BuildContext context, String route, String title, int number, IconData icon)
  {

    Color onPrimaryContainer = Theme.of(context).colorScheme.onPrimaryContainer;
    Color primaryFixed = Theme.of(context).colorScheme.primaryFixed;
    return SideMenuItemDataTile(
                            isSelected: provider.selectedOption == number ? true : false, //checks if the selected option is its one
                            onTap: (){
                              provider.changeOption(number);
                               _navigateTo(route);
                            },
                            title: title,
                            titleStyle: TextStyle(color: onPrimaryContainer, fontSize: 20),
                            itemHeight: 60,
                            hoverColor: primaryFixed,
                            highlightSelectedColor: primaryFixed,
                            selectedTitleStyle: TextStyle(color: onPrimaryContainer, fontSize: 20),
                            icon: Icon(icon),
                          );
  }


}
