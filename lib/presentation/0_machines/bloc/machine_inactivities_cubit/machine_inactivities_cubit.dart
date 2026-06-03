import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_inactivity_entity.dart';
import 'package:production_planning/services/machines_service.dart';

import 'machine_inactivities_state.dart';

class MachineInactivitiesCubit extends Cubit<MachineInactivitiesState> {
  final MachinesService service;

  MachineInactivitiesCubit(this.service)
      : super(MachineInactivitiesState.initial());

  Future<void> initialize(MachineEntity machine) async {
    final id = machine.id;
    if (id == null) {
      emit(state.copyWith(
          errorMessage: 'No se pudo cargar la información de la máquina.'));
      return;
    }

    final initialScheduled =
        List<MachineInactivityEntity>.from(machine.scheduledInactivities)
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    var currentMachine = machine;
    final machineResponse = await service.getMachineById(id);
    machineResponse.fold((_) => null, (updatedMachine) {
      currentMachine = updatedMachine;
    });

    emit(state.copyWith(
      machineId: id,
      machineName: currentMachine.name,
      continueCapacity: currentMachine.continueCapacity,
      // Calculate rest duration from percentage (100% = 1 hour base)
      restTime:
          Duration(minutes: (60 * currentMachine.restPercentage / 100).round()),
      scheduled: List.unmodifiable(initialScheduled),
      isLoading: true,
      clearError: true,
      clearSuccess: true,
    ));

    final response = await service.getMachineInactivities(id);
    response.fold(
      (_) => emit(state.copyWith(
        isLoading: false,
        errorMessage: 'No se pudieron cargar las inactividades programadas.',
      )),
      (scheduled) {
        scheduled.sort((a, b) => a.startTime.compareTo(b.startTime));
        emit(state.copyWith(
          isLoading: false,
          scheduled: List.unmodifiable(scheduled),
          continueCapacity: currentMachine.continueCapacity,
          restTime:
              Duration(minutes: (60 * currentMachine.restPercentage / 100).round()),
        ));
      },
    );
  }

  void clearFeedback() {
    emit(state.copyWith(clearError: true, clearSuccess: true));
  }

  Future<void> saveAutomatic({
    required int continueCapacity,
    Duration? restTime,
  }) async {
    if (!state.hasMachine) return;

    emit(state.copyWith(
      isSavingAutomatic: true,
      clearError: true,
      clearSuccess: true,
    ));

    final response = await service.updateAutomaticInactivity(
      machineId: state.machineId,
      continueCapacity: continueCapacity,
      restTime: restTime,
    );

    response.fold(
      (_) => emit(state.copyWith(
        isSavingAutomatic: false,
        errorMessage: 'No se pudo actualizar la inactividad automática.',
      )),
      (_) => emit(state.copyWith(
        isSavingAutomatic: false,
        continueCapacity: continueCapacity,
        restTime: restTime,
        successMessage: 'Inactividad automática actualizada.',
      )),
    );
  }

  Future<void> addScheduled({
    required String name,
    required Set<Weekday> weekdays,
    required Duration startTime,
    required Duration duration,
  }) async {
    if (!state.hasMachine) return;

    emit(state.copyWith(
      isSavingScheduled: true,
      clearError: true,
      clearSuccess: true,
    ));

    final inactivity = MachineInactivityEntity(
      machineId: state.machineId,
      name: name,
      weekdays: weekdays,
      startTime: startTime,
      duration: duration,
    );

    final response = await service.addMachineInactivity(inactivity);

    response.fold(
      (_) => emit(state.copyWith(
        isSavingScheduled: false,
        errorMessage: 'No se pudo agregar la inactividad programada.',
      )),
      (added) {
        final updated = List<MachineInactivityEntity>.from(state.scheduled)
          ..add(added);
        updated.sort((a, b) => a.startTime.compareTo(b.startTime));
        emit(state.copyWith(
          isSavingScheduled: false,
          scheduled: List.unmodifiable(updated),
          successMessage: 'Inactividad programada agregada.',
        ));
      },
    );
  }

  Future<void> removeScheduled(int inactivityId) async {
    if (!state.hasMachine) return;

    emit(state.copyWith(
      isSavingScheduled: true,
      clearError: true,
      clearSuccess: true,
    ));

    final response = await service.deleteMachineInactivity(inactivityId);

    response.fold(
      (_) => emit(state.copyWith(
        isSavingScheduled: false,
        errorMessage: 'No se pudo eliminar la inactividad programada.',
      )),
      (_) {
        final updated = state.scheduled
            .where((item) => item.id != inactivityId)
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
        emit(state.copyWith(
          isSavingScheduled: false,
          scheduled: List.unmodifiable(updated),
          successMessage: 'Inactividad programada eliminada.',
        ));
      },
    );
  }
}
