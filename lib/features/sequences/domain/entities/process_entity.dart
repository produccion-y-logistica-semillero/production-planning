import 'package:production_planning/features/machines/domain/entities/machine_type_entity.dart';

class ProcessEntity {
  final List<MachineTypeEntity> machines;
  final List<Duration> durations;

  ProcessEntity({required this.machines, required this.durations});

  @override
  String toString() {
    final machinesString = machines.map((m) => m.toString()).join(', ');
    final durationsString = durations.map((d) => '${d.inHours}h').join(', ');

    return 'ProcessEntity(machines: [$machinesString], durations: [$durationsString])';
  }
}
