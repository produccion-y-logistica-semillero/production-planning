import 'package:production_planning/repositories/interfaces/machine_repository.dart';

/// Name of each work station (machine type) in [typeIds], so the planning
/// output can say which station every machine belongs to — needed for the
/// per-station idle time and tardiness. A station whose name cannot be read
/// is shown as "Estación <id>".
Future<Map<int, String>> stationNamesById(
  MachineRepository repository,
  Iterable<int?> typeIds,
) async {
  final names = <int, String>{};
  for (final id in typeIds.whereType<int>().toSet()) {
    final result = await repository.getMachineTypeName(id);
    names[id] = result.fold((_) => 'Estación $id', (name) => name);
  }
  return names;
}
