// A job keeps its processing time PER MACHINE of each station.
//
// The job form used to store a single machine entry per task, so typing a
// time for a second machine of the station erased the first, and the
// scheduler then applied that lone entry to every machine of the station
// ("if only one mapping exists, return it"). These tests pin the pieces the
// fix rests on: the seeding of one entry per machine, the per-machine lookup
// the adapters use, and the automatic-rest policy every adapter now reads
// through the same function.
import 'package:flutter_test/flutter_test.dart';
import 'package:production_planning/entities/job_entity.dart';
import 'package:production_planning/entities/machine_entity.dart';
import 'package:production_planning/entities/machine_times.dart';
import 'package:production_planning/entities/task_entity.dart';
import 'package:production_planning/shared/utils/task_time_utils.dart';

MachineEntity machine(
  int id, {
  double processingPercentage = 100,
  int continueCapacity = 0,
  double restPercentage = 0,
}) =>
    MachineEntity(
      id: id,
      machineTypeId: 9,
      status: null,
      name: 'Torno $id',
      processingPercentage: processingPercentage,
      preparationPercentage: 100,
      restPercentage: restPercentage,
      continueCapacity: continueCapacity,
    );

TaskEntity task({int id = 1}) => TaskEntity(
      id: id,
      processingUnits: const Duration(hours: 2),
      description: 'Torneado',
      machineTypeId: 9,
      machineName: 'Torno',
      allowPreemption: true,
    );

Map<String, int> minutes(int processing) =>
    {'processing': processing, 'preparation': 0, 'rest': 0};

void main() {
  group('seedTaskMachineMinutes — one entry per machine of the station', () {
    test('a new job gets every machine, each at its own percentage', () {
      final seeded = seedTaskMachineMinutes(
        task: task(),
        stationMachines: [
          machine(1),
          machine(2),
          machine(3, processingPercentage: 80),
        ],
      );

      expect(seeded.keys, [1, 2, 3]);
      // Identical machines (100 %) start from the same time...
      expect(seeded[1]!['processing'], 120);
      expect(seeded[2]!['processing'], 120);
      // ...and a non-identical one from its own.
      expect(seeded[3]!['processing'], 96);
    });

    test('times typed for two identical machines are both kept', () {
      final seeded = seedTaskMachineMinutes(
        task: task(),
        stationMachines: [machine(1), machine(2)],
        saved: {1: minutes(30), 2: minutes(45)},
      );

      expect(seeded[1]!['processing'], 30);
      expect(seeded[2]!['processing'], 45);
    });

    test('editing one machine leaves its siblings untouched', () {
      final current = seedTaskMachineMinutes(
        task: task(),
        stationMachines: [machine(1), machine(2)],
      );
      // What the time dialog does on "Aceptar" for machine 2.
      current[2] = minutes(15);

      final reloaded = seedTaskMachineMinutes(
        task: task(),
        stationMachines: [machine(1), machine(2)],
        saved: current,
      );

      expect(reloaded[1]!['processing'], 120);
      expect(reloaded[2]!['processing'], 15);
    });

    test('an order saved in the old one-entry format keeps its schedule', () {
      // The scheduler applied the lone entry to every machine; reopening
      // the order must show exactly that, not silently recompute.
      final seeded = seedTaskMachineMinutes(
        task: task(),
        stationMachines: [machine(1), machine(2, processingPercentage: 50)],
        saved: {1: minutes(50)},
      );

      expect(seeded[1]!['processing'], 50);
      expect(seeded[2]!['processing'], 50);
    });

    test('a machine that left the station is dropped', () {
      final seeded = seedTaskMachineMinutes(
        task: task(),
        stationMachines: [machine(1), machine(2)],
        saved: {1: minutes(30), 2: minutes(45), 7: minutes(99)},
      );

      expect(seeded.keys, [1, 2]);
    });
  });

  group('getExplicitMachineTimes — what the adapters read', () {
    JobEntity job(Map<int, Map<int, MachineTimes>> times) => JobEntity(
          1,
          null,
          'Lote A',
          DateTime(2024, 10, 25),
          1,
          DateTime(2024, 10, 20, 8),
          taskMachineTimes: times,
        );

    MachineTimes t(int processing) =>
        MachineTimes.fromMinutesMap(minutes(processing));

    test('each machine of a station gets its own time', () {
      final j = job({
        1: {1: t(30), 2: t(45)},
      });

      expect(getExplicitProcessingDuration(j, 1, machine(1)),
          const Duration(minutes: 30));
      expect(getExplicitProcessingDuration(j, 1, machine(2)),
          const Duration(minutes: 45));
    });

    test('a machine id is never confused with a machine TYPE id', () {
      // Machine 14 belongs to type 9, and the job happens to have an entry
      // for a machine whose id is 9. That entry is another machine's time.
      final j = job({
        1: {9: t(30), 5: t(45)},
      });
      final other = MachineEntity(
        id: 14,
        machineTypeId: 9,
        status: null,
        name: 'Torno 14',
        processingPercentage: 100,
        preparationPercentage: 100,
        restPercentage: 0,
        continueCapacity: 0,
      );

      expect(getExplicitProcessingDuration(j, 1, other), isNull);
    });
  });

  group('machineRestPolicy — "No aplica descanso automático"', () {
    void expectNoRest(MachineEntity m) {
      final policy = machineRestPolicy(m);
      expect(policy.capacityMinutes, 0);
      expect(policy.rest, Duration.zero);
    }

    test('capacity 0 means no rest, whatever the rest says', () {
      expectNoRest(machine(1, continueCapacity: 0, restPercentage: 100));
    });

    test('a zero rest means no rest, whatever the capacity says', () {
      expectNoRest(machine(1, continueCapacity: 240, restPercentage: 0));
    });

    test('a capacity beyond the scheduling horizon means no rest', () {
      expectNoRest(machine(1,
          continueCapacity: maxContinuousCapacityMinutes,
          restPercentage: 100));
      expectNoRest(
          machine(1, continueCapacity: 999999, restPercentage: 100));
    });

    test('a real policy comes back in minutes', () {
      // 15 minutes of rest is stored as 25 % of an hour.
      final policy =
          machineRestPolicy(machine(1, continueCapacity: 240, restPercentage: 25));

      expect(policy.capacityMinutes, 240);
      expect(policy.rest, const Duration(minutes: 15));
    });
  });
}
