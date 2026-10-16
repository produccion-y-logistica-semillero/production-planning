// =============================================================================
// lib/services/setup_time_matrix.dart
//
// Core logic for sequence-dependent setup times (tiempos de alistamiento
// dependientes de la secuencia).
//
// ARCHITECTURE NOTE
// ──────────────────
// This file is pure Dart — no Flutter, no BLoC, no SQLite imports.
// It is consumed by the algorithm files (flexible_flow_shop.dart,
// single_machine.dart, …) to look up job-state-to-job-state changeover costs.
//
// DB RELATIONSHIP
// ───────────────
// The matrix data (keyed by machine name and job "final state" letter) is
// persisted per order in the order_setup_matrix table, read/written by
// OrderDao and carried on OrderEntity.setupTimeMatrix. Adapters convert that
// raw map into a SetupTimeMatrix/SetupTimeHelper at schedule time.
//
// WHY SEQUENCE-DEPENDENT?
// ────────────────────────
// s_{ij} = changeover cost from job-type i → job-type j on a given machine.
// The cost changes based on what ran BEFORE (hence "dependent on the sequence").
// This is precisely what the project leader's image flags:
//   "Tiempos de alistamiento según job y máquina dependientes de la secuencia"
// =============================================================================
//
/// One (fromState → toState) cell together with its setup cost in minutes.
class SetupTimeMatrixEntry {
  final String fromState;
  final String toState;
  final double time;

  const SetupTimeMatrixEntry({
    required this.fromState,
    required this.toState,
    required this.time,
  });

  @override
  String toString() =>
      'SetupTimeMatrixEntry(fromState: $fromState, toState: $toState, time: $time)';
}

// -----------------------------------------------------------------------------
// Core matrix
// -----------------------------------------------------------------------------

/// Sequence-dependent setup time matrix for ONE machine.
///
/// Rows   = fromState (product family / job-type that just ran).
/// Cols   = toState   (product family / job-type about to run).
/// Value  = setup minutes required before processing can start.
///
/// The diagonal s_{ii} defaults to 0, but same-state transitions can be
/// overridden with a custom setup cost when the user enters a value for the
/// corresponding row/column cell.
class SetupTimeMatrix {
  /// Machine identifier that matches the machine picker in the UI / DB.
  final String machineName;

  /// Ordered state labels (e.g. "A"…"J" as shown in the UI screenshot).
  final List<String> states;

  final Map<String, Map<String, double>> _data = {};

  SetupTimeMatrix({
    required this.machineName,
    required List<String> states,
  }) : states = List.unmodifiable(states) {
    _initDefaultTimes();
  }

  void _initDefaultTimes() {
    for (final from in states) {
      _data[from] = {};
      for (final to in states) {
        _data[from]![to] = 0.0;
      }
    }
  }

  // ---- mutation -----------------------------------------------------------

  void setTime(String fromState, String toState, double time) {
    if (!_data.containsKey(fromState) ||
        !_data[fromState]!.containsKey(toState)) {
      throw ArgumentError('Invalid states: $fromState -> $toState');
    }
    if (time < 0) throw ArgumentError('Time cannot be negative: $time');
    _data[fromState]![toState] = time;
  }

  void setTimeByIndex(int rowIndex, int colIndex, double time) =>
      setTime(states[rowIndex], states[colIndex], time);

  // ---- lookup -------------------------------------------------------------

  /// Returns s_{fromState → toState}.
  /// Returns 0.0 when [fromState] is null (cold-start / first job on machine).
  /// Also returns 0.0 gracefully when a state pair is missing (e.g. new job
  /// type added after the matrix was last saved).
  double getTime(String? fromState, String toState) {
    if (fromState == null) return 0.0;
    return _data[fromState]?[toState] ?? 0.0;
  }

  double getTimeByIndex(int rowIndex, int colIndex) =>
      getTime(states[rowIndex], states[colIndex]);

  // ---- introspection ------------------------------------------------------

  List<SetupTimeMatrixEntry> get nonZeroEntries => allEntries
      .where((e) => e.time != 0.0)
      .toList();

  List<SetupTimeMatrixEntry> get allEntries {
    final result = <SetupTimeMatrixEntry>[];
    for (final from in states) {
      for (final to in states) {
        result.add(SetupTimeMatrixEntry(
            fromState: from, toState: to, time: _data[from]![to]!));
      }
    }
    return result;
  }

  List<List<double>> toMatrix() => [
        for (final from in states)
          [for (final to in states) _data[from]![to]!],
      ];
}

// -----------------------------------------------------------------------------
// SetupTimeHelper — used directly inside algorithm files
// -----------------------------------------------------------------------------

/// Provides the two primitives every scheduling algorithm needs:
///
///   [getSetupTime]            → raw s_{ij} in minutes (double)
///   [effectiveProcessingTime] → p_j + s_{ij}  (used by *_ADAPTADO variants)
///   [setupDuration]           → s_{ij} as a [Duration] (used by flow-shops)
///   [earliestStartAfterSetup] → completionTime + setup as a [DateTime]
class SetupTimeHelper {
  final SetupTimeMatrix _matrix;

  SetupTimeHelper(this._matrix);

  /// Raw s_{fromState → toState} in minutes.  0.0 on cold start (null from).
  double getSetupTime(String? fromState, String toState) =>
      _matrix.getTime(fromState, toState);

  /// p_j + s_{prev → curr}.  Used by EDD_ADAPTADO, SPT_ADAPTADO, etc.
  double effectiveProcessingTime(
    double nominalProcessingTime,
    String? fromJobState,
    String toJobState,
  ) =>
      nominalProcessingTime + getSetupTime(fromJobState, toJobState);

  /// Total setup time in minutes for a complete ordered sequence of job states.
  double totalSetupTime(List<String> jobStates) {
    if (jobStates.length < 2) return 0.0;
    double total = 0.0; // first job: cold start → s = 0
    for (int i = 0; i < jobStates.length - 1; i++) {
      total += getSetupTime(jobStates[i], jobStates[i + 1]);
    }
    return total;
  }

  /// s_{ij} expressed as a [Duration] for use with [DateTime] arithmetic.
  Duration setupDuration(String? fromState, String toState) =>
      Duration(minutes: getSetupTime(fromState, toState).round());

  /// Returns the earliest [DateTime] at which a machine can START processing
  /// the next job (toState), given it finished the previous job at
  /// [completionTime].
  ///
  /// Working-schedule boundary adjustments (e.g. _adjustForWorkingSchedule)
  /// are left to the caller because that logic already exists in the flow-shop
  /// classes and must not be duplicated here.
  DateTime earliestStartAfterSetup({
    required DateTime completionTime,
    required String? fromState,
    required String toState,
  }) =>
      completionTime.add(setupDuration(fromState, toState));
}
