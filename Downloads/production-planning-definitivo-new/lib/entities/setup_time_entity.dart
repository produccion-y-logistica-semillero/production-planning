class SetupTimeEntity {
  int? id;
  final int machineId;
  final int?
      fromSequenceId; // null significa "desde cualquier secuencia" o inicio
  final int toSequenceId;
  final Duration setupDuration;

  SetupTimeEntity({
    this.id,
    required this.machineId,
    this.fromSequenceId,
    required this.toSequenceId,
    required this.setupDuration,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'machine_id': machineId,
      'from_sequence_id': fromSequenceId,
      'to_sequence_id': toSequenceId,
      'setup_duration_minutes': setupDuration.inMinutes,
    };
  }

  factory SetupTimeEntity.fromMap(Map<String, dynamic> map) {
    return SetupTimeEntity(
      id: map['id'],
      machineId: map['machine_id'],
      fromSequenceId: map['from_sequence_id'],
      toSequenceId: map['to_sequence_id'],
      setupDuration: Duration(minutes: map['setup_duration_minutes'] ?? 0),
    );
  }
}
