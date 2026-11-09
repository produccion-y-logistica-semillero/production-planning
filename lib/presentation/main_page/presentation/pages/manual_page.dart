import 'package:flutter/material.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/tutorial/tutorial_tours.dart';
import 'package:production_planning/shared/tutorial/tutorial_workspace.dart';

/// In-app user manual: two guided examples (one machine per station /
/// several machines per station), game-style. The app lights up the
/// exact button or field to use, says what to do and waits until the user
/// does it, building a real program (in the "Tutorial" workspace) and
/// covering everything the platform can do.
class ManualPage extends StatelessWidget {
  /// Tour to highlight first (0: Flow Shop, 1: Flexible Job Shop).
  final int initialCase;

  const ManualPage({super.key, this.initialCase = 0});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Tours are examples of a family; group the cards by it.
    final categories = <String>[];
    for (final t in kTours) {
      if (!categories.contains(t.category)) categories.add(t.category);
    }
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Manual de usuario',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Ejemplos guiados: la plataforma te dice qué tocar en cada '
            'momento y avanza cuando lo haces. Se trabaja en un espacio de '
            'prueba ("Tutorial"); tus datos reales no se tocan y vuelven al '
            'terminar o al salir.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer.withValues(alpha: .4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: theme.colorScheme.secondary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'No hay un tutorial por ambiente: la plataforma detecta '
                    'sola el ambiente (máquina única, paralelas, Flow Shop, '
                    'Job Shop, Open Shop, Recurrente y sus variantes '
                    'flexibles) a partir de tus rutas y de cuántas máquinas '
                    'tiene cada estación. Por eso basta con dos ejemplos: '
                    'uno con una máquina por estación y otro con varias. Los '
                    'pasos son los mismos en todos los ambientes de la '
                    'familia.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          for (final category in categories) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(category,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            for (int i = 0; i < kTours.length; i++)
              if (kTours[i].category == category)
                _TourCard(
                  tour: kTours[i],
                  highlighted: i == initialCase,
                ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.lightbulb_outline,
                  size: 18, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                    'En cualquier paso puedes usar "Atrás", "Saltar" o '
                    '"Salir".'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Trabajar el mismo workspace en otro equipo',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerLow,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Abre "Configuración" › "Workspace". En el equipo donde '
                'trabajaste pulsa "Exportar…" y guarda el archivo .ppws; '
                'envíalo como quieras (correo, USB, nube). En el otro equipo '
                'pulsa "Importar desde archivo…" y elígelo, aunque esté en '
                'Descargas: la aplicación guarda una copia propia (el archivo '
                'oficial, cuya ubicación te muestra) y sigues trabajando allí '
                'con los mismos datos, horario y formato de tiempos. Para '
                'volver, exporta en ese equipo e importa en el primero '
                'eligiendo "Reemplazar".',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  final TutorialTour tour;
  final bool highlighted;

  const _TourCard({
    required this.tour,
    required this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: highlighted ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: highlighted
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tour.icon, size: 32, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(tour.title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${tour.steps.length} pasos'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(tour.blurb),
            if (tour.environments.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Sirve para estos ambientes:',
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in tour.environments)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.factory_outlined, size: 16),
                      label: Text(e),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in tour.chapters)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.flag_outlined, size: 16),
                    label: Text(c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => startGuidedTour(tour),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Comenzar tutorial'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
