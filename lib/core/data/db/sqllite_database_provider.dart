import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

class SQLLiteDatabaseProvider {
  static Database? _database;

  static Future<void> _createMachineInactivitiesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS MACHINE_INACTIVITIES (
          inactivity_id INTEGER PRIMARY KEY AUTOINCREMENT,
          machine_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          start_time TEXT NOT NULL,
          duration_minutes INTEGER NOT NULL,
          monday INTEGER NOT NULL DEFAULT 0,
          tuesday INTEGER NOT NULL DEFAULT 0,
          wednesday INTEGER NOT NULL DEFAULT 0,
          thursday INTEGER NOT NULL DEFAULT 0,
          friday INTEGER NOT NULL DEFAULT 0,
          saturday INTEGER NOT NULL DEFAULT 0,
          sunday INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id)
      );
    ''');
  }

  static Future<Database> open(String workspace) async {
    final docsDir = await getApplicationSupportDirectory();
    final databasePath = docsDir.path;
    final path = join(databasePath, '${workspace.replaceAll(' ', '')}_v3.db');

    // Remove legacy log file writing which causes permission issues
    print('Database path: $path');

    _database = await openDatabase(
      path,
      version: 9,
      onCreate: (Database db, int version) async {
        final batch = db.batch();

        batch.execute('''
          CREATE TABLE STATUS (
              status_id INTEGER PRIMARY KEY AUTOINCREMENT,
              status VARCHAR(100) NOT NULL
          );
        ''');
        batch.execute('''
          CREATE TABLE MACHINE_TYPES(
              machine_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              description TEXT
          );
        ''');
        batch.execute('''
          CREATE TABLE MACHINES (
              machine_id INTEGER PRIMARY KEY AUTOINCREMENT,
              machine_name VARCHAR(100) NOT NULL,
              machine_type_id INTEGER NOT NULL,
              status_id INTEGER NOT NULL,
              processing_percentage REAL NOT NULL DEFAULT 100.0,
              preparation_percentage REAL NOT NULL DEFAULT 100.0,
              rest_percentage REAL NOT NULL DEFAULT 100.0,
              availability_time DATETIME NOT NULL,
              continue_capacity INTEGER,
              FOREIGN KEY (machine_type_id) REFERENCES machine_types(machine_type_id),
              FOREIGN KEY (status_id) REFERENCES status(status_id)
          );
        ''');

        // Inline creation of MACHINE_INACTIVITIES to avoid async issues in batch
        batch.execute('''
        CREATE TABLE IF NOT EXISTS MACHINE_INACTIVITIES (
            inactivity_id INTEGER PRIMARY KEY AUTOINCREMENT,
            machine_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            start_time TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            monday INTEGER NOT NULL DEFAULT 0,
            tuesday INTEGER NOT NULL DEFAULT 0,
            wednesday INTEGER NOT NULL DEFAULT 0,
            thursday INTEGER NOT NULL DEFAULT 0,
            friday INTEGER NOT NULL DEFAULT 0,
            saturday INTEGER NOT NULL DEFAULT 0,
            sunday INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id)
        );
      ''');

        batch.execute('''
          CREATE TABLE IF NOT EXISTS setup_times (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              machine_id INTEGER NOT NULL,
              from_sequence_id INTEGER,
              to_sequence_id INTEGER NOT NULL,
              setup_duration_minutes INTEGER NOT NULL,
              FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id),
              FOREIGN KEY (from_sequence_id) REFERENCES sequences(sequence_id),
              FOREIGN KEY (to_sequence_id) REFERENCES sequences(sequence_id),
              UNIQUE(machine_id, from_sequence_id, to_sequence_id)
          );
        ''');

        batch.execute('''
          CREATE TABLE sequences (
              sequence_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name VARCHAR(100) NOT NULL
          );
        ''');
        batch.execute('''
          CREATE TABLE tasks (
              task_id INTEGER PRIMARY KEY AUTOINCREMENT,
              n_proc_units TIMESTAMP NOT NULL,
              description VARCHAR(100),
              sequence_id INTEGER NOT NULL,
              machine_type_id INTEGER NOT NULL,
              allow_preemption INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (sequence_id) REFERENCES sequences(sequence_id),
              FOREIGN KEY (machine_type_id) REFERENCES machine_types(machine_type_id)
          );
        ''');

        batch.execute('''
          CREATE TABLE TaskDependency (
            id SERIAL PRIMARY KEY,
            predecessor_id INT NOT NULL,
            successor_id INT NOT NULL,
            sequence_id INT NOT NULL,
            FOREIGN KEY (predecessor_id) REFERENCES tasks(id),
            FOREIGN KEY (successor_id) REFERENCES tasks(id),
            FOREIGN KEY (sequence_id) REFERENCES sequences(sequence_id),
            CONSTRAINT unique_dependency UNIQUE (predecessor_id, successor_id),
            CONSTRAINT no_self_dependency CHECK (predecessor_id <> successor_id)
          );
        ''');

        batch.execute('''
          CREATE TABLE environments (
              environment_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name VARCHAR(100) NOT NULL
          );
        ''');

        batch.execute('''
          CREATE TABLE dispatch_rules (
              dispatch_rule_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name VARCHAR(100) NOT NULL
          );
        ''');

        batch.execute('''
          CREATE TABLE types_x_rules (
              type_rule_id INTEGER PRIMARY KEY AUTOINCREMENT,
              environment_id INTEGER NOT NULL,
              dispatch_rule_id INTEGER NOT NULL,
              FOREIGN KEY (environment_id) REFERENCES environments(environment_id),
              FOREIGN KEY (dispatch_rule_id) REFERENCES dispatch_rules(dispatch_rule_id)
          );
        ''');

        batch.execute('''
          CREATE TABLE orders (
              order_id INTEGER PRIMARY KEY AUTOINCREMENT,
              reg_date DATE NOT NULL
          );
        ''');
        batch.execute('''
          CREATE TABLE jobs (
              job_id INTEGER PRIMARY KEY AUTOINCREMENT,
              sequence_id INTEGER NOT NULL,
              order_id INTEGER NOT NULL,
              amount INTEGER NOT NULL,
              job_name VARCHAR(100),
              due_date DATE NOT NULL,
              available_date DATE NOT NULL,
              priority INTEGER NOT NULL,
              FOREIGN KEY (sequence_id) REFERENCES sequences(sequence_id),
              FOREIGN KEY (order_id) REFERENCES orders(order_id)
          );
        ''');

        batch.execute('''
          CREATE TABLE job_preemption (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              job_id INTEGER NOT NULL,
              machine_id INTEGER NOT NULL,
              can_preempt INTEGER NOT NULL CHECK (can_preempt IN (0, 1)),
              FOREIGN KEY (job_id) REFERENCES jobs(job_id),
              FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id),
              UNIQUE(job_id, machine_id)
          );
        ''');

        batch.execute('''
          CREATE TABLE IF NOT EXISTS job_task_machine_times (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              job_id INTEGER NOT NULL,
              task_id INTEGER NOT NULL,
              machine_id INTEGER NOT NULL,
              processing_minutes INTEGER NOT NULL,
              preparation_minutes INTEGER NOT NULL DEFAULT 0,
              rest_minutes INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (job_id) REFERENCES jobs(job_id),
              FOREIGN KEY (task_id) REFERENCES tasks(task_id),
              FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id),
              UNIQUE(job_id, task_id, machine_id)
          );
        ''');

        //DML TO POPULATE THE DATABASE
        // Seeding individual rows to ensure execution

        // Status
        batch.insert('status', {'status': 'Active'});
        batch.insert('status', {'status': 'Inactive'});
        batch.insert('status', {'status': 'Maintenance'});

        // Machine Types
        batch.insert('machine_types', {
          'name': 'Type A',
          'description': 'Basic machine type A',
        });
        batch.insert('machine_types', {
          'name': 'Type B',
          'description': 'Advanced machine type B',
        });
        batch.insert('machine_types', {
          'name': 'Type C',
          'description': 'High capacity machine type C',
        });

        // Machines
        batch.insert('machines', {
          'machine_type_id': 1,
          'machine_name': 'type A 1',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 5,
          'availability_time': '2024-09-08 10:00:00',
        });
        batch.insert('machines', {
          'machine_type_id': 2,
          'machine_name': 'type B 1',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 3,
          'availability_time': '2024-09-08 11:00:00',
        });
        batch.insert('machines', {
          'machine_type_id': 3,
          'machine_name': 'type C 1',
          'status_id': 2,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 7,
          'availability_time': '2024-09-08 12:00:00',
        });

        // Sequences
        batch.insert('sequences', {'name': 'Sequence Alpha'});
        batch.insert('sequences', {'name': 'Sequence Beta'});
        batch.insert('sequences', {'name': 'Sequence Gamma'});

        // Tasks
        batch.insert('tasks', {
          'n_proc_units': '2024-09-08 09:00:00',
          'description': 'Task 1 description',
          'sequence_id': 1,
          'machine_type_id': 1,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-09-08 10:00:00',
          'description': 'Task 2 description',
          'sequence_id': 2,
          'machine_type_id': 2,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-09-08 11:00:00',
          'description': 'Task 3 description',
          'sequence_id': 3,
          'machine_type_id': 3,
          'allow_preemption': 0,
        });

        // Environments
        batch.insert('environments', {
          'environment_id': 1,
          'name': 'SINGLE MACHINE',
        });
        batch.insert('environments', {
          'environment_id': 2,
          'name': 'PARALLEL MACHINES',
        });
        batch.insert('environments', {
          'environment_id': 3,
          'name': 'FLOW SHOP',
        });
        batch.insert('environments', {
          'environment_id': 4,
          'name': 'FLEXIBLE FLOW SHOP',
        });
        batch.insert('environments', {'environment_id': 5, 'name': 'JOB SHOP'});
        batch.insert('environments', {
          'environment_id': 6,
          'name': 'FLEXIBLE JOB SHOP',
        });
        batch.insert('environments', {
          'environment_id': 7,
          'name': 'OPEN SHOP',
        });

        // Dispatch Rules
        // Single Machine (IDs 1-13)
        batch.insert('dispatch_rules', {'dispatch_rule_id': 1, 'name': 'EDD'});
        batch.insert('dispatch_rules', {'dispatch_rule_id': 2, 'name': 'SPT'});
        batch.insert('dispatch_rules', {'dispatch_rule_id': 3, 'name': 'LPT'});
        batch.insert('dispatch_rules', {'dispatch_rule_id': 4, 'name': 'FIFO'});
        batch.insert('dispatch_rules', {'dispatch_rule_id': 5, 'name': 'WSPT'});
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 6,
          'name': 'EDD_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 7,
          'name': 'SPT_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 8,
          'name': 'LPT_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 9,
          'name': 'FIFO_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 10,
          'name': 'WSPT_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 11,
          'name': 'MINSLACK',
        });
        batch.insert('dispatch_rules', {'dispatch_rule_id': 12, 'name': 'CR'});
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 13,
          'name': 'ATCS',
        });

        // Parallel (IDs 14-22)
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 14,
          'name': 'FIFO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 15,
          'name': 'SPT_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 16,
          'name': 'EDD_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 17,
          'name': 'LPT_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 18,
          'name': 'FIFO_ADAPTADO',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 19,
          'name': 'WSPT_ADAPTADO',
        });
        batch.insert('dispatch_rules', {'dispatch_rule_id': 20, 'name': 'CR'});
        batch.insert('dispatch_rules', {'dispatch_rule_id': 21, 'name': 'MS'});
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 22,
          'name': 'ATCS',
        });

        // Flow Shop (ID 23)
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 23,
          'name': 'JOHNSON',
        });

        // Genetics (ID 24)
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 24,
          'name': 'GENETICS',
        });

        // Types x Rules
        void addRule(int envId, int ruleId) {
          batch.insert('types_x_rules', {
            'environment_id': envId,
            'dispatch_rule_id': ruleId,
          });
        }

        // 1: Single Machine
        [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          24,
        ].forEach((r) => addRule(1, r));

        // 2: Parallel
        [
          2,
          3,
          1,
          14,
          11,
          12,
          5,
          6,
          7,
          10,
          15,
          16,
          17,
          18,
          19,
          20,
          21,
          22,
          24,
        ].forEach((r) => addRule(2, r));

        // 3: Flow Shop
        [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          11,
          12,
          13,
          23,
          24,
        ].forEach((r) => addRule(3, r));

        // 4: Flexible Flow Shop
        [
          1,
          2,
          3,
          4,
          5,
          6,
          7,
          8,
          9,
          10,
          12,
          13,
          21,
          23,
          24,
        ].forEach((r) => addRule(4, r));

        // 6: Flexible Job Shop
        [1, 2, 3, 4, 5, 12, 13, 21, 24].forEach((r) => addRule(6, r));

        // 7: Open Shop
        [1, 2, 3, 4, 5, 11, 12, 13, 24].forEach((r) => addRule(7, r));

        // Orders
        batch.insert('orders', {'reg_date': '2024-09-08'});
        batch.insert('orders', {'reg_date': '2024-09-07'});
        batch.insert('orders', {'reg_date': '2024-09-06'});

        // Jobs
        batch.insert('jobs', {
          'sequence_id': 1,
          'order_id': 1,
          'amount': 100,
          'due_date': '2024-09-10',
          'priority': 1,
          'available_date': '2024-09-10',
        });
        batch.insert('jobs', {
          'sequence_id': 2,
          'order_id': 2,
          'amount': 200,
          'due_date': '2024-09-11',
          'priority': 2,
          'available_date': '2024-09-10',
        });
        batch.insert('jobs', {
          'sequence_id': 3,
          'order_id': 3,
          'amount': 150,
          'due_date': '2024-09-12',
          'priority': 3,
          'available_date': '2024-09-10',
        });

        // Custom Orders (The ones that were huge blocks)

        // Machine Type 4
        batch.insert('machine_types', {
          'name': 'Maquina coser',
          'description': 'Maquina para coser prendas de vestir',
        }); // ID 4 implicit if autoinc works seq

        // Machine 4
        batch.insert('machines', {
          'machine_type_id': 4,
          'machine_name': 'Maquina de coser pro',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 1,
          'availability_time': '2024-09-08 01:00:00',
        });

        // Sequences 4, 5
        batch.insert('sequences', {'name': 'Coser pantalon'});
        batch.insert('sequences', {'name': 'Coser camiseta'});

        // Tasks
        batch.insert('tasks', {
          'n_proc_units': '2024-09-08 04:30:00',
          'description': 'Coser pantalon',
          'sequence_id': 4,
          'machine_type_id': 4,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-09-08 06:30:00',
          'description': 'Coser camiseta',
          'sequence_id': 5,
          'machine_type_id': 4,
          'allow_preemption': 0,
        });

        // Order 4
        batch.insert('orders', {'reg_date': '2024-10-08'});

        // Jobs for Order 4
        batch.insert('jobs', {
          'job_id': 4,
          'sequence_id': 4,
          'order_id': 4,
          'amount': 3,
          'due_date': '2024-10-14',
          'priority': 1,
          'available_date': '2024-10-10 14:30',
        });
        batch.insert('jobs', {
          'job_id': 5,
          'sequence_id': 5,
          'order_id': 4,
          'amount': 2,
          'due_date': '2024-10-18',
          'priority': 1,
          'available_date': '2024-10-10 17:30',
        });
        batch.insert('jobs', {
          'job_id': 6,
          'sequence_id': 4,
          'order_id': 4,
          'amount': 5,
          'due_date': '2024-10-17',
          'priority': 1,
          'available_date': '2024-10-10 14:30',
        });
        batch.insert('jobs', {
          'job_id': 7,
          'sequence_id': 5,
          'order_id': 4,
          'amount': 7,
          'due_date': '2024-10-21',
          'priority': 1,
          'available_date': '2024-10-10 22:30',
        });

        await batch.commit(noResult: true);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          await _createMachineInactivitiesTable(db);
        }
        if (oldVersion < 3) {
          // Agregar environment y reglas de Open Shop
          await db.execute('''
            INSERT OR IGNORE INTO environments (environment_id, name) VALUES(7, 'OPEN SHOP');
            
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 1);
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 2);
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 3);
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 4);
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 5);
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 11);
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 12);
            INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 13);
          ''');
        }
        if (oldVersion < 5) {
          // Crear tabla job_preemption
          await db.execute('''
            CREATE TABLE job_preemption (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id INTEGER NOT NULL,
                machine_id INTEGER NOT NULL,
                can_preempt INTEGER NOT NULL CHECK (can_preempt IN (0, 1)),
                FOREIGN KEY (job_id) REFERENCES jobs(job_id),
                FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id),
                UNIQUE(job_id, machine_id)
            );
          ''');
        }
        if (oldVersion < 6) {
          // Crear tabla setup_times
          await db.execute('''
            CREATE TABLE IF NOT EXISTS setup_times (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                machine_id INTEGER NOT NULL,
                from_sequence_id INTEGER,
                to_sequence_id INTEGER NOT NULL,
                setup_duration_minutes INTEGER NOT NULL,
                FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id),
                FOREIGN KEY (from_sequence_id) REFERENCES sequences(sequence_id),
                FOREIGN KEY (to_sequence_id) REFERENCES sequences(sequence_id),
                UNIQUE(machine_id, from_sequence_id, to_sequence_id)
            );
          ''');
        }
        if (oldVersion < 7) {
          // Asegurar que el environment OPEN SHOP existe
          await db.execute('''
            INSERT OR IGNORE INTO environments (environment_id, name) VALUES(7, 'OPEN SHOP');
          ''');
        }
        if (oldVersion < 8) {
          // Migración a versión 8: convertir tiempos a porcentajes en MACHINES
          // Crear nueva tabla con esquema actualizado
          await db.execute('''
          CREATE TABLE MACHINES_NEW (
              machine_id INTEGER PRIMARY KEY AUTOINCREMENT,
              machine_name VARCHAR(100) NOT NULL,
              machine_type_id INTEGER NOT NULL,
              status_id INTEGER NOT NULL,
              processing_percentage REAL NOT NULL DEFAULT 100.0,
              preparation_percentage REAL NOT NULL DEFAULT 100.0,
              rest_percentage REAL NOT NULL DEFAULT 100.0,
              availability_time DATETIME NOT NULL,
              continue_capacity INTEGER,
              FOREIGN KEY (machine_type_id) REFERENCES machine_types(machine_type_id),
              FOREIGN KEY (status_id) REFERENCES status(status_id)
          );
        ''');
          // Migrar datos existentes con porcentaje 100%
          await db.execute('''
          INSERT INTO MACHINES_NEW (machine_id, machine_name, machine_type_id, status_id, 
              processing_percentage, preparation_percentage, rest_percentage, 
              availability_time, continue_capacity)
          SELECT machine_id, machine_name, machine_type_id, status_id, 
              100.0, 100.0, 100.0, 
              availability_time, continue_capacity
          FROM MACHINES;
        ''');
          await db.execute('DROP TABLE MACHINES;');
          await db.execute('ALTER TABLE MACHINES_NEW RENAME TO MACHINES;');

          // Actualizar job_task_machine_times para tener 3 columnas de tiempo
          await db.execute('''
          CREATE TABLE job_task_machine_times_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              job_id INTEGER NOT NULL,
              task_id INTEGER NOT NULL,
              machine_id INTEGER NOT NULL,
              processing_minutes INTEGER NOT NULL,
              preparation_minutes INTEGER NOT NULL DEFAULT 0,
              rest_minutes INTEGER NOT NULL DEFAULT 0,
              FOREIGN KEY (job_id) REFERENCES jobs(job_id),
              FOREIGN KEY (task_id) REFERENCES tasks(task_id),
              FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id),
              UNIQUE(job_id, task_id, machine_id)
          );
        ''');
          await db.execute('''
          INSERT INTO job_task_machine_times_new (id, job_id, task_id, machine_id, processing_minutes, preparation_minutes, rest_minutes)
          SELECT id, job_id, task_id, machine_id, duration_minutes, 0, 0 FROM job_task_machine_times;
        ''');
          await db.execute('DROP TABLE IF EXISTS job_task_machine_times;');
          await db.execute(
            'ALTER TABLE job_task_machine_times_new RENAME TO job_task_machine_times;',
          );
        }
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE jobs ADD COLUMN job_name VARCHAR(100);');
        }
      },
    );
    return _database!;
  }

  static Future<void> closeDatabaseConnection() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
