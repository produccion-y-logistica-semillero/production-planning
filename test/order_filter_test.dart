// Search and filters of the production-program list.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/order_entity.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/presentation/2_orders/order_filter.dart';

JobEntity job(int id, String name, int routeId, String route) => JobEntity(
      id,
      SequenceEntity(routeId, const [], route, const []),
      name,
      DateTime(2026, 11, 1),
      1,
      DateTime(2026, 10, 15),
    );

OrderEntity order(int id, List<JobEntity> jobs) =>
    OrderEntity(id, DateTime(2026, 10, id), jobs);

void main() {
  final orders = [
    order(1, [job(1, 'Pan integral', 10, 'Panadería')]),
    order(2, [
      job(2, 'Lote 3', 20, 'Textil'),
      job(3, 'Pan blanco', 10, 'Panadería'),
    ]),
    order(12, [job(4, 'Camisa', 20, 'Textil')]),
  ];
  const environments = {1: 'FLOW SHOP', 2: 'JOB SHOP', 12: 'FLOW SHOP'};

  List<int?> ids(List<OrderEntity> r) => r.map((o) => o.orderId).toList();

  test('no criteria returns everything', () {
    expect(ids(filterOrders(orders, environments)), [1, 2, 12]);
  });

  test('search by job name ignores case and accents', () {
    expect(ids(filterOrders(orders, environments, query: 'PAN')), [1, 2]);
    expect(ids(filterOrders(orders, environments, query: 'lote')), [2]);
  });

  test('search also matches route names and the program number', () {
    expect(ids(filterOrders(orders, environments, query: 'panaderia')),
        [1, 2]);
    expect(ids(filterOrders(orders, environments, query: '#12')), [12]);
  });

  test('filter by environment', () {
    expect(ids(filterOrders(orders, environments, environment: 'FLOW SHOP')),
        [1, 12]);
  });

  test('filter by route', () {
    expect(ids(filterOrders(orders, environments, route: 'Textil')), [2, 12]);
  });

  test('criteria combine', () {
    expect(
      ids(filterOrders(orders, environments,
          query: 'pan', environment: 'JOB SHOP', route: 'Panadería')),
      [2],
    );
    expect(
      ids(filterOrders(orders, environments,
          query: 'camisa', environment: 'JOB SHOP')),
      isEmpty,
    );
  });

  test('route names are listed once, in first-use order', () {
    expect(routeNamesOf(orders[1]), ['Textil', 'Panadería']);
  });
}
