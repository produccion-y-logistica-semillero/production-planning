import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
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

    // Log the database path for debugging purposes
    print('Database path: $path');

    _database = await openDatabase(
      path,
      version: 10,
      onCreate: (Database db, int version) async {
        final batch = db.batch();

        // ─── DDL ───────────────────────────────────────────────────────────────

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
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              predecessor_id INTEGER NOT NULL,
              successor_id INTEGER NOT NULL,
              sequence_id INTEGER NOT NULL,
              FOREIGN KEY (predecessor_id) REFERENCES tasks(task_id),
              FOREIGN KEY (successor_id) REFERENCES tasks(task_id),
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

        // ─── DML SEED ──────────────────────────────────────────────────────────

        // Status
        batch.insert('status', {'status': 'Active'});
        batch.insert('status', {'status': 'Inactive'});
        batch.insert('status', {'status': 'Maintenance'});

        // Machine Types (base)
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

        // Machines (base)
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

        // Sequences (base)
        batch.insert('sequences', {'name': 'Sequence Alpha'});
        batch.insert('sequences', {'name': 'Sequence Beta'});
        batch.insert('sequences', {'name': 'Sequence Gamma'});

        // Tasks (base)
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

        // ─── Environments ──────────────────────────────────────────────────────
        // IMPORTANT: environments and dispatch_rules must always be inserted,
        // including in production.
        batch.insert('environments', {
          'environment_id': 1,
          'name': 'SINGLE MACHINE',
        });
        batch.insert('environments', {
          'environment_id': 2,
          'name': 'PARALLEL MACHINES',
        });
        batch
            .insert('environments', {'environment_id': 3, 'name': 'FLOW SHOP'});
        batch.insert('environments', {
          'environment_id': 4,
          'name': 'FLEXIBLE FLOW SHOP',
        });
        batch.insert('environments', {'environment_id': 5, 'name': 'JOB SHOP'});
        batch.insert('environments', {
          'environment_id': 6,
          'name': 'FLEXIBLE JOB SHOP',
        });
        batch
            .insert('environments', {'environment_id': 7, 'name': 'OPEN SHOP'});
        batch.insert('environments', {
          'environment_id': 8,
          'name': 'FLEXIBLE OPEN SHOP',
        });

        // ─── Dispatch Rules ────────────────────────────────────────────────────
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
        batch
            .insert('dispatch_rules', {'dispatch_rule_id': 13, 'name': 'ATCS'});

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
        batch
            .insert('dispatch_rules', {'dispatch_rule_id': 22, 'name': 'ATCS'});

        // Flow Shop (ID 23)
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 23,
          'name': 'JOHNSON',
        });

        // Meta-heuristics (IDs 24-25)
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 24,
          'name': 'GENETICS',
        });
        batch.insert('dispatch_rules', {
          'dispatch_rule_id': 25,
          'name': 'TABU',
        });

        // ─── Types × Rules ─────────────────────────────────────────────────────
        void addRule(int envId, int ruleId) {
          batch.insert('types_x_rules', {
            'environment_id': envId,
            'dispatch_rule_id': ruleId,
          });
        }

        // 1: Single Machine
        for (final r in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 24, 25]) {
          addRule(1, r);
        }

        // 2: Parallel Machines
        for (final r in [
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
          25,
        ]) {
          addRule(2, r);
        }

        // 3: Flow Shop
        for (final r in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 23, 24]) {
          addRule(3, r);
        }

        // 4: Flexible Flow Shop
        for (final r in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 21, 23, 24]) {
          addRule(4, r);
        }

        // 5: Job Shop
        for (final r in [1, 2, 3, 4, 5, 12, 13, 24]) {
          addRule(5, r);
        }

        // 6: Flexible Job Shop
        for (final r in [1, 2, 3, 4, 5, 12, 13, 21, 24]) {
          addRule(6, r);
        }

        // 7: Open Shop
        for (final r in [1, 2, 3, 4, 5, 11, 12, 13, 24]) {
          addRule(7, r);
        }

        // 8: Flexible Open Shop
        for (final r in [1, 2, 3, 4, 5, 11, 12, 13, 24]) {
          addRule(8, r);
        }

        // ─── Orders & Jobs (base) ──────────────────────────────────────────────
        batch.insert('orders', {'order_id': 1, 'reg_date': '2024-09-08'});
        batch.insert('orders', {'order_id': 2, 'reg_date': '2024-09-07'});
        batch.insert('orders', {'order_id': 3, 'reg_date': '2024-09-06'});

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

        // ============================================================
        // EMPRESA 1: PANADERÍA Y PASTELERÍA "DELICIAS DEL DÍA"
        // ============================================================

        // --- Machine Types (Panadería, IDs 4-8) ---
        batch.insert('machine_types', {
          'machine_type_id': 4,
          'name': 'Mezclado y Amasado',
          'description': 'Estación de preparación de masas y mezclas base',
        });
        batch.insert('machine_types', {
          'machine_type_id': 5,
          'name': 'Formado y Moldeado',
          'description': 'Estación de conformado de piezas y divisiones',
        });
        batch.insert('machine_types', {
          'machine_type_id': 6,
          'name': 'Horneado',
          'description': 'Estación de cocción en hornos industriales',
        });
        batch.insert('machine_types', {
          'machine_type_id': 7,
          'name': 'Decorado y Acabado',
          'description': 'Estación de baños, glaseados y montaje de pasteles',
        });
        batch.insert('machine_types', {
          'machine_type_id': 8,
          'name': 'Enfriado y Empaque',
          'description': 'Estación de enfriamiento en bandas y empaque final',
        });

        // --- Machines (Panadería, IDs 4-13) ---
        batch.insert('machines', {
          'machine_id': 4,
          'machine_type_id': 4,
          'machine_name': 'Amasadora Industrial 50L',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 8,
          'availability_time': '2024-10-14 04:00:00',
        });
        batch.insert('machines', {
          'machine_id': 5,
          'machine_type_id': 4,
          'machine_name': 'Amasadora Rápida 20L',
          'status_id': 1,
          'processing_percentage': 95.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 5,
          'availability_time': '2024-10-14 05:00:00',
        });
        batch.insert('machines', {
          'machine_id': 6,
          'machine_type_id': 5,
          'machine_name': 'Moldeadora de Barras',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 4,
          'availability_time': '2024-10-14 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 7,
          'machine_type_id': 5,
          'machine_name': 'Divisora de Masa Redonda',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 6,
          'availability_time': '2024-10-14 06:30:00',
        });
        batch.insert('machines', {
          'machine_id': 8,
          'machine_type_id': 6,
          'machine_name': 'Horno de Carro 4 Niveles',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 90.0,
          'rest_percentage': 100.0,
          'continue_capacity': 10,
          'availability_time': '2024-10-14 05:00:00',
        });
        batch.insert('machines', {
          'machine_id': 9,
          'machine_type_id': 6,
          'machine_name': 'Horno de Convección Compacto',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 4,
          'availability_time': '2024-10-14 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 10,
          'machine_type_id': 7,
          'machine_name': 'Mesa de Decorado Refrigerada',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 3,
          'availability_time': '2024-10-14 07:00:00',
        });
        batch.insert('machines', {
          'machine_id': 11,
          'machine_type_id': 7,
          'machine_name': 'Máquina de Glaseado Automático',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 2,
          'availability_time': '2024-10-14 08:00:00',
        });
        batch.insert('machines', {
          'machine_id': 12,
          'machine_type_id': 8,
          'machine_name': 'Banda de Enfriamiento 5m',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 12,
          'availability_time': '2024-10-14 05:00:00',
        });
        batch.insert('machines', {
          'machine_id': 13,
          'machine_type_id': 8,
          'machine_name': 'Empacadora al Vacío con Etiquetado',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 6,
          'availability_time': '2024-10-14 08:00:00',
        });

        // --- Sequences (Panadería, IDs 4-7) ---
        batch.insert('sequences', {
          'sequence_id': 4,
          'name': 'Pan Artesanal de Molde',
        });
        batch.insert('sequences', {
          'sequence_id': 5,
          'name': 'Croissants de Mantequilla',
        });
        batch.insert('sequences', {
          'sequence_id': 6,
          'name': 'Pastel de Chocolate Familiar',
        });
        batch.insert('sequences', {
          'sequence_id': 7,
          'name': 'Galletas de Avena y Miel',
        });

        // --- Tasks (Panadería) ---
        // Seq 4: Pan Artesanal de Molde
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 04:30:00',
          'description': 'Mezclado de harina, agua, levadura y sal',
          'sequence_id': 4,
          'machine_type_id': 4,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 05:00:00',
          'description': 'Amasado desarrollo de gluten',
          'sequence_id': 4,
          'machine_type_id': 4,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 06:00:00',
          'description': 'Formado de barras para molde',
          'sequence_id': 4,
          'machine_type_id': 5,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 07:30:00',
          'description': 'Horneado lento 45 min',
          'sequence_id': 4,
          'machine_type_id': 6,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 08:30:00',
          'description': 'Enfriado y empaque en bolsas kraft',
          'sequence_id': 4,
          'machine_type_id': 8,
          'allow_preemption': 0,
        });

        // Seq 5: Croissants de Mantequilla
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 04:00:00',
          'description': 'Mezclado de masa base croissant',
          'sequence_id': 5,
          'machine_type_id': 4,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 05:30:00',
          'description': 'Laminado y formado de capas',
          'sequence_id': 5,
          'machine_type_id': 5,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 07:00:00',
          'description': 'Horneado dorado 35 min',
          'sequence_id': 5,
          'machine_type_id': 6,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 08:00:00',
          'description': 'Barnizado de almíbar de naranja',
          'sequence_id': 5,
          'machine_type_id': 7,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 08:30:00',
          'description': 'Enfriado y empaque en cajas',
          'sequence_id': 5,
          'machine_type_id': 8,
          'allow_preemption': 0,
        });

        // Seq 6: Pastel de Chocolate Familiar
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 06:00:00',
          'description': 'Preparación de bizcocho de chocolate',
          'sequence_id': 6,
          'machine_type_id': 4,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 07:00:00',
          'description': 'Horneado de bizcocho 50 min',
          'sequence_id': 6,
          'machine_type_id': 6,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 08:30:00',
          'description': 'Decorado con ganache y frutas',
          'sequence_id': 6,
          'machine_type_id': 7,
          'allow_preemption': 1,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 09:30:00',
          'description': 'Refrigeración y empaque especial',
          'sequence_id': 6,
          'machine_type_id': 8,
          'allow_preemption': 0,
        });

        // Seq 7: Galletas de Avena y Miel
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 05:00:00',
          'description': 'Mezclado de avena, miel y manteca',
          'sequence_id': 7,
          'machine_type_id': 4,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 06:00:00',
          'description': 'Formado y estampado de galletas',
          'sequence_id': 7,
          'machine_type_id': 5,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 07:00:00',
          'description': 'Horneado crujiente 25 min',
          'sequence_id': 7,
          'machine_type_id': 6,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'n_proc_units': '2024-10-14 08:00:00',
          'description': 'Enfriado y empaque en frascos',
          'sequence_id': 7,
          'machine_type_id': 8,
          'allow_preemption': 0,
        });

        // --- Orders (Panadería, IDs 4-6 reutilizando las existentes del branch 1 sería conflicto;
        //     aquí van los IDs correctos del branch 2) ---
        batch.insert('orders', {'order_id': 4, 'reg_date': '2024-10-14'});
        batch.insert('orders', {'order_id': 5, 'reg_date': '2024-10-15'});
        batch.insert('orders', {'order_id': 6, 'reg_date': '2024-10-16'});

        // --- Jobs (Panadería) ---
        // No explicit job_id: autoincrement continues from 4 after the 3 base jobs.
        batch.insert('jobs', {
          'sequence_id': 4,
          'order_id': 4,
          'amount': 50,
          'job_name': 'Lote Pan Integral Supermercado',
          'due_date': '2024-10-18',
          'priority': 2,
          'available_date': '2024-10-14 04:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 5,
          'order_id': 4,
          'amount': 30,
          'job_name': 'Lote Croissants Vitrina',
          'due_date': '2024-10-18',
          'priority': 3,
          'available_date': '2024-10-14 04:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 6,
          'order_id': 5,
          'amount': 5,
          'job_name': 'Pastel Cumpleaños El Rincón',
          'due_date': '2024-10-17',
          'priority': 1,
          'available_date': '2024-10-15 06:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 7,
          'order_id': 5,
          'amount': 120,
          'job_name': 'Galletas Avena Pedido Mayorista',
          'due_date': '2024-10-19',
          'priority': 2,
          'available_date': '2024-10-15 05:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 4,
          'order_id': 6,
          'amount': 25,
          'job_name': 'Pan Artesanal Evento Corporativo',
          'due_date': '2024-10-20',
          'priority': 1,
          'available_date': '2024-10-16 06:00:00',
        });

        // --- Setup Times (Panadería) ---
        batch.insert('setup_times', {
          'machine_id': 4,
          'from_sequence_id': 4,
          'to_sequence_id': 5,
          'setup_duration_minutes': 15,
        });
        batch.insert('setup_times', {
          'machine_id': 8,
          'from_sequence_id': 4,
          'to_sequence_id': 6,
          'setup_duration_minutes': 20,
        });
        batch.insert('setup_times', {
          'machine_id': 6,
          'from_sequence_id': 5,
          'to_sequence_id': 7,
          'setup_duration_minutes': 10,
        });

        // --- Machine Inactivities (Panadería) ---
        batch.insert('machine_inactivities', {
          'machine_id': 8,
          'name': 'Mantenimiento Horno Carro',
          'start_time': '06:00',
          'duration_minutes': 120,
          'monday': 1,
          'tuesday': 0,
          'wednesday': 0,
          'thursday': 0,
          'friday': 0,
          'saturday': 0,
          'sunday': 0,
        });
        batch.insert('machine_inactivities', {
          'machine_id': 4,
          'name': 'Limpieza Preventiva Amasadora',
          'start_time': '14:00',
          'duration_minutes': 60,
          'monday': 0,
          'tuesday': 0,
          'wednesday': 0,
          'thursday': 0,
          'friday': 1,
          'saturday': 0,
          'sunday': 0,
        });

        // --- Job Preemption (Panadería) ---
        // Base jobs take IDs 1-3; bakery jobs take 4-8 in insertion order:
        //   4=Pan Integral, 5=Croissants, 6=Pastel, 7=Galletas, 8=Pan Corporativo
        batch.insert('job_preemption', {
          'job_id': 6, // Pastel Cumpleaños → mesa de decorado
          'machine_id': 10,
          'can_preempt': 1,
        });
        batch.insert('job_preemption', {
          'job_id': 4, // Pan Integral → horno de carro
          'machine_id': 8,
          'can_preempt': 0,
        });

        // ============================================================
        // EMPRESA 2: MANUFACTURA TEXTIL "TELASINDUSTRIAL"
        // ============================================================

        // --- Machine Types (Textiles, IDs 9-17) ---
        batch.insert('machine_types', {
          'machine_type_id': 9,
          'name': 'Planchado',
          'description': 'Máquina de planchado industrial para telas',
        });
        batch.insert('machine_types', {
          'machine_type_id': 10,
          'name': 'Corte',
          'description': 'Máquina de corte automático',
        });
        batch.insert('machine_types', {
          'machine_type_id': 11,
          'name': 'Teñido',
          'description': 'Máquina de teñido por lotes',
        });
        batch.insert('machine_types', {
          'machine_type_id': 12,
          'name': 'Lavado',
          'description': 'Máquina lavadora industrial',
        });
        batch.insert('machine_types', {
          'machine_type_id': 13,
          'name': 'Secado',
          'description': 'Secadora industrial de tambor',
        });
        batch.insert('machine_types', {
          'machine_type_id': 14,
          'name': 'Confección',
          'description': 'Estación de costura y confección',
        });
        batch.insert('machine_types', {
          'machine_type_id': 15,
          'name': 'Tintorería Clásica',
          'description': 'Máquina de tintura tradicional con 1 unidad',
        });
        batch.insert('machine_types', {
          'machine_type_id': 16,
          'name': 'Enjuague Industrial',
          'description': 'Máquina de enjuague automático con 1 unidad',
        });
        batch.insert('machine_types', {
          'machine_type_id': 17,
          'name': 'Prensado al Vapor',
          'description': 'Prensa industrial de vapor con 1 unidad',
        });

        // --- Machines (Textiles, IDs 14-26) ---
        batch.insert('machines', {
          'machine_id': 14,
          'machine_type_id': 9,
          'machine_name': 'Planchadora Industrial XL',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 5,
          'availability_time': '2024-10-20 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 15,
          'machine_type_id': 10,
          'machine_name': 'Cortadora Automática 1',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 8,
          'availability_time': '2024-10-20 07:00:00',
        });
        batch.insert('machines', {
          'machine_id': 16,
          'machine_type_id': 10,
          'machine_name': 'Cortadora Automática 2',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 8,
          'availability_time': '2024-10-20 07:30:00',
        });
        batch.insert('machines', {
          'machine_id': 17,
          'machine_type_id': 11,
          'machine_name': 'Teñidor Industrial 1',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 10,
          'availability_time': '2024-10-20 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 18,
          'machine_type_id': 12,
          'machine_name': 'Lavadora Industrial 1',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 10,
          'availability_time': '2024-10-20 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 19,
          'machine_type_id': 13,
          'machine_name': 'Secadora Industrial 1',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 12,
          'availability_time': '2024-10-20 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 20,
          'machine_type_id': 14,
          'machine_name': 'Estación Costura 1',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 6,
          'availability_time': '2024-10-20 08:00:00',
        });
        batch.insert('machines', {
          'machine_id': 21,
          'machine_type_id': 14,
          'machine_name': 'Estación Costura 2',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 6,
          'availability_time': '2024-10-20 08:30:00',
        });
        batch.insert('machines', {
          'machine_id': 22,
          'machine_type_id': 11,
          'machine_name': 'Teñidor Industrial 2',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 10,
          'availability_time': '2024-10-20 06:30:00',
        });
        batch.insert('machines', {
          'machine_id': 23,
          'machine_type_id': 12,
          'machine_name': 'Lavadora Industrial 2',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 10,
          'availability_time': '2024-10-20 06:30:00',
        });
        batch.insert('machines', {
          'machine_id': 24,
          'machine_type_id': 15,
          'machine_name': 'Tintorería Clásica Principal',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 8,
          'availability_time': '2024-10-22 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 25,
          'machine_type_id': 16,
          'machine_name': 'Enjuague Principal',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 8,
          'availability_time': '2024-10-22 06:00:00',
        });
        batch.insert('machines', {
          'machine_id': 26,
          'machine_type_id': 17,
          'machine_name': 'Prensa de Vapor Principal',
          'status_id': 1,
          'processing_percentage': 100.0,
          'preparation_percentage': 100.0,
          'rest_percentage': 100.0,
          'continue_capacity': 10,
          'availability_time': '2024-10-22 06:00:00',
        });

        // --- Sequences (Textiles, IDs 8-12) ---
        batch.insert('sequences', {
          'sequence_id': 8,
          'name': 'Planchado Simple Camisetas',
        });
        batch.insert('sequences', {
          'sequence_id': 9,
          'name': 'Corte de Telas Estándar',
        });
        batch.insert('sequences', {
          'sequence_id': 10,
          'name': 'Ciclo Teñido Completo',
        });
        batch.insert('sequences', {
          'sequence_id': 11,
          'name': 'Confección Camisas Premium',
        });
        batch.insert('sequences', {
          'sequence_id': 12,
          'name': 'Ciclo Tintura-Enjuague-Prensado',
        });

        // --- Tasks (Textiles, IDs 22-32) ---
        // Seq 8: Single Machine
        batch.insert('tasks', {
          'task_id': 22,
          'n_proc_units': '1970-01-01 00:30:00',
          'description': 'Planchado de camisetas',
          'sequence_id': 8,
          'machine_type_id': 9,
          'allow_preemption': 0,
        });

        // Seq 9: Parallel Machines
        batch.insert('tasks', {
          'task_id': 23,
          'n_proc_units': '1970-01-01 00:45:00',
          'description': 'Corte automático de telas',
          'sequence_id': 9,
          'machine_type_id': 10,
          'allow_preemption': 0,
        });

        // Seq 10: Flow Shop
        batch.insert('tasks', {
          'task_id': 24,
          'n_proc_units': '1970-01-01 01:00:00',
          'description': 'Teñido de telas',
          'sequence_id': 10,
          'machine_type_id': 11,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'task_id': 25,
          'n_proc_units': '1970-01-01 00:45:00',
          'description': 'Lavado de telas teñidas',
          'sequence_id': 10,
          'machine_type_id': 12,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'task_id': 26,
          'n_proc_units': '1970-01-01 01:15:00',
          'description': 'Secado en tambor industrial',
          'sequence_id': 10,
          'machine_type_id': 13,
          'allow_preemption': 0,
        });

        // Seq 11: Flexible Flow Shop
        batch.insert('tasks', {
          'task_id': 27,
          'n_proc_units': '1970-01-01 00:50:00',
          'description': 'Corte de piezas premium',
          'sequence_id': 11,
          'machine_type_id': 10,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'task_id': 28,
          'n_proc_units': '1970-01-01 02:00:00',
          'description': 'Confección de camisas',
          'sequence_id': 11,
          'machine_type_id': 14,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'task_id': 29,
          'n_proc_units': '1970-01-01 00:30:00',
          'description': 'Control de calidad y planchado final',
          'sequence_id': 11,
          'machine_type_id': 9,
          'allow_preemption': 0,
        });

        // Seq 12: Flow Shop (Tintura → Enjuague → Prensado)
        batch.insert('tasks', {
          'task_id': 30,
          'n_proc_units': '1970-01-01 01:00:00',
          'description': 'Tintura de lote',
          'sequence_id': 12,
          'machine_type_id': 15,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'task_id': 31,
          'n_proc_units': '1970-01-01 00:30:00',
          'description': 'Enjuague tras tintura',
          'sequence_id': 12,
          'machine_type_id': 16,
          'allow_preemption': 0,
        });
        batch.insert('tasks', {
          'task_id': 32,
          'n_proc_units': '1970-01-01 00:45:00',
          'description': 'Prensado al vapor',
          'sequence_id': 12,
          'machine_type_id': 17,
          'allow_preemption': 0,
        });

        // --- Task Dependencies (Textiles) ---
        // Seq 10: Teñido → Lavado → Secado
        batch.insert('TaskDependency', {
          'predecessor_id': 24,
          'successor_id': 25,
          'sequence_id': 10,
        });
        batch.insert('TaskDependency', {
          'predecessor_id': 25,
          'successor_id': 26,
          'sequence_id': 10,
        });

        // Seq 11: Corte → Confección → Control
        batch.insert('TaskDependency', {
          'predecessor_id': 27,
          'successor_id': 28,
          'sequence_id': 11,
        });
        batch.insert('TaskDependency', {
          'predecessor_id': 28,
          'successor_id': 29,
          'sequence_id': 11,
        });

        // Seq 12: Tintura → Enjuague → Prensado
        batch.insert('TaskDependency', {
          'predecessor_id': 30,
          'successor_id': 31,
          'sequence_id': 12,
        });
        batch.insert('TaskDependency', {
          'predecessor_id': 31,
          'successor_id': 32,
          'sequence_id': 12,
        });

        // --- Orders (Textiles, IDs 7-10) ---
        batch.insert('orders', {'order_id': 7, 'reg_date': '2024-10-20'});
        batch.insert('orders', {'order_id': 8, 'reg_date': '2024-10-21'});
        batch.insert('orders', {'order_id': 9, 'reg_date': '2024-10-22'});
        batch.insert('orders', {'order_id': 10, 'reg_date': '2024-10-23'});

        // --- Jobs (Textiles) ---
        // No explicit job_id: autoincrement continues from 9
        // (3 base + 5 bakery = 8 already inserted → textile starts at 9).

        // Order 7: Single Machine (seq 8)
        batch.insert('jobs', {
          'sequence_id': 8,
          'order_id': 7,
          'amount': 100,
          'job_name': 'Camisetas Blancas Lote A',
          'due_date': '2024-10-25',
          'priority': 2,
          'available_date': '2024-10-20 06:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 8,
          'order_id': 7,
          'amount': 80,
          'job_name': 'Camisetas Negras Lote B',
          'due_date': '2024-10-25',
          'priority': 2,
          'available_date': '2024-10-20 06:30:00',
        });

        // Order 8: Parallel Machines (seq 9)
        batch.insert('jobs', {
          'sequence_id': 9,
          'order_id': 8,
          'amount': 60,
          'job_name': 'Corte Mezclilla Lote A',
          'due_date': '2024-10-24',
          'priority': 1,
          'available_date': '2024-10-20 07:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 9,
          'order_id': 8,
          'amount': 50,
          'job_name': 'Corte Algodón Lote B',
          'due_date': '2024-10-24',
          'priority': 1,
          'available_date': '2024-10-20 07:30:00',
        });

        // Order 9: Flow Shop (seq 12)
        batch.insert('jobs', {
          'sequence_id': 12,
          'order_id': 9,
          'amount': 75,
          'job_name': 'Tintura Azul Marino',
          'due_date': '2024-10-26',
          'priority': 1,
          'available_date': '2024-10-22 06:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 12,
          'order_id': 9,
          'amount': 60,
          'job_name': 'Tintura Rojo Intenso',
          'due_date': '2024-10-26',
          'priority': 1,
          'available_date': '2024-10-22 06:30:00',
        });

        // Order 10: Flexible Flow Shop (seq 11)
        batch.insert('jobs', {
          'sequence_id': 11,
          'order_id': 10,
          'amount': 40,
          'job_name': 'Camisas Blancas Premium',
          'due_date': '2024-10-27',
          'priority': 1,
          'available_date': '2024-10-23 08:00:00',
        });
        batch.insert('jobs', {
          'sequence_id': 11,
          'order_id': 10,
          'amount': 35,
          'job_name': 'Camisas Azules Premium',
          'due_date': '2024-10-27',
          'priority': 1,
          'available_date': '2024-10-23 08:30:00',
        });

        await batch.commit(noResult: true);
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        // NOTE: migrations run in order from oldVersion up to newVersion.
        // Each block is idempotent (uses INSERT OR IGNORE / IF NOT EXISTS).

        if (oldVersion < 2) {
          await _createMachineInactivitiesTable(db);
        }

        if (oldVersion < 3) {
          await db.execute('''
            INSERT OR IGNORE INTO environments (environment_id, name)
            VALUES(7, 'OPEN SHOP');
          ''');
          await db.execute('''
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 1);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 2);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 3);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 4);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 5);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 11);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 12);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 13);
          ''');
        }

        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS job_preemption (
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
          await db.execute('''
            INSERT OR IGNORE INTO environments (environment_id, name)
            VALUES(7, 'OPEN SHOP');
          ''');
        }

        if (oldVersion < 8) {
          // Convert machine time columns to percentage columns
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
            INSERT INTO job_task_machine_times_new
                (id, job_id, task_id, machine_id, processing_minutes, preparation_minutes, rest_minutes)
            SELECT id, job_id, task_id, machine_id, duration_minutes, 0, 0
            FROM job_task_machine_times;
          ''');
          await db.execute('DROP TABLE IF EXISTS job_task_machine_times;');
          await db.execute(
            'ALTER TABLE job_task_machine_times_new RENAME TO job_task_machine_times;',
          );
        }

        if (oldVersion < 9) {
          await db.execute(
            'ALTER TABLE jobs ADD COLUMN job_name VARCHAR(100);',
          );
          try {
            await db.execute(
              'ALTER TABLE order_setup_matrix ADD COLUMN machine_name TEXT NOT NULL DEFAULT "";',
            );
          } catch (_) {
            // Column already exists or table not present yet — safe to ignore.
          }
        }

        if (oldVersion < 10) {
          // Ensure all environments introduced after v3 exist
          await db.execute('''
            INSERT OR IGNORE INTO environments (environment_id, name) VALUES(5, 'JOB SHOP');
            INSERT OR IGNORE INTO environments (environment_id, name) VALUES(6, 'FLEXIBLE JOB SHOP');
            INSERT OR IGNORE INTO environments (environment_id, name) VALUES(7, 'OPEN SHOP');
            INSERT OR IGNORE INTO environments (environment_id, name) VALUES(8, 'FLEXIBLE OPEN SHOP');
          ''');

          // Ensure all dispatch rules introduced in later branches exist
          await db.execute('''
            INSERT OR IGNORE INTO dispatch_rules (dispatch_rule_id, name) VALUES (11, 'MINSLACK');
            INSERT OR IGNORE INTO dispatch_rules (dispatch_rule_id, name) VALUES (12, 'CR');
            INSERT OR IGNORE INTO dispatch_rules (dispatch_rule_id, name) VALUES (13, 'ATCS');
            INSERT OR IGNORE INTO dispatch_rules (dispatch_rule_id, name) VALUES (21, 'MS');
            INSERT OR IGNORE INTO dispatch_rules (dispatch_rule_id, name) VALUES (23, 'JOHNSON');
            INSERT OR IGNORE INTO dispatch_rules (dispatch_rule_id, name) VALUES (24, 'GENETICS');
            INSERT OR IGNORE INTO dispatch_rules (dispatch_rule_id, name) VALUES (25, 'TABU');
          ''');

          // Job Shop
          await db.execute('''
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 1);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 2);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 3);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 4);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 5);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 12);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 13);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (5, 24);
          ''');

          // Flexible Job Shop
          await db.execute('''
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 1);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 2);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 3);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 4);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 5);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 12);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 13);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 21);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 24);
          ''');

          // Open Shop
          await db.execute('''
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 1);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 2);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 3);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 4);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 5);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 11);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 12);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 13);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 24);
          ''');

          // Flexible Open Shop
          await db.execute('''
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 1);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 2);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 3);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 4);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 5);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 11);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 12);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 13);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (8, 24);
          ''');

          // Single Machine: ensure TABU rule is linked (added in branch 1)
          await db.execute('''
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 25);
            INSERT OR IGNORE INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 25);
          ''');
        }
      },
    );

    // Tables created outside the versioned onCreate/onUpgrade so they are
    // always guaranteed to exist on every open() call.
    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS job_machine_states (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          job_id INTEGER NOT NULL,
          machine_type_id INTEGER NOT NULL,
          state_char TEXT NOT NULL,
          FOREIGN KEY (job_id) REFERENCES jobs(job_id)
      );
    ''');

    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS orders (
          order_id INTEGER PRIMARY KEY AUTOINCREMENT,
          reg_date DATE NOT NULL
      );
    ''');

    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS jobs (
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

    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS job_preemption (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          job_id INTEGER NOT NULL,
          machine_id INTEGER NOT NULL,
          can_preempt INTEGER NOT NULL CHECK (can_preempt IN (0, 1)),
          FOREIGN KEY (job_id) REFERENCES jobs(job_id),
          FOREIGN KEY (machine_id) REFERENCES MACHINES(machine_id),
          UNIQUE(job_id, machine_id)
      );
    ''');
    
    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS order_setup_matrix (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          machine_name TEXT NOT NULL DEFAULT "",
          order_id INTEGER NOT NULL,
          from_state TEXT NOT NULL DEFAULT "",
          to_state TEXT NOT NULL DEFAULT "",
          duration_minutes INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (order_id) REFERENCES orders(order_id)
      );
    ''');

    await _ensureOrderSetupMatrixSchema(_database!);

    return _database!;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Adds any columns that may be missing from [order_setup_matrix] due to
  /// older schema versions being upgraded incrementally.
  static Future<void> _ensureOrderSetupMatrixSchema(Database db) async {
    final columns = await _getTableColumns(db, 'order_setup_matrix');
    if (columns.isEmpty) return;

    Future<void> addIfMissing(String col, String def) async {
      if (!columns.contains(col)) {
        await db.execute(
          'ALTER TABLE order_setup_matrix ADD COLUMN $col $def;',
        );
      }
    }

    await addIfMissing('machine_name', 'TEXT NOT NULL DEFAULT ""');
    await addIfMissing('from_state', 'TEXT NOT NULL DEFAULT ""');
    await addIfMissing('to_state', 'TEXT NOT NULL DEFAULT ""');
    await addIfMissing('duration_minutes', 'INTEGER NOT NULL DEFAULT 0');
  }

  static Future<List<String>> _getTableColumns(
    Database db,
    String table,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table);');
    return info.map((row) => row['name'] as String).toList();
  }

  static Future<void> closeDatabaseConnection() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
