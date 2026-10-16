// A station's setup-time matrix is entered for ONE machine at a time in the
// UI (Definir matriz de tiempos de alistamiento), keyed there by machine
// NAME. A second machine of the same station/type had no entry of its own
// and always got zero setup — buildMachineStateSetupMatrix now falls back
// to another machine of the SAME machine type as that machine's default,
// same idea as resolveMachineInitialStates.
import 'package:production_planning/entities/machine_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/shared/utils/task_time_utils.dart';

MachineEntity _machine(int id, int typeId, String name) => MachineEntity(
      id: id,
      status: null,
      machineTypeId: typeId,
      name: name,
      processingPercentage: 100,
      preparationPercentage: 0,
      restPercentage: 0,
      continueCapacity: 0,
    );

void main() {
  group('buildMachineStateSetupMatrix — same-type inheritance', () {
    test('a machine with no matrix of its own inherits the one registered '
        'for another machine of the same type', () {
      final machines = [
        _machine(1, 100, 'Torno 1'),
        _machine(2, 100, 'Torno 2'),
      ];
      // Registered only for "Torno 1" — the UI dialog saves one machine at
      // a time.
      final orderMatrix = {
        'Torno 1': {
          'A': {'A': 0, 'B': 30},
        },
      };

      final result = buildMachineStateSetupMatrix(machines, orderMatrix);

      expect(result, isNotNull);
      expect(result![1], {
        'A': {'A': 0, 'B': 30},
      }, reason: 'the machine with a direct name match keeps its own entry');
      expect(result[2], result[1],
          reason: 'Torno 2 (same type, no entry of its own) should inherit '
              "Torno 1's matrix as its station default");
    });

    test('a machine of a DIFFERENT type never inherits another '
        "station's matrix", () {
      final machines = [
        _machine(1, 100, 'Torno 1'),
        _machine(2, 200, 'Fresadora 1'),
      ];
      final orderMatrix = {
        'Torno 1': {
          'A': {'A': 0, 'B': 30},
        },
      };

      final result = buildMachineStateSetupMatrix(machines, orderMatrix);

      expect(result, isNotNull);
      expect(result!.containsKey(2), isFalse);
    });

    test('an explicit match always wins over inheritance', () {
      final machines = [
        _machine(1, 100, 'Torno 1'),
        _machine(2, 100, 'Torno 2'),
      ];
      final orderMatrix = {
        'Torno 1': {
          'A': {'A': 0, 'B': 30},
        },
        'Torno 2': {
          'A': {'A': 0, 'B': 99},
        },
      };

      final result = buildMachineStateSetupMatrix(machines, orderMatrix);

      expect(result![2], {
        'A': {'A': 0, 'B': 99},
      });
    });
  });

  group('resolveMachineInitialStates — same-type inheritance', () {
    test('a machine with no initial state of its own inherits the one '
        'registered for another machine of the same type', () {
      final machines = [
        _machine(1, 100, 'Torno 1'),
        _machine(2, 100, 'Torno 2'),
      ];
      final result =
          resolveMachineInitialStates(machines, {'Torno 1': 'B'});

      expect(result[1], 'B');
      expect(result[2], 'B');
    });

    test('with nothing configured, no machine gets an initial state', () {
      final machines = [_machine(1, 100, 'Torno 1')];
      expect(resolveMachineInitialStates(machines, null), isEmpty);
      expect(resolveMachineInitialStates(machines, {}), isEmpty);
    });
  });

  group('station default is deterministic (lowest machine id)', () {
    // Three machines of one station; Torno 3 and Torno 2 have their own
    // matrix, Torno 4 has none. Loaded in a scrambled order on purpose.
    final machines = [
      _machine(3, 100, 'Torno 3'),
      _machine(4, 100, 'Torno 4'),
      _machine(2, 100, 'Torno 2'),
    ];
    final orderMatrix = {
      'Torno 3': {
        'A': {'B': 30},
      },
      'Torno 2': {
        'A': {'B': 10},
      },
    };

    test('a machine without a matrix inherits the lowest-id sibling, '
        'whatever the load order', () {
      final result = buildMachineStateSetupMatrix(machines, orderMatrix)!;
      expect(result[4], orderMatrix['Torno 2']);
      final reversed = buildMachineStateSetupMatrix(
          machines.reversed.toList(), orderMatrix)!;
      expect(reversed[4], orderMatrix['Torno 2']);
    });

    test('initial states follow the same rule', () {
      final result = resolveMachineInitialStates(
          machines, {'Torno 3': 'C', 'Torno 2': 'B'});
      expect(result[4], 'B');
    });

    test('stationDefaultSource tells the UI where each entry comes from', () {
      final sources =
          stationDefaultSource(machines, orderMatrix.keys.toSet());
      expect(sources, {
        'Torno 3': 'Torno 3',
        'Torno 2': 'Torno 2',
        'Torno 4': 'Torno 2',
      });
      expect(stationDefaultSource(machines, {}),
          {'Torno 3': null, 'Torno 4': null, 'Torno 2': null});
    });
  });
}
