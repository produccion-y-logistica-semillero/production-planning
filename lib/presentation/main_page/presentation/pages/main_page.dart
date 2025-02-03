import 'package:flutter/material.dart';
import 'package:flutter_side_menu/flutter_side_menu.dart';
import 'package:path/path.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/presentation/main_page/presentation/widgets/high_order_widgets/main_navigator.dart';
import 'package:provider/provider.dart';
import 'dart:io';

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
    Color onTertiaryContainer = Theme.of(context).colorScheme.onTertiaryContainer;
    Color primaryFixed = Theme.of(context).colorScheme.primaryFixed;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: tertiaryContainer,
        elevation: 2,
        toolbarHeight: 50,
        title: Center(
          child: Text(
            "Planeacion de Producción",
            style: TextStyle(fontSize: 16, color: onTertiaryContainer, fontWeight: FontWeight.w600),
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.menu, color: onTertiaryContainer),
          onPressed: () {
            Provider.of<SideMenuProvider>(context, listen: false).changeExpansion();
          },
        ),
      ),
      body: Row(
        children: [
          Consumer<SideMenuProvider>(
            builder: (context, provider, _) {
              return SideMenu(
                hasResizerToggle: false,
                mode: provider.expanded ? SideMenuMode.auto : SideMenuMode.compact,
                minWidth: 70,
                maxWidth: 250,
                backgroundColor: primaryContainer,
                builder: (data) => SideMenuData(
                  header: Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    child: Image.asset('assets/images/javeriana.png'),
                  ),
                  items: [
                    SideMenuItemDataTile(
                      title: 'Workspace',
                      onTap: () => _showWorkspaceDialog(context),
                      titleStyle: TextStyle(color: onPrimaryContainer, fontSize: 18),
                      icon: Icon(Icons.workspaces_outline, color: onPrimaryContainer),
                      isSelected: false,
                    ),
                    SideMenuItemDataTile(
                      title: 'Horario',
                      onTap: () => _showScheduleDialog(context),
                      titleStyle: TextStyle(color: onPrimaryContainer, fontSize: 18),
                      icon: Icon(Icons.schedule, color: onPrimaryContainer),
                      isSelected: false,
                    ),
                    SideMenuItemDataDivider(divider: const Divider(height: 20, color: Colors.white)),
                    createItem(provider, context, '/machines', 'Maquinas', 1, Icons.settings),
                    createItem(provider, context, '/sequences', 'Secuencias', 2, Icons.work),
                    createItem(provider, context, '/orders', 'Ordenes', 3, Icons.schedule_send_sharp),
                  ],
                  footer: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'Pontificia Universidad Javeriana',
                      style: TextStyle(color: onPrimaryContainer.withOpacity(0.6), fontSize: 12),
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
      selectedTitleStyle: TextStyle(color: onPrimaryContainer, fontWeight: FontWeight.bold, fontSize: 18),
      icon: Icon(icon, color: onPrimaryContainer),
    );
  }

  Future<void> _showWorkspaceDialog(BuildContext context) async {
    final file = File('workspace.txt');
    List<String> options = [];
    String currentWorkspace = 'default';

    if (await file.exists()) {
      List<String> lines = await file.readAsLines();
      if (lines.isNotEmpty) {
        currentWorkspace = lines[0];
        options = lines.sublist(1);
      }
    }

    String? selectedWorkspace = currentWorkspace;
    TextEditingController newWorkspaceController = TextEditingController();

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Selecciona o crea un workspace'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (options.isNotEmpty)
                DropdownButton<String>(
                  value: selectedWorkspace,
                  items: options.map((option) {
                    return DropdownMenuItem<String>(
                      value: option,
                      child: Text(option),
                    );
                  }).toList(),
                  onChanged: (value) {
                    selectedWorkspace = value;
                  },
                ),
              TextField(
                controller: newWorkspaceController,
                decoration: const InputDecoration(hintText: 'Nuevo workspace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (newWorkspaceController.text.isNotEmpty) {
                  selectedWorkspace = newWorkspaceController.text;
                  options.add(newWorkspaceController.text);
                }

                if (selectedWorkspace != null) {
                  await file.writeAsString('$selectedWorkspace\n${options.join('\n')}');
                  Navigator.of(context).pop();
                  _showRestartMessage(context);
                }
              },
              child: const Text('Enviar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showScheduleDialog(BuildContext context) async {
    TimeOfDay startTime = START_SCHEDULE;
    TimeOfDay endTime = END_SCHEDULE;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Configuración de Horario'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Hora de inicio'),
                trailing: Text('${startTime.format(context)}'),
                onTap: () async {
                  final pickedTime = await showTimePicker(context: context, initialTime: startTime);
                  if (pickedTime != null) {
                    startTime = pickedTime;
                  }
                },
              ),
              ListTile(
                title: const Text('Hora de fin'),
                trailing: Text('${endTime.format(context)}'),
                onTap: () async {
                  final pickedTime = await showTimePicker(context: context, initialTime: endTime);
                  if (pickedTime != null) {
                    endTime = pickedTime;
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                START_SCHEDULE = startTime;
                END_SCHEDULE = endTime;

                final file = File('schedule.txt');
                await file.writeAsString(
                  '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}\n'
                  '${endTime.hour.toString().padLeft(2, '0')}:${endTime.minute.toString().padLeft(2, '0')}',
                );

                Navigator.of(context).pop();
              },
              child: const Text('Guardar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  void _showRestartMessage(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Se requiere reinicio'),
          content: const Text('La aplicacion requiere reiniciar para aplicar los cambios'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                exit(0);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }
}
