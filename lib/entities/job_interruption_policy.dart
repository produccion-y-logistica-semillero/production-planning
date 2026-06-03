/// Per-job settings for whether machine downtimes may pause (split) work.
class JobInterruptionPolicy {
  /// Descanso obligatorio tras capacidad continua de la máquina.
  final bool allowRestInterrupt;

  /// Eventos recurrentes configurados en inactividades de la máquina.
  final bool allowScheduledInterrupt;

  /// Horario de trabajo (cierre / apertura de tienda).
  final bool allowWorkHoursInterrupt;

  const JobInterruptionPolicy({
    this.allowRestInterrupt = false,
    this.allowScheduledInterrupt = true,
    this.allowWorkHoursInterrupt = true,
  });

  /// Matches legacy scheduler behavior before per-job policies existed.
  static const legacyDefault = JobInterruptionPolicy(
    allowRestInterrupt: true,
    allowScheduledInterrupt: true,
    allowWorkHoursInterrupt: true,
  );

  JobInterruptionPolicy copyWith({
    bool? allowRestInterrupt,
    bool? allowScheduledInterrupt,
    bool? allowWorkHoursInterrupt,
  }) {
    return JobInterruptionPolicy(
      allowRestInterrupt: allowRestInterrupt ?? this.allowRestInterrupt,
      allowScheduledInterrupt:
          allowScheduledInterrupt ?? this.allowScheduledInterrupt,
      allowWorkHoursInterrupt:
          allowWorkHoursInterrupt ?? this.allowWorkHoursInterrupt,
    );
  }

  Map<String, dynamic> toDatabaseMap(int jobId) => {
        'job_id': jobId,
        'allow_rest': allowRestInterrupt ? 1 : 0,
        'allow_scheduled': allowScheduledInterrupt ? 1 : 0,
        'allow_work_hours': allowWorkHoursInterrupt ? 1 : 0,
      };

  factory JobInterruptionPolicy.fromDatabaseMap(Map<String, dynamic> map) {
    return JobInterruptionPolicy(
      allowRestInterrupt: (map['allow_rest'] as int? ?? 0) == 1,
      allowScheduledInterrupt: (map['allow_scheduled'] as int? ?? 1) == 1,
      allowWorkHoursInterrupt: (map['allow_work_hours'] as int? ?? 1) == 1,
    );
  }
}
