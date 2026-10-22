// Every main page, built on a real (temporary) database with the demo data,
// at phone, tablet and laptop sizes: no layout may overflow.
//
// A RenderFlex overflow is reported through FlutterError.onError; each one
// is collected with the widget that caused it, so a failure names exactly
// which page, size and source line to fix.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:production_planning/dependency_injection.dart';
import 'package:production_planning/presentation/0_machines/bloc/machine_types_bloc/machine_types_bloc.dart';
import 'package:production_planning/presentation/0_machines/pages/machines_list_page.dart';
import 'package:production_planning/presentation/1_sequences/bloc/new_process_bloc/sequences_bloc.dart';
import 'package:production_planning/presentation/1_sequences/pages/sequences_page.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_bloc.dart';
import 'package:production_planning/presentation/2_orders/pages/algorithm_picker_page.dart';
import 'package:production_planning/presentation/2_orders/bloc/gantt_bloc/gantt_bloc.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_data_table_page.dart';
import 'package:production_planning/presentation/2_orders/pages/gantt_page.dart';
import 'package:production_planning/presentation/2_orders/pages/new_order_page.dart';
import 'package:production_planning/presentation/2_orders/pages/order_metrics_page.dart';
import 'package:production_planning/presentation/2_orders/pages/orders_page.dart';
import 'package:production_planning/presentation/main_page/presentation/pages/main_page.dart';
import 'package:production_planning/presentation/main_page/presentation/provider/side_menu_provider.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:provider/provider.dart';

class _FakePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final String path;
  _FakePathProvider(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

/// Window sizes, logical pixels.
const sizes = <String, Size>{
  'celular': Size(390, 844),
  'tablet vertical': Size(820, 1180),
  'tablet horizontal': Size(1180, 820),
  'portátil 1280x720': Size(1280, 720),
  'portátil 1366x768': Size(1366, 768),
};

late int orderId;
late int ruleCount;

/// Lets real database I/O (sqflite FFI) complete, then rebuilds.
Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
  for (int i = 0; i < rounds; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Builds [page] at every size and returns one line per overflow found.
Future<List<String>> overflowsOf(
  WidgetTester tester,
  String name,
  Widget Function() page, {
  Map<String, Size> at = sizes,
}) async {
  final found = <String>{};
  for (final entry in at.entries) {
    tester.view.physicalSize = entry.value;
    tester.view.devicePixelRatio = 1;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.toString();
      if (!text.contains('overflowed')) {
        previous?.call(details);
        return;
      }
      final where = RegExp(r'file:///\S+?\.dart:\d+:\d+')
              .firstMatch(text)
              ?.group(0)
              ?.replaceFirst(RegExp(r'^.*?/lib/'), 'lib/') ??
          '?';
      final what =
          RegExp(r'A RenderFlex overflowed by [\d.]+ pixels on the \w+')
                  .firstMatch(text)
                  ?.group(0) ??
              details.exceptionAsString().split('\n').first;
      found.add('$name · ${entry.key} · $what · $where');
    };
    try {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: page(),
      ));
      await settle(tester);
    } finally {
      FlutterError.onError = previous;
    }
    // Leave the page so its timers / blocs stop before the next size.
    await tester.pumpWidget(const SizedBox());
    await settle(tester, rounds: 2);
  }
  addTearDown(tester.view.reset);
  return found.toList();
}

void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pp_responsive_');
    PathProviderPlatform.instance = _FakePathProvider(dir.path);
    await initDependencies('responsive_test');
    final orders =
        (await GetIt.instance<OrdersService>().getOrders()).getOrElse(() => []);
    orderId = orders.first.orderId!;
    final env = (await GetIt.instance<OrdersService>()
            .getOrderEnvironment(orderId))
        .getOrElse(() => throw StateError('sin ambiente'));
    ruleCount = env.rules.length;
  });

  final pages = <String, Widget Function()>{
    'Inicio': () => ChangeNotifierProvider(
        create: (_) => SideMenuProvider(), child: MainPage()),
    'Máquinas': () => BlocProvider(
        create: (_) => GetIt.instance.get<MachineTypesBloc>(),
        child: MachinesListPage()),
    'Rutas de proceso': () => BlocProvider(
        create: (_) => GetIt.instance.get<SequencesBloc>(),
        child: const SequencesPage()),
    'Programas': () => const OrdersPage(),
    'Nuevo programa': () => BlocProvider(
        create: (_) => GetIt.instance.get<NewOrderBloc>(),
        child: const NewOrderPage(editOrderId: null)),
    'Editar programa': () => BlocProvider(
        create: (_) => GetIt.instance.get<NewOrderBloc>(),
        child: NewOrderPage(editOrderId: orderId)),
    'Seleccionar algoritmos': () => AlgorithmPickerPage(orderId: orderId),
    'Métricas': () => OrderMetrics(
        orderId: orderId,
        selectedRuleIndexes: List.generate(ruleCount, (i) => i)),
    // The Gantt and the task table as Métricas opens them: one GanttBloc
    // with the order and its first rule already selected.
    'Gantt': () => BlocProvider(
        create: (_) => GetIt.instance.get<GanttBloc>()
          ..assignOrderAndSelectRuleByIndex(orderId, 0),
        child: GanttPage(orderId: orderId, number: 1)),
    'Detalle de tareas': () => BlocProvider(
        create: (_) => GetIt.instance.get<GanttBloc>()
          ..assignOrderAndSelectRuleByIndex(orderId, 0),
        child: GanttDataTablePage(orderId: orderId)),
  };

  for (final entry in pages.entries) {
    testWidgets('${entry.key}: no overflow at any size', (tester) async {
      final found = await overflowsOf(tester, entry.key, entry.value);
      if (found.isNotEmpty) {
        // ignore: avoid_print
        print('OVERFLOWS:\n${found.join('\n')}');
      }
      expect(found, isEmpty);
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
