import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/presentation/2_orders/request_models/new_order_request_model.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/services/machines_service.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/services/sequences_service.dart';

class NewOrderBloc extends Cubit<NewOrderState> {
  final OrdersService orderService;
  final SequencesService seqService;
  final MachinesService machinesService;

  final Map<int, SequenceEntity> _sequenceCache = {};
  final Map<int, List<MachineEntity>> _machinesCache = {};

  NewOrderBloc(
    this.orderService,
    this.seqService,
    this.machinesService,
  ) : super(NewOrdersInitialState());

  // Several methods here (loadOrderForEdit, saveOrder, updateOrder, ...)
  // await a DB round trip before emitting. If the page that owns this bloc
  // is popped while one is in flight, BlocProvider closes it before the
  // callback runs, and a bare emit() then throws "Cannot emit new states
  // after calling close" — a widget-lifecycle race, not a data error.
  // Silently dropping the state once closed is the standard fix.
  @override
  void emit(NewOrderState state) {
    if (isClosed) return;
    super.emit(state);
  }

  // ─── Sequences ─────────────────────────────────────────────────────────────

  Future<void> retrieveSequences() async {
    final response = await seqService.getSequences();
    response.fold(
      (failure) => emit(NewOrdersFailureState()),
      (sequences) {
        emit(NewOrdersState(
          jobs: [],
          sequences: sequences
              .map((s) => Tuple2<int, String>(s.id!, s.name))
              .toList(),
        ));
      },
    );
  }

  // ─── Job ID helpers ────────────────────────────────────────────────────────

  /// Returns the next sequential job ID by finding the current maximum among
  /// all existing job `idController` values. Only present in file 9 — needed
  /// by both [addJob] and [duplicateJob].
  ///
  /// The field holds a free-text name, so most values will not parse as a
  /// number (a job called "Job 1" parses to nothing). When none of them do,
  /// fall back to the job count rather than to 0 — otherwise every job added
  /// to an order whose jobs have text names would be numbered "1" and collide
  /// with the previous one.
  int _getNextJobId(List<AddJobWidget> jobs) {
    final parsedIds = jobs
        .map((job) => int.tryParse(job.idController?.text ?? '') ?? 0)
        .where((id) => id > 0)
        .toList();
    if (parsedIds.isEmpty) return jobs.length + 1;
    final maxId = parsedIds.reduce((a, b) => a > b ? a : b);
    return maxId + 1;
  }

  // ─── Job CRUD ──────────────────────────────────────────────────────────────

  void addJob() {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);
      List<Tuple2<int, String>> sequences = currentState.sequences;

      int index = jobs.isNotEmpty
          ? jobs.map((job) => job.index).reduce((a, b) => a > b ? a : b)
          : 0;
      // Auto-assign a sequential ID so the field is never empty (file 9).
      final nextJobId = _getNextJobId(jobs);

      jobs.add(AddJobWidget(
        availableDate: null,
        dueDate: null,
        availableHour: null,
        dueHour: null,
        priorityController: TextEditingController(),
        idController: TextEditingController(text: '$nextJobId'),
        index: index + 1,
        sequences: sequences,
      ));

      emit(currentState.copyWith(jobs: jobs));
    }
  }

  void removeJob(int index) {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);

      jobs.removeWhere((widget) => widget.index == index);
      emit(currentState.copyWith(jobs: jobs));
    }
  }

  /// Clones an existing job (identified by [index]) with all its current field
  /// values, assigning a new sequential index and ID. Only present in file 9.
  void duplicateJob(int index) {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);
      List<Tuple2<int, String>> sequences = currentState.sequences;

      final sourceJob = jobs.firstWhere((job) => job.index == index);
      final sourceState = sourceJob.stateKey.currentState;

      int nextIndex = jobs.isNotEmpty
          ? jobs.map((job) => job.index).reduce((a, b) => a > b ? a : b) + 1
          : 1;
      final nextJobId = _getNextJobId(jobs);

      // Deep-copy the source job's live parameters (times, A-J states,
      // preemption) into the clone's initial* maps. Without this the clone
      // started blank and, on save, recomputed its baseline from whatever
      // machine type it shared with another job. Deep copies so editing the
      // clone can never mutate the source job's own maps.
      final Map<int, String>? clonedFinalStates =
          sourceState?.getMachineFinalStates();
      final Map<int, int>? clonedPreemptionMatrix =
          sourceState?.getPreemptionMatrix();
      final clonedTaskMachineTimes = sourceState
          ?.getExplicitTaskMachineMinutes()
          .map((taskId, byMachine) => MapEntry(
                taskId,
                byMachine.map((machineId, times) =>
                    MapEntry(machineId, Map<String, int>.from(times))),
              ));

      jobs.add(AddJobWidget(
        availableDate: sourceJob.availableDate,
        dueDate: sourceJob.dueDate,
        availableHour: sourceJob.availableHour,
        dueHour: sourceJob.dueHour,
        priorityController: TextEditingController(
          text: sourceJob.priorityController?.text ?? '',
        ),
        idController: TextEditingController(text: '$nextJobId'),
        index: nextIndex,
        sequences: sequences,
        selectedSequence: sourceJob.selectedSequence,
        initialMachineFinalStates: clonedFinalStates == null
            ? null
            : Map<int, String>.from(clonedFinalStates),
        initialPreemptionMatrix: clonedPreemptionMatrix == null
            ? null
            : Map<int, int>.from(clonedPreemptionMatrix),
        initialTaskMachineTimes: clonedTaskMachineTimes,
      ));

      // copyWith — not a bare NewOrdersState — so the order-level state
      // (setupTimeMatrix, dateMode, leadTimeDays, automatic hours) survives
      // the duplicate. Losing setupTimeMatrix here meant a save right after
      // duplicating a job called updateSetupMatrix(orderId, null), which
      // deleted the whole order's setup matrix.
      emit(currentState.copyWith(jobs: jobs));
    }
  }

  // ─── Sequence / machine helpers ────────────────────────────────────────────

  Future<SequenceEntity?> getSequenceDetails(int sequenceId) async {
    if (_sequenceCache.containsKey(sequenceId)) {
      return _sequenceCache[sequenceId];
    }
    final response = await seqService.getFullSequence(sequenceId);
    return response.fold(
      (failure) => null,
      (sequence) {
        if (sequence != null) {
          _sequenceCache[sequenceId] = sequence;
        }
        return sequence;
      },
    );
  }

  Future<List<MachineEntity>> getMachinesForType(int machineTypeId) async {
    if (_machinesCache.containsKey(machineTypeId)) {
      return _machinesCache[machineTypeId]!;
    }
    final response = await machinesService.getMachines(machineTypeId);
    return response.fold(
      (failure) => <MachineEntity>[],
      (machines) {
        _machinesCache[machineTypeId] = machines;
        return machines;
      },
    );
  }

  // TODO: Implementar updateMachineTimes en MachinesService
  // Future<void> updateMachineTimes({
  //   required int machineId,
  //   required MachineStandardTimes times,
  //   int? machineTypeId,
  // }) async {
  //   await machinesService.updateMachineTimes(
  //     machineId: machineId,
  //     times: times,
  //     machineTypeId: machineTypeId,
  //   );
  // }

  void setSetupTimeMatrix(
      Map<String, Map<String, Map<String, int>>> matrix) {
    if (state is NewOrdersState) {
      emit((state as NewOrdersState).copyWith(setupTimeMatrix: matrix));
    }
  }

  void setMachineInitialStates(Map<String, String> states) {
    if (state is NewOrdersState) {
      emit((state as NewOrdersState).copyWith(machineInitialStates: states));
    }
  }

  void setDateMode(DateRegistrationMode mode) {
    if (state is NewOrdersState) {
      emit((state as NewOrdersState).copyWith(dateMode: mode));
    }
  }

  void setLeadTimeDays(int days) {
    if (state is NewOrdersState && days > 0) {
      emit((state as NewOrdersState).copyWith(leadTimeDays: days));
    }
  }

  /// Order-wide default hour for automatic mode. Pass `null` to clear it
  /// (falls back to the current time at save, same as leaving it unset).
  void setAutomaticStartHour(TimeOfDay? tod) {
    if (state is NewOrdersState) {
      emit((state as NewOrdersState)
          .copyWith(automaticStartHour: Optional(tod)));
    }
  }

  void setAutomaticDueHour(TimeOfDay? tod) {
    if (state is NewOrdersState) {
      emit((state as NewOrdersState)
          .copyWith(automaticDueHour: Optional(tod)));
    }
  }

  // ─── Shared task-machine time builder ─────────────────────────────────────

  /// Builds the `taskMachineTimes` map from a job widget's current state.
  /// Shared by both [saveOrder] and [updateOrder] to avoid duplication.
  Map<int, Map<int, Map<String, int>>>? _buildTaskMachineTimes(
    AddJobWidget wid,
  ) {
    final widgetState = wid.stateKey.currentState;
    if (widgetState == null) {
      print('NewOrderBloc: widgetState is NULL for job index=${wid.index}');
      return null;
    }

    final explicit = widgetState.getExplicitTaskMachineMinutes();
    if (explicit.isNotEmpty) {
      print(
          'NewOrderBloc: using explicit taskMachineTimes for job index=${wid.index} -> $explicit');
      return explicit;
    }

    final selectedMachines = widgetState.getSelectedMachines();
    final stationTimes = widgetState.getStationProcessingMinutes();
    print(
        'NewOrderBloc: widgetState for job index=${wid.index} '
        'selectedMachines=$selectedMachines stationTimes=$stationTimes');

    final taskMachineTimes = <int, Map<int, Map<String, int>>>{};
    final tasks = widgetState.getSequenceTasks();
    if (tasks != null && tasks.isNotEmpty) {
      for (final task in tasks) {
        final machineType = task.machineTypeId;
        final machineId = selectedMachines[machineType];
        final minutes = stationTimes[machineType];
        if (machineId != null && minutes != null) {
          taskMachineTimes[task.id!] = {
            machineId: {
              'processing': minutes,
              'preparation': 0,
              'rest': 0,
            }
          };
        } else {
          print(
              'NewOrderBloc: missing mapping for task ${task.id} -> '
              'machineType=$machineType machineId=$machineId minutes=$minutes');
        }
      }
    } else {
      print(
          'NewOrderBloc: no tasks for job index=${wid.index} '
          '(sequence not selected?)');
    }
    return taskMachineTimes;
  }

  // ─── Persist order ─────────────────────────────────────────────────────────

  /// Resolves the (availableDate, dueDate) pair for [wid] according to the
  /// order's current [DateRegistrationMode]. In manual mode this simply
  /// returns whatever the user picked in the form. In automatic mode the
  /// user-picked dates (if any) are ignored: availableDate's day is "today"
  /// and dueDate's day is "today" plus the configured lead time — but the
  /// HOUR of each comes from, in order of precedence: the per-job override
  /// (wid.automaticStartHour / wid.automaticDueHour), then the order-wide
  /// default (currentState.automaticStartHour / automaticDueHour), then the
  /// current time when none of those were set.
  Tuple2<DateTime, DateTime> _resolveDates(
      NewOrdersState currentState, AddJobWidget wid) {
    if (currentState.dateMode == DateRegistrationMode.automatic) {
      final now = DateTime.now();
      final startTod = wid.automaticStartHour ??
          currentState.automaticStartHour ??
          TimeOfDay.fromDateTime(now);
      final dueTod = wid.automaticDueHour ??
          currentState.automaticDueHour ??
          TimeOfDay.fromDateTime(now);

      final availableDate = DateTime(
          now.year, now.month, now.day, startTod.hour, startTod.minute);
      final dueBase =
          availableDate.add(Duration(days: currentState.leadTimeDays));
      final dueDate = DateTime(
          dueBase.year, dueBase.month, dueBase.day, dueTod.hour, dueTod.minute);

      return Tuple2(availableDate, dueDate);
    }
    return Tuple2(wid.availableDate!, wid.dueDate!);
  }

  Future<void> saveOrder() async {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      final List<NewOrderRequestModel> jobs =
          currentState.jobs.map<NewOrderRequestModel>((wid) {
        final taskMachineTimes = _buildTaskMachineTimes(wid);
        final dates = _resolveDates(currentState, wid);

        return NewOrderRequestModel(
          wid.selectedSequence!,
          dates.value2,
          dates.value1,
          int.parse(wid.priorityController!.text),
          wid.idController!.text.isNotEmpty ? wid.idController!.text : null,
          preemptionMatrix:
              wid.stateKey.currentState?.getPreemptionMatrix(),
          taskMachineTimesMinutes: taskMachineTimes,
          machineFinalStates:
              wid.stateKey.currentState?.getMachineFinalStates(),
        );
      }).toList();

      // Diagnostic: print taskMachineTimesMinutes for each job before saving.
      for (var j in jobs) {
        print(
            'NewOrderBloc: job sequence=${j.sequenceId} '
            'taskMachineTimes=${j.taskMachineTimesMinutes}');
      }

      late Either<Failure, bool> response;
      try {
        response = await orderService.addOrder(
          jobs,
          setupTimeMatrix: currentState.setupTimeMatrix,
          machineInitialStates: currentState.machineInitialStates,
        );
      } catch (error, stack) {
        print('NewOrderBloc.saveOrder error: ${error.toString()}');
        print(stack.toString());
        response = Left(LocalStorageFailure());
      }

      response.fold(
        (failure) => emit(NewOrdersState(
          jobs: currentState.jobs,
          sequences: currentState.sequences,
          justSaved: false,
        )),
        (success) => emit(NewOrdersState(
          jobs: [],
          sequences: currentState.sequences,
          justSaved: true,
        )),
      );
    }
  }

  /// Updates an existing order identified by [orderId]. Only present in
  /// file 9 — uses the same task-machine-time logic as [saveOrder].
  Future<void> updateOrder(int orderId) async {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      final List<NewOrderRequestModel> jobs =
          currentState.jobs.map<NewOrderRequestModel>((wid) {
        final taskMachineTimes = _buildTaskMachineTimes(wid);
        final dates = _resolveDates(currentState, wid);

        return NewOrderRequestModel(
          wid.selectedSequence!,
          dates.value2,
          dates.value1,
          int.parse(wid.priorityController!.text),
          wid.idController!.text.isNotEmpty ? wid.idController!.text : null,
          preemptionMatrix:
              wid.stateKey.currentState?.getPreemptionMatrix(),
          taskMachineTimesMinutes: taskMachineTimes,
          machineFinalStates:
              wid.stateKey.currentState?.getMachineFinalStates(),
        );
      }).toList();

      final response = await orderService.updateOrder(
        orderId,
        jobs,
        setupTimeMatrix: currentState.setupTimeMatrix,
        machineInitialStates: currentState.machineInitialStates,
      );

      response.fold(
        (failure) {
          final newState = NewOrdersState(
            jobs: currentState.jobs,
            sequences: currentState.sequences,
            justSaved: false,
          );
          emit(newState);
        },
        (success) {
          final newState = NewOrdersState(
            jobs: [],
            sequences: currentState.sequences,
            justSaved: true,
          );
          emit(newState);
        },
      );
    }
  }

  /// Loads an existing order into the BLoC so its jobs can be edited.
  /// Only present in file 9.
  Future<void> loadOrderForEdit(int orderId) async {
    final seqResponse = await seqService.getSequences();
    List<Tuple2<int, String>> sequences = [];
    seqResponse.fold(
      (failure) => null,
      (seqs) => sequences =
          seqs.map((s) => Tuple2<int, String>(s.id!, s.name)).toList(),
    );

    final response = await orderService.orderRepo.getFullOrder(orderId);
    response.fold(
      (failure) => emit(NewOrdersFailureState()),
      (order) {
        List<AddJobWidget> jobs = [];
        if (order.orderJobs != null) {
          int index = 1;
          for (var job in order.orderJobs!) {
            jobs.add(AddJobWidget(
              availableDate: job.availableDate,
              dueDate: job.dueDate,
              availableHour: TimeOfDay.fromDateTime(
                  job.availableDate ?? DateTime.now()),
              dueHour:
                  TimeOfDay.fromDateTime(job.dueDate ?? DateTime.now()),
              priorityController:
                  TextEditingController(text: job.priority.toString()),
              // The name the user typed, not the database's auto-increment
              // id. This field is submitted back as NewOrderRequestModel
              // .jobName on save, so filling it with the numeric id meant
              // reopening an order showed "34" and saving it overwrote the
              // real name with that number.
              idController: TextEditingController(
                  text: job.jobName ?? job.jobId?.toString() ?? ''),
              index: index,
              sequences: sequences,
              selectedSequence: job.sequence?.id,
              // Everything the form used to drop on the floor. The DAO
              // already reads these back from job_machine_states,
              // job_preemption and job_task_machine_times; they just had
              // nowhere to go until AddJobWidget gained these parameters.
              initialMachineFinalStates: job.machineFinalStates,
              initialPreemptionMatrix: job.preemptionMatrix,
              initialTaskMachineTimes: job.taskMachineTimes?.map(
                (taskId, byMachine) => MapEntry(
                  taskId,
                  byMachine.map(
                    (machineId, times) =>
                        MapEntry(machineId, times.toMinutesMap()),
                  ),
                ),
              ),
            ));
            index++;
          }
        }
        emit(NewOrdersState(
          jobs: jobs,
          sequences: sequences,
          setupTimeMatrix: order.setupTimeMatrix,
          machineInitialStates: order.machineInitialStates,
        ));
      },
    );
  }

  // ─── State resets ──────────────────────────────────────────────────────────

  void newOrder() {
    emit(NewOrdersInitialState());
  }

  void newJob() {
    emit(NewOrdersInitialState());
  }
}