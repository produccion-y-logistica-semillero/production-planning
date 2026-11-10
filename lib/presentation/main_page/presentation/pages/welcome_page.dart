import 'package:flutter/material.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/shared/motion/motion.dart';
import 'package:production_planning/shared/tutorial/tutorial_tours.dart';
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
    // Cards lift on hover and enter in a short cascade.
    var cardIndex = 0;
    Widget card(IconData icon, String title, String text, VoidCallback onTap) =>
        FadeSlideIn.staggered(
          index: 2 + cardIndex++,
          child: SizedBox(
            width: 300,
            child: HoverLift(
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
              FadeSlideIn(
                child: Column(children: [
                  Text('Programación de Operaciones',
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Estaciones → rutas → programa → algoritmos → dashboard y '
                    'Gantt.',
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.center,
                children: [
                  // One card per example family, generated from the tours.
                  for (int i = 0; i < kTours.length; i++)
                    card(
                      kTours[i].icon,
                      'Ejemplo: ${kTours[i].category.toLowerCase()}',
                      'Guiado paso a paso, sirve para ${kTours[i].environments.length} '
                          'ambientes: ${kTours[i].environments.join(', ')}.',
                      () => _open(context, '/manual', 4, arguments: i),
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
