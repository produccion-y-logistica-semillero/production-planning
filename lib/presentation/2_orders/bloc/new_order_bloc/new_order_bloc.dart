
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_standard_times.dart';
import 'package:production_planning/entities/sequence_entity.dart';
import 'package:production_planning/presentation/2_orders/bloc/new_order_bloc/new_order_state.dart';
import 'package:production_planning/presentation/2_orders/request_models/new_order_request_model.dart';
import 'package:production_planning/presentation/2_orders/widgets/high_order/add_job.dart';
import 'package:production_planning/services/machines_service.dart';
import 'package:production_planning/services/orders_service.dart';
import 'package:production_planning/services/sequences_service.dart';

class NewOrderBloc extends Cubit<NewOrderState> {

  final OrdersService orderService;
  final SequencesService seqService;
  final MachinesService machinesService;

  final Map<int, SequenceEntity> _sequenceCache = {};
  final Map<int, List<MachineEntity>> _machinesCache = {};

  NewOrderBloc(this.orderService, this.seqService, this.machinesService)
      : super(NewOrdersInitialState());

  Future<void> retrieveSequences() async {
    final response = await seqService.getSequences();
    response.fold(
      (failure) => emit(NewOrdersFailureState()),
      (sequences) {
        emit(NewOrdersState(
          [],
          sequences.map((s) => Tuple2<int, String>(s.id!, s.name)).toList(),
        ));
      },
    );
  }

  void addJob() {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);
      List<Tuple2<int, String>> sequences = currentState.sequences;

      int index = jobs.isNotEmpty
          ? jobs.map((job) => job.index).reduce((a, b) => a > b ? a : b)
          : 0;

      jobs.add(AddJobWidget(
        availableDate: null,
        dueDate: null,
        availableHour: null,
        dueHour: null,
        priorityController: TextEditingController(),
        quantityController: TextEditingController(),
        idController: TextEditingController(),
        index: index + 1,
        sequences: sequences,
      ));

      emit(NewOrdersState(jobs, sequences));
    }
  }

  void removeJob(int index) {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);
      List<Tuple2<int, String>> sequences = currentState.sequences;

      jobs.removeWhere((widget) => widget.index == index);
      emit(NewOrdersState(jobs, sequences));
    }
  }

  void duplicateJob(int index) {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      List<AddJobWidget> jobs = List.from(currentState.jobs);
      List<Tuple2<int, String>> sequences = currentState.sequences;

      // Find the source job to copy
      final sourceJob = jobs.firstWhere((job) => job.index == index);

      // Calculate next index
      int nextIndex = jobs.isNotEmpty
          ? jobs.map((job) => job.index).reduce((a, b) => a > b ? a : b) + 1
          : 1;

      // Clone the job with all its current data
      jobs.add(AddJobWidget(
        availableDate: sourceJob.availableDate,
        dueDate: sourceJob.dueDate,
        availableHour: sourceJob.availableHour,
        dueHour: sourceJob.dueHour,
        priorityController: TextEditingController(
          text: sourceJob.priorityController?.text ?? '',
        ),
        quantityController: TextEditingController(
          text: sourceJob.quantityController?.text ?? '',
        ),
        idController: TextEditingController(),
        index: nextIndex,
        sequences: sequences,
        selectedSequence: sourceJob.selectedSequence,
      ));

      emit(NewOrdersState(jobs, sequences));
    }
  }

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

  MachineStandardTimes getStandardTimesForType(int machineTypeId) {
    return machinesService.getStandardTimesForType(machineTypeId);
  }

  Future<void> updateStandardTimesForType(
    int machineTypeId,
    MachineStandardTimes times,
  ) async {
    machinesService.updateStandardTimesForType(machineTypeId, times);
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

  Future<void> saveOrder() async {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      final List<NewOrderRequestModel> jobs = currentState.jobs.map((wid) {

        // Collect task-machine explicit times from the widget state (if any)
        final widgetState = wid.stateKey.currentState;
        Map<int, Map<int, Map<String, int>>>? taskMachineTimes;
        if (widgetState == null) {
          print('NewOrderBloc: widgetState is NULL for job index=${wid.index}');
        } else {
          // Prefer explicit per-task-per-machine times collected by the widget
          final explicit = widgetState.getExplicitTaskMachineMinutes();
          if (explicit.isNotEmpty) {
            taskMachineTimes = explicit;
            print(
                'NewOrderBloc: using explicit taskMachineTimes for job index=${wid.index} -> $taskMachineTimes');
          } else {
            final selectedMachines = widgetState.getSelectedMachines();
            final stationTimes = widgetState.getStationProcessingMinutes();
            print(
                'NewOrderBloc: widgetState for job index=${wid.index} selectedMachines=$selectedMachines stationTimes=$stationTimes');
            // Build mapping taskId -> { machineId: { processing, preparation, rest } }
            taskMachineTimes = {};
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
                      'NewOrderBloc: missing mapping for task ${task.id} -> machineType=$machineType machineId=$machineId minutes=$minutes');
                }
              }
            } else {
              print(
                  'NewOrderBloc: no tasks for job index=${wid.index} (sequence not selected?)');
            }
          }
        }

        return NewOrderRequestModel(
          wid.selectedSequence!,
          wid.dueDate!,
          wid.availableDate!,
          int.parse(wid.priorityController!.text),
          int.parse(wid.quantityController!.text),
          preemptionMatrix: wid.stateKey.currentState?.getPreemptionMatrix(),
          taskMachineTimesMinutes: taskMachineTimes,

        );
      }).toList();

      final response = await orderService.addOrder(jobs);

      // Diagnostic: print the taskMachineTimesMinutes for each job before saving
      for (var j in jobs) {
        print(
            'NewOrderBloc: job sequence=${j.sequenceId} taskMachineTimes=${j.taskMachineTimesMinutes}');
      }
      response.fold(
        (failure) {
          final newState =
              NewOrdersState(currentState.jobs, currentState.sequences);
          newState.justSaved = false;
          emit(newState);
        },
        (success) {
          final newState = NewOrdersState([], currentState.sequences);
          newState.justSaved = true;
          emit(newState);
        },
      );
    }
  }

  Future<void> updateOrder(int orderId) async {
    if (state is NewOrdersState) {
      final currentState = state as NewOrdersState;
      final List<NewOrderRequestModel> jobs = currentState.jobs.map((wid) {
        final widgetState = wid.stateKey.currentState;
        Map<int, Map<int, Map<String, int>>>? taskMachineTimes;
        
        if (widgetState != null) {
          final explicit = widgetState.getExplicitTaskMachineMinutes();
          if (explicit.isNotEmpty) {
            taskMachineTimes = explicit;
          } else {
            final selectedMachines = widgetState.getSelectedMachines();
            final stationTimes = widgetState.getStationProcessingMinutes();
            taskMachineTimes = {};
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
                }
              }
            }
          }
        }

        return NewOrderRequestModel(
          wid.selectedSequence!,
          wid.dueDate!,
          wid.availableDate!,
          int.parse(wid.priorityController!.text),
          int.parse(wid.quantityController!.text),
          preemptionMatrix: wid.stateKey.currentState?.getPreemptionMatrix(),
          taskMachineTimesMinutes: taskMachineTimes,
        );
      }).toList();

      final response = await orderService.updateOrder(orderId, jobs);

      response.fold(
        (failure) {
          final newState =
              NewOrdersState(currentState.jobs, currentState.sequences);
          newState.justSaved = false;
          emit(newState);
        },
        (success) {
          final newState = NewOrdersState([], currentState.sequences);
          newState.justSaved = true;
          emit(newState);
        },
      );
    }
  }

  Future<void> loadOrderForEdit(int orderId) async {
    final seqResponse = await seqService.getSequences();
    List<Tuple2<int, String>> sequences = [];
    seqResponse.fold(
      (failure) => null,
      (seqs) => sequences = seqs.map((s) => Tuple2<int, String>(s.id!, s.name)).toList(),
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
              availableHour: TimeOfDay.fromDateTime(job.availableDate ?? DateTime.now()),
              dueHour: TimeOfDay.fromDateTime(job.dueDate ?? DateTime.now()),
              priorityController: TextEditingController(text: job.priority.toString()),
              quantityController: TextEditingController(text: job.amount.toString()),
              idController: TextEditingController(text: job.jobId?.toString() ?? ''),
              index: index,
              sequences: sequences,
              selectedSequence: job.sequence?.id,
            ));
            index++;
          }
        }
        emit(NewOrdersState(jobs, sequences));
      },
    );
  }

  void newOrder() {
    emit(NewOrdersInitialState());
  }

  void newJob() {
    emit(NewOrdersInitialState());
  }
}
