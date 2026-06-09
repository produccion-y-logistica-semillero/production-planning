// lib/services/setup_time_service.dart
//
// Merged version that satisfies BOTH call-sites:
//   1. new_order_bloc.dart  → saveMatrix(machineName, SetupTimeMatrix)
//   2. flow_shop_adapter / flexible_flow_shop_adapter
//        → order.setupTimeMatrix (Map<machineName, fromState -> toState -> minutes>)
//          which is populated from this service's in-memory cache
//   3. setup_times_page (existing CRUD) → add/update/delete/get by machine id
//
// The in-memory cache (_matrixCache) is the live bridge:
//   - written by saveMatrix() (called from the BLoC when user taps Guardar)
//   - read  by getSetupMatrixForOrder() (called by OrdersService before
//     invoking any adapter, to attach matrices to the OrderEntity)

import 'package:dartz/dartz.dart';
import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/setup_time_dao.dart';
import 'package:production_planning/entities/setup_time_entity.dart';
import 'package:production_planning/services/setup_time_matrix.dart';

class SetupTimeService {
  final SetupTimeDao dao;

  // keyed by machine NAME (the string the user sees and the dialog uses)
  final Map<String, Map<String, Map<String, int>>> _matrixCache = {};

  SetupTimeService(this.dao);

  // ── In-memory matrix API (used by BLoC + adapters) ──────────────────────

  /// Called by NewOrderBloc.saveSetupMatrix() when the user taps "Guardar".
  /// Stores the machine-state matrix in the in-memory cache so adapters can access it.
  Future<void> saveMatrix(String machineName, SetupTimeMatrix matrix) async {
    _matrixCache[machineName.trim().toLowerCase()] = _matrixToRawMap(matrix);
  }

  Map<String, Map<String, int>> _matrixToRawMap(SetupTimeMatrix matrix) {
    return {
      for (final from in matrix.states)
        from: {
          for (final to in matrix.states)
            to: matrix.getTime(from, to).round(),
        }
    };
  }

  /// Returns the matrix for [machineName] from the cache, or an empty
  /// all-zero matrix if none has been saved yet.
  Future<SetupTimeMatrix> loadMatrix({
    required String machineName,
    required List<String> jobStates,
  }) async {
    final raw = _matrixCache[machineName.trim().toLowerCase()];
    if (raw == null) {
      return SetupTimeMatrix(machineName: machineName, states: jobStates);
    }

    final matrix = SetupTimeMatrix(machineName: machineName, states: jobStates);
    for (final from in raw.keys) {
      for (final to in raw[from]!.keys) {
        matrix.setTime(from, to, raw[from]![to]!.toDouble());
      }
    }
    return matrix;
  }

  /// Returns all matrices currently in the cache.
  /// Called by adapters to overlay cache values onto the persisted order matrix.
  Map<String, Map<String, Map<String, int>>> get allCachedMatrices =>
      Map.unmodifiable(_matrixCache);

  /// Clears the cache (e.g. after an order is saved and processing is done).
  void clearCache() => _matrixCache.clear();

  // ── Persistent setup-time CRUD (used by SetupTimesPage) ─────────────────

  Future<Either<Failure, SetupTimeEntity>> addSetupTime({
    required int machineId,
    int? fromSequenceId,
    required int toSequenceId,
    required Duration setupDuration,
  }) async {
    final setupTime = SetupTimeEntity(
      machineId: machineId,
      fromSequenceId: fromSequenceId,
      toSequenceId: toSequenceId,
      setupDuration: setupDuration,
    );
    final result = await dao.insert(setupTime);
    return result.fold(
      (failure) => Left(failure),
      (id) {
        setupTime.id = id;
        return Right(setupTime);
      },
    );
  }

  Future<Either<Failure, bool>> updateSetupTime(
          SetupTimeEntity setupTime) async =>
      dao.update(setupTime);

  Future<Either<Failure, bool>> deleteSetupTime(int id) async =>
      dao.delete(id);

  Future<Either<Failure, List<SetupTimeEntity>>> getSetupTimesByMachine(
          int machineId) async =>
      dao.getAllByMachine(machineId);

  Future<Either<Failure, Duration>> getSetupDuration({
    required int machineId,
    int? fromSequenceId,
    required int toSequenceId,
  }) async {
    final result =
        await dao.getSetupTime(machineId, fromSequenceId, toSequenceId);
    return result.fold(
      (failure) => Left(failure),
      (setupTime) {
        if (setupTime == null) {
          if (fromSequenceId != null) {
            return getSetupDuration(
              machineId: machineId,
              fromSequenceId: null,
              toSequenceId: toSequenceId,
            );
          }
          return const Right(Duration.zero);
        }
        return Right(setupTime.setupDuration);
      },
    );
  }

  Future<Either<Failure, Map<int, Map<int?, Map<int, Duration>>>>>
      buildChangeoverMatrix() async {
    final result = await dao.getAll();
    return result.fold(
      (failure) => Left(failure),
      (setupTimes) {
        final Map<int, Map<int?, Map<int, Duration>>> matrix = {};
        for (final st in setupTimes) {
          matrix.putIfAbsent(st.machineId, () => {});
          matrix[st.machineId]!.putIfAbsent(st.fromSequenceId, () => {});
          matrix[st.machineId]![st.fromSequenceId]![st.toSequenceId] =
              st.setupDuration;
        }
        return Right(matrix);
      },
    );
  }
}