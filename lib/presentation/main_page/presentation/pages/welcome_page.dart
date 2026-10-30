import 'package:flutter/material.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:provider/provider.dart';

/// First screen: what the platform does and a way into the guided manual.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  void _open(BuildContext context, String route, int menuIndex,
      {Object? arguments}) {
    Provider.of<SideMenuProvider>(context, listen: false)
        .changeOption(menuIndex);
    Navigator.of(context).pushNamed(route, arguments: arguments);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget card(IconData icon, String title, String text, VoidCallback onTap) =>
        SizedBox(
          width: 300,
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 32, color: theme.colorScheme.primary),
                    const SizedBox(height: 8),
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(text,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Programación de Operaciones',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'Estaciones → rutas → programa → algoritmos → dashboard y '
                'Gantt.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  card(
                    Icons.linear_scale,
                    'Tutorial: Flow Shop',
                    'Guiado paso a paso: 3 lotes, la misma ruta para todos.',
                    () => _open(context, '/manual', 4, arguments: 0),
                  ),
                  card(
                    Icons.hub_outlined,
                    'Tutorial: Flexible Job Shop',
                    'Guiado paso a paso: ejes y bridas, rutas distintas y '
                        'varias máquinas por estación.',
                    () => _open(context, '/manual', 4, arguments: 1),
                  ),
                  card(
                    Icons.functions,
                    'Notación teórica',
                    'α | β | γ, Mi, pij, rj, dj y las fórmulas de cada regla.',
                    () => _open(context, '/notacion', 5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
