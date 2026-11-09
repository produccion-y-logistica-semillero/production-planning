import 'package:flutter/material.dart';
import 'package:flutter_side_menu/flutter_side_menu.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/high_order_widgets/main_navigator.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/settings/settings_dialog.dart';
import 'package:production_planning/shared/notation.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:provider/provider.dart';

class MainPage extends StatelessWidget {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  bool _isNavigating = false;
  int selected = 0;

  MainPage({super.key});

  @override
  Widget build(BuildContext context) {
    Color primaryContainer = Theme.of(context).colorScheme.primaryContainer;
    Color onPrimaryContainer = Theme.of(context).colorScheme.onPrimaryContainer;
    Color tertiaryContainer = Theme.of(context).colorScheme.tertiaryContainer;
    Color onTertiaryContainer =
        Theme.of(context).colorScheme.onTertiaryContainer;
    Color primaryFixed = Theme.of(context).colorScheme.primaryFixed;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: tertiaryContainer,
        elevation: 2,
        toolbarHeight: 50,
        title: Center(
          child: Text(
            "Programación de Operaciones",
            style: TextStyle(
                fontSize: 16,
                color: onTertiaryContainer,
                fontWeight: FontWeight.w600),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu, color: onTertiaryContainer),
          onPressed: () {
            Provider.of<SideMenuProvider>(context, listen: false)
                .changeExpansion();
          },
        ),
      ),
      body: Row(
        children: [
          Consumer<SideMenuProvider>(
            builder: (context, provider, _) {
              return SideMenu(
                hasResizerToggle: false,
                mode: provider.expanded
                    ? SideMenuMode.auto
                    : SideMenuMode.compact,
                minWidth: 70,
                maxWidth: 250,
                backgroundColor: primaryContainer,
                builder: (data) => SideMenuData(
                  header: Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix(<double>[
                        -1.0, 0.0, 0.0, 0.0, 255.0, // R
                        0.0, -1.0, 0.0, 0.0, 255.0, // G
                        0.0, 0.0, -1.0, 0.0, 255.0, // B
                        0.0, 0.0, 0.0, 1.0, 0.0, // A
                      ]),
                      child: Image.asset('assets/images/javeriana.png'),
                    ),
                  ),
                  items: [
                    // Workspace, Horario and Formato de tiempos live in one
                    // dialog with a section for each.
                    SideMenuItemDataTile(
                      title: 'Configuración',
                      onTap: () => showSettingsDialog(context),
                      titleStyle:
                          TextStyle(color: onPrimaryContainer, fontSize: 18),
                      hoverColor: primaryFixed.withValues(alpha: 0.15),
                      icon: TutorialTarget(
                          id: 'menu.config',
                          inflate: _menuRow,
                          child: Icon(Icons.tune, color: onPrimaryContainer)),
                      isSelected: false,
                    ),
                    const SideMenuItemDataDivider(
                        divider: Divider(height: 20, color: Colors.white)),
                    createItem(provider, context, '/machines',
                        'Estaciones de Trabajo', 1, Icons.settings),
                    createItem(provider, context, '/sequences',
                        'Rutas de Proceso', 2, Icons.work),
                    createItem(
                        provider,
                        context,
                        '/orders',
                        'Programas de produccion',
                        3,
                        Icons.schedule_send_sharp),
                    const SideMenuItemDataDivider(
                        divider: Divider(height: 20, color: Colors.white)),
                    createItem(provider, context, '/manual',
                        'Manual de usuario', 4, Icons.menu_book_outlined),
                    createItem(provider, context, '/notacion',
                        'Glosario de notación', 5, Icons.functions),
                    // Global switch: adds the theoretical symbols to every
                    // screen. The icon shows whether it is on.
                    SideMenuItemDataTile(
                      title: showNotation.value
                          ? 'Notación teórica: sí'
                          : 'Notación teórica: no',
                      onTap: () async {
                        await setNotation(!showNotation.value);
                        provider.changeOption(provider.selectedOption);
                      },
                      titleStyle:
                          TextStyle(color: onPrimaryContainer, fontSize: 18),
                      icon: TutorialTarget(
                          id: 'menu.notacion',
                          inflate: _menuRow,
                          child: Icon(
                              showNotation.value
                                  ? Icons.toggle_on
                                  : Icons.toggle_off_outlined,
                              color: onPrimaryContainer)),
                      isSelected: false,
                    ),
                  ],
                  footer: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Pontificia Universidad Javeriana',
                      style: TextStyle(
                          color: onPrimaryContainer.withOpacity(0.6),
                          fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            },
          ),
          Expanded(
            child: MainNavigator(_navigatorKey),
          ),
        ],
      ),
    );
  }

  void _navigateTo(String routeName) async {
    if (!_isNavigating && _navigatorKey.currentState != null) {
      _isNavigating = true;
      while (_navigatorKey.currentState?.canPop() ?? false) {
        _navigatorKey.currentState!.pop();
      }
      _navigatorKey.currentState!.pushNamed(routeName);
      _isNavigating = false;
    }
  }

  SideMenuItemDataTile createItem(
    SideMenuProvider provider,
    BuildContext context,
    String route,
    String title,
    int number,
    IconData icon,
  ) {
    Color onPrimaryContainer = Theme.of(context).colorScheme.onPrimaryContainer;
    Color primaryFixed = Theme.of(context).colorScheme.primaryFixed;

    return SideMenuItemDataTile(
      isSelected: provider.selectedOption == number,
      onTap: () {
        provider.changeOption(number);
        _navigateTo(route);
      },
      title: title,
      titleStyle: TextStyle(color: onPrimaryContainer, fontSize: 18),
      itemHeight: 50,
      hoverColor: primaryFixed.withOpacity(0.15),
      highlightSelectedColor: primaryFixed.withOpacity(0.2),
      selectedTitleStyle: TextStyle(
          color: onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 18),
      icon: TutorialTarget(
        id: 'menu$route',
        inflate: _menuRow,
        child: Icon(icon, color: onPrimaryContainer),
      ),
    );
  }

  /// Lights the whole menu row in the tutorial, not only its icon.
  static const EdgeInsets _menuRow = EdgeInsets.fromLTRB(8, 8, 190, 8);
}
