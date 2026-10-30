import 'package:flutter/material.dart';
import 'package:production_planning/shared/tutorial/tutorial_controller.dart';
import 'package:production_planning/shared/tutorial/tutorial_tours.dart';
import 'package:production_planning/shared/tutorial/tutorial_workspace.dart';

/// In-app user manual: two guided tours, game-style. The app lights up the
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
    const icons = [Icons.linear_scale, Icons.hub_outlined];
    const blurbs = [
      'Panadería: 3 lotes de pan, todos por Mezcla → Horno → Empaque. '
          'Configuración, estaciones, una ruta, fechas, tiempos, familias y '
          'alistamiento, reglas, algoritmo genético, métricas, dashboard, '
          'Gantt y notación.',
      'Taller: ejes y bridas con rutas distintas y estaciones con 2 '
          'máquinas. Descansos y mantenimientos, fechas automáticas, '
          'tiempos por máquina, estado inicial, reglas compuestas, tu propia '
          'secuencia, Gantt por trabajo y gestión de programas.',
    ];
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
            'Tutoriales guiados: la plataforma te dice qué tocar en cada '
            'momento y avanza cuando lo haces. Se trabaja en un espacio de '
            'prueba ("Tutorial"); tus datos reales no se tocan y vuelven al '
            'terminar o al salir.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < kTours.length; i++)
            _TourCard(
              tour: kTours[i],
              icon: icons[i],
              blurb: blurbs[i],
              highlighted: i == initialCase,
            ),
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
        ],
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  final TutorialTour tour;
  final IconData icon;
  final String blurb;
  final bool highlighted;

  const _TourCard({
    required this.tour,
    required this.icon,
    required this.blurb,
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
                Icon(icon, size: 32, color: theme.colorScheme.primary),
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
            Text(blurb),
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
