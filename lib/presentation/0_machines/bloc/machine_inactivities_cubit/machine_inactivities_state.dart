import 'package:equatable/equatable.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';

class MachineInactivitiesState extends Equatable {
  final bool isLoading;
  final bool isSavingAutomatic;
  final bool isSavingScheduled;
  final String? errorMessage;
  final String? successMessage;
  final int machineId;
  final String machineName;
  final int continueCapacity;
  final Duration? restTime;
  final List<MachineInactivityEntity> scheduled;

  const MachineInactivitiesState({
    required this.isLoading,
    required this.isSavingAutomatic,
    required this.isSavingScheduled,
    required this.errorMessage,
    required this.successMessage,
    required this.machineId,
    required this.machineName,
    required this.continueCapacity,
    required this.restTime,
    required this.scheduled,
  });

  factory MachineInactivitiesState.initial() => const MachineInactivitiesState(
        isLoading: false,
        isSavingAutomatic: false,
        isSavingScheduled: false,
        errorMessage: null,
        successMessage: null,
        machineId: -1,
        machineName: '',
        continueCapacity: 0,
        restTime: null,
        scheduled: <MachineInactivityEntity>[],
      );

  MachineInactivitiesState copyWith({
    bool? isLoading,
    bool? isSavingAutomatic,
    bool? isSavingScheduled,
    String? errorMessage,
    String? successMessage,
    int? machineId,
    String? machineName,
    int? continueCapacity,
    Duration? restTime,
    List<MachineInactivityEntity>? scheduled,
    bool clearError = false,
    bool clearSuccess = false,
  }) {
    return MachineInactivitiesState(
      isLoading: isLoading ?? this.isLoading,
      isSavingAutomatic: isSavingAutomatic ?? this.isSavingAutomatic,
      isSavingScheduled: isSavingScheduled ?? this.isSavingScheduled,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccess ? null : (successMessage ?? this.successMessage),
      machineId: machineId ?? this.machineId,
      machineName: machineName ?? this.machineName,
      continueCapacity: continueCapacity ?? this.continueCapacity,
      restTime: restTime ?? this.restTime,
      scheduled: scheduled ?? this.scheduled,
    );
  }

  bool get hasMachine => machineId > 0;

  @override
  List<Object?> get props => [
        isLoading,
        isSavingAutomatic,
        isSavingScheduled,
        errorMessage,
        successMessage,
        machineId,
        machineName,
        continueCapacity,
        restTime,
        scheduled,
      ];
}
