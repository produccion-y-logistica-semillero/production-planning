// Search and filters of the production-program list. Pure: no widgets.

import 'package:production_planning/entities/order_entity.dart';

/// Lower-case and without accents, so "Panaderia" finds "Panadería".
String normalizeForSearch(String text) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final lower = text.toLowerCase();
  final buffer = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    buffer.write(i >= 0 ? to[i] : ch);
  }
  return buffer.toString();
}

/// Display name of a job, as the list shows it.
String jobDisplayName(OrderEntity order, int index) {
  final job = order.orderJobs![index];
  return job.jobName ?? 'Job ${job.jobId}';
}

/// Names of the routes (sequences) the jobs of [order] follow, without
/// repeats, in first-use order.
List<String> routeNamesOf(OrderEntity order) {
  final names = <String>[];
  for (final job in order.orderJobs ?? const []) {
    final name = job.sequence?.name;
    if (name != null && name.isNotEmpty && !names.contains(name)) {
      names.add(name);
    }
  }
  return names;
}

/// The orders that match every given criterion:
///  * [query]: part of a job name, of a route name, or the program number
///    ("12" or "#12"), ignoring case and accents;
///  * [environment]: exact environment name (null = any);
///  * [route]: exact route name (null = any).
List<OrderEntity> filterOrders(
  List<OrderEntity> orders,
  Map<int, String> environments, {
  String query = '',
  String? environment,
  String? route,
}) {
  final q = normalizeForSearch(query.trim());
  final number = int.tryParse(q.replaceFirst('#', ''));

  bool matchesQuery(OrderEntity order) {
    if (q.isEmpty) return true;
    if (number != null && order.orderId == number) return true;
    final jobs = order.orderJobs ?? const [];
    for (int i = 0; i < jobs.length; i++) {
      if (normalizeForSearch(jobDisplayName(order, i)).contains(q)) {
        return true;
      }
    }
    return routeNamesOf(order).any((r) => normalizeForSearch(r).contains(q));
  }

  return [
    for (final order in orders)
      if ((environment == null || environments[order.orderId] == environment) &&
          (route == null || routeNamesOf(order).contains(route)) &&
          matchesQuery(order))
        order,
  ];
}
