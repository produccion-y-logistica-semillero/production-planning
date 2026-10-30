import 'package:flutter/material.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:provider/provider.dart';

/// In-app user manual: two guided use cases, step by step and with little
/// text, that build a production program from scratch — one Flow Shop and
/// one Flexible Job Shop. Every step can open its screen directly.
class ManualPage extends StatelessWidget {
  /// Tab to open first (0: Flow Shop, 1: Flexible Job Shop).
  final int initialCase;

  const ManualPage({super.key, this.initialCase = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialCase.clamp(0, 1),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Manual de usuario'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.linear_scale), text: 'Caso 1 · Flow Shop'),
              Tab(
                  icon: Icon(Icons.hub_outlined),
                  text: 'Caso 2 · Flexible Job Shop'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _GuidedCase(intro: _flowShopIntro, steps: _flowShopSteps),
            _GuidedCase(intro: _jobShopIntro, steps: _jobShopSteps),
          ],
        ),
      ),
    );
  }
}

/// Screens a step can open: route in the main navigator and side-menu item.
enum _Screen {
  stations('/machines', 1, 'Estaciones de Trabajo', Icons.settings),
  routes('/sequences', 2, 'Rutas de Proceso', Icons.work),
  programs('/orders', 3, 'Programas de produccion', Icons.schedule_send_sharp);

  final String route;
  final int menuIndex;
  final String menuLabel;
  final IconData icon;
  const _Screen(this.route, this.menuIndex, this.menuLabel, this.icon);
}

/// One line of a step: what to do, with the button or field to use.
class _Do {
  final IconData icon;
  final String text;
  const _Do(this.icon, this.text);
}

class _Step {
  final String title;
  final _Screen screen;
  final List<_Do> actions;

  /// Example data to type, shown as chips.
  final List<String> data;

  /// What the user should see when the step is done.
  final String check;

  const _Step({
    required this.title,
    required this.screen,
    required this.actions,
    this.data = const [],
    required this.check,
  });
}

class _Intro {
  final String goal;
  final String example;
  final IconData icon;
  const _Intro(this.goal, this.example, this.icon);
}

// ── Caso 1: Flow Shop ───────────────────────────────────────────────────────

const _flowShopIntro = _Intro(
  'Programar 3 lotes de pan que pasan todos por las mismas estaciones, '
      'en el mismo orden.',
  'Panadería · Mezclado → Horneado → Empaque · 1 máquina por estación',
  Icons.bakery_dining_outlined,
);

const _flowShopSteps = [
  _Step(
    title: 'Crear las 3 estaciones',
    screen: _Screen.stations,
    actions: [
      _Do(Icons.add_circle_outline, 'Pulse "Agregar estacion de trabajo".'),
      _Do(Icons.edit_outlined, 'Escriba el nombre y pulse "Agregar".'),
      _Do(Icons.repeat, 'Repita para las otras dos.'),
    ],
    data: ['Mezclado', 'Horneado', 'Empaque'],
    check: 'Ve las 3 estaciones en la lista.',
  ),
  _Step(
    title: 'Agregar una máquina a cada estación',
    screen: _Screen.stations,
    actions: [
      _Do(Icons.add, 'En cada estación pulse + (agregar máquina).'),
      _Do(Icons.badge_outlined, 'Nombre de la máquina y cantidad: 1.'),
      _Do(Icons.event, 'Fecha de inicio: "Ahora".'),
      _Do(Icons.free_breakfast_outlined,
          'Descanso: deje "No aplica descanso automático".'),
    ],
    data: ['Mezcladora', 'Horno', 'Empacadora'],
    check: 'Cada estación muestra 1 máquina.',
  ),
  _Step(
    title: 'Crear la ruta de proceso',
    screen: _Screen.routes,
    actions: [
      _Do(Icons.touch_app_outlined,
          'Haga clic en las estaciones de la izquierda, en orden.'),
      _Do(Icons.trending_flat,
          'Modo "Conectar": clic en origen y luego en destino.'),
      _Do(Icons.save_outlined, 'Escriba el nombre y pulse "Guardar ruta".'),
    ],
    data: ['Pan blanco', 'Mezclado → Horneado → Empaque'],
    check: 'La ruta aparece en la lista con 3 estaciones.',
  ),
  _Step(
    title: 'Crear el programa de producción',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.add, 'Pulse "Nuevo Programa de Producción".'),
      _Do(Icons.playlist_add, 'Pulse "Agregar Job" tres veces.'),
      _Do(Icons.account_tree_outlined, 'En cada job elija la ruta "Pan blanco".'),
      _Do(Icons.calendar_today,
          'Fechas de disponibilidad (rj) y de entrega (dj): fecha y luego la '
          'hora escrita (HH:mm).'),
      _Do(Icons.timer_outlined,
          'Tiempo de proceso (pij) de cada estación, en el formato elegido en '
          '"Formato de tiempos".'),
    ],
    data: [
      'Lote 1 · entrega hoy 12:00 · 00:30 / 01:00 / 00:15',
      'Lote 2 · entrega hoy 11:00 · 00:20 / 00:45 / 00:10',
      'Lote 3 · entrega hoy 14:00 · 00:40 / 00:50 / 00:20',
    ],
    check: 'Los 3 jobs tienen ruta, fechas y tiempos.',
  ),
  _Step(
    title: 'Opcional: tiempos de alistamiento',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.grid_on, 'Pulse "Definir matriz de tiempos de alistamiento".'),
      _Do(Icons.abc, 'Asigne a cada job su estado (familia A-J).'),
      _Do(Icons.swap_horiz,
          'Escriba el tiempo de pasar de un estado a otro (sjk).'),
      _Do(Icons.save_outlined, 'Pulse "Guardar".'),
    ],
    data: ['Horno: A → B = 15 min', 'Horno: B → A = 10 min'],
    check: 'El programa aparece en la lista con Ambiente: FLOW SHOP.',
  ),
  _Step(
    title: 'Elegir los algoritmos',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.play_arrow, 'En la tarjeta del programa pulse "programar".'),
      _Do(Icons.check_box_outlined, 'Marque EDD, SPT, WSPT y GENETICS.'),
      _Do(Icons.tune,
          'En GENETICS pulse ajustes y elija la función objetivo (ej. '
          'Tardanza total).'),
      _Do(Icons.low_priority,
          'Opcional: "Secuencia del usuario" → Definir, ordene los lotes.'),
      _Do(Icons.calculate, 'Pulse "Calcular".'),
    ],
    check: 'Se abre la pantalla de métricas.',
  ),
  _Step(
    title: 'Comparar en el dashboard',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.dashboard_outlined, 'Abra la pestaña "Dashboard".'),
      _Do(Icons.emoji_events_outlined,
          'La fila "Recomendado" es la de mejor puesto promedio.'),
      _Do(Icons.filter_alt_outlined,
          'Active o quite indicadores para el ranking (ej. Anticipo total).'),
    ],
    check: 'Sabe qué algoritmo conviene y por qué.',
  ),
  _Step(
    title: 'Ver el diagrama de Gantt',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.bar_chart, 'En la fila del algoritmo pulse "Ver diagrama de Gantt".'),
      _Do(Icons.swap_vert, 'Cambie la vista por máquina o por trabajo.'),
      _Do(Icons.table_rows_outlined,
          '"Ver detalle de tareas" muestra inicio y fin de cada operación.'),
    ],
    check: 'Ve los 3 lotes pasando por Mezclado, Horneado y Empaque.',
  ),
];

// ── Caso 2: Flexible Job Shop ───────────────────────────────────────────────

const _jobShopIntro = _Intro(
  'Programar 4 piezas con rutas distintas en estaciones que tienen varias '
      'máquinas iguales.',
  'Taller · Corte (2 máq.) · Torno (2 máq.) · Pintura (1 máq.)',
  Icons.precision_manufacturing_outlined,
);

const _jobShopSteps = [
  _Step(
    title: 'Crear las 3 estaciones',
    screen: _Screen.stations,
    actions: [
      _Do(Icons.add_circle_outline, 'Pulse "Agregar estacion de trabajo".'),
      _Do(Icons.edit_outlined, 'Escriba el nombre y pulse "Agregar".'),
    ],
    data: ['Corte', 'Torno', 'Pintura'],
    check: 'Ve las 3 estaciones en la lista.',
  ),
  _Step(
    title: 'Agregar varias máquinas por estación',
    screen: _Screen.stations,
    actions: [
      _Do(Icons.add, 'En Corte pulse + y ponga cantidad: 2.'),
      _Do(Icons.add, 'En Torno pulse + y ponga cantidad: 2.'),
      _Do(Icons.add, 'En Pintura pulse + y ponga cantidad: 1.'),
      _Do(Icons.build_outlined,
          'Opcional: "Agregar Mantenimiento" (día, hora HH:mm, duración).'),
    ],
    data: ['Corte 1, Corte 2', 'Torno 1, Torno 2', 'Cabina'],
    check: 'Corte y Torno muestran 2 máquinas cada una.',
  ),
  _Step(
    title: 'Crear dos rutas distintas',
    screen: _Screen.routes,
    actions: [
      _Do(Icons.touch_app_outlined, 'Agregue las estaciones de la ruta.'),
      _Do(Icons.trending_flat, 'Conecte en el orden de la ruta.'),
      _Do(Icons.save_outlined, 'Guarde y repita con la segunda ruta.'),
    ],
    data: ['Eje: Corte → Torno → Pintura', 'Brida: Torno → Corte → Pintura'],
    check: 'Hay 2 rutas que recorren las estaciones en distinto orden.',
  ),
  _Step(
    title: 'Crear el programa con 4 piezas',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.add, 'Pulse "Nuevo Programa de Producción".'),
      _Do(Icons.playlist_add, 'Agregue 4 jobs: 2 con "Eje" y 2 con "Brida".'),
      _Do(Icons.calendar_today, 'Disponibilidad (rj), entrega (dj) y prioridad (wj).'),
      _Do(Icons.timer_outlined,
          'Tiempos por máquina: cada máquina de la estación guarda el suyo '
          '(cambie de máquina para editarlo).'),
      _Do(Icons.content_copy, '"Duplicar job" copia un job para ir más rápido.'),
    ],
    data: [
      'Eje A · prioridad 2',
      'Eje B · prioridad 1',
      'Brida A · prioridad 3',
      'Brida B · prioridad 1',
    ],
    check: 'El programa aparece con Ambiente: FLEXIBLE JOB SHOP.',
  ),
  _Step(
    title: 'Elegir los algoritmos',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.play_arrow, 'Pulse "programar".'),
      _Do(Icons.menu_book_outlined, '"Guía de reglas" explica cada una.'),
      _Do(Icons.check_box_outlined,
          'Marque MS, ATCS, PRIORIDAD_COMPUESTA y GENETICS.'),
      _Do(Icons.tune,
          'En GENETICS ajuste población, generaciones, mutación y función '
          'objetivo.'),
      _Do(Icons.calculate, 'Pulse "Calcular".'),
    ],
    check: 'Se abre la pantalla de métricas.',
  ),
  _Step(
    title: 'Comparar y elegir',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.table_rows_outlined,
          '"Tabla": verde es el mejor valor de cada columna, rojo el peor.'),
      _Do(Icons.dashboard_outlined, '"Dashboard": ranking y recomendado.'),
    ],
    check: 'Identifica el mejor algoritmo para su objetivo.',
  ),
  _Step(
    title: 'Revisar el Gantt por máquina',
    screen: _Screen.programs,
    actions: [
      _Do(Icons.bar_chart, 'Pulse "Ver diagrama de Gantt".'),
      _Do(Icons.compare_arrows,
          'Note cómo se reparten las piezas entre Corte 1 y Corte 2.'),
      _Do(Icons.functions,
          'Active "Notación teórica" en el menú para ver α | β | γ: FJc | rj, '
          'sjk, prmp, brkdwn, prec | γ.'),
    ],
    check: 'Ve las 4 piezas en las 5 máquinas, cada una con su ruta.',
  ),
];

// ── Widgets ─────────────────────────────────────────────────────────────────

class _GuidedCase extends StatefulWidget {
  final _Intro intro;
  final List<_Step> steps;
  const _GuidedCase({required this.intro, required this.steps});

  @override
  State<_GuidedCase> createState() => _GuidedCaseState();
}

class _GuidedCaseState extends State<_GuidedCase>
    with AutomaticKeepAliveClientMixin {
  int _current = 0;

  @override
  bool get wantKeepAlive => true;

  void _open(_Screen screen) {
    Provider.of<SideMenuProvider>(context, listen: false)
        .changeOption(screen.menuIndex);
    // Pushed over the manual, so "atrás" returns to this step.
    Navigator.of(context).pushNamed(screen.route);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final steps = widget.steps;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: theme.colorScheme.primaryContainer.withOpacity(0.4),
          elevation: 0,
          child: ListTile(
            leading: Icon(widget.intro.icon,
                size: 36, color: theme.colorScheme.primary),
            title: Text(widget.intro.goal,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(widget.intro.example),
          ),
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (_current + 1) / steps.length,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text('Paso ${_current + 1} de ${steps.length}',
              style: theme.textTheme.bodySmall),
        ),
        Stepper(
          physics: const NeverScrollableScrollPhysics(),
          currentStep: _current,
          onStepTapped: (i) => setState(() => _current = i),
          controlsBuilder: (context, details) {
            final step = steps[details.stepIndex];
            final last = details.stepIndex == steps.length - 1;
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _open(step.screen),
                    icon: Icon(step.screen.icon),
                    label: Text('Ir a "${step.screen.menuLabel}"'),
                  ),
                  if (!last)
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _current++),
                      icon: const Icon(Icons.check),
                      label: const Text('Listo, siguiente'),
                    ),
                  if (details.stepIndex > 0)
                    TextButton(
                      onPressed: () => setState(() => _current--),
                      child: const Text('Anterior'),
                    ),
                ],
              ),
            );
          },
          steps: [
            for (int i = 0; i < steps.length; i++)
              Step(
                isActive: i <= _current,
                state: i < _current ? StepState.complete : StepState.indexed,
                title: Text(steps[i].title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(steps[i].screen.menuLabel),
                content: _StepBody(step: steps[i]),
              ),
          ],
        ),
      ],
    );
  }
}

class _StepBody extends StatelessWidget {
  final _Step step;
  const _StepBody({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in step.actions)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(a.icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(a.text)),
              ],
            ),
          ),
        if (step.data.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final d in step.data)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.keyboard_outlined, size: 16),
                  label: Text(d),
                ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.task_alt, size: 18, color: theme.colorScheme.tertiary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(step.check,
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ],
        ),
      ],
    );
  }
}
