import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

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
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, '${workspace.replaceAll(' ', '')}.db');

    // Get the directory of the current executable (.exe)
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    // Create a text file in the same directory as the .exe
    final logFile = File(join(exeDir, 'database_path_log.txt'));

    // Write the database path to the text file
    await logFile.writeAsString('Database path: $path');
    //I'm using this to manually locate my database and deleting it when I need new creation, it's not
    //the best way, but anyways, it works for me at the moment, can comment the line while we don't need it
    print(path);

    _database = await openDatabase(path, version: 8,
        onCreate: (Database db, int version) async {
      await db.execute('''
          CREATE TABLE STATUS (
              status_id INTEGER PRIMARY KEY AUTOINCREMENT,
              status VARCHAR(100) NOT NULL
          );
        ''');
      await db.execute('''
          CREATE TABLE MACHINE_TYPES(
            machine_type_id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            description TEXT
          );
        ''');
      await db.execute('''
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
      await _createMachineInactivitiesTable(db);

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

      await db.execute('''
          CREATE TABLE sequences (
              sequence_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name VARCHAR(100) NOT NULL
          );
        ''');
      await db.execute('''
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

      await db.execute('''
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

      await db.execute('''
          CREATE TABLE environments (
              environment_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name VARCHAR(100) NOT NULL
          );
        ''');

      await db.execute('''
          CREATE TABLE dispatch_rules (
              dispatch_rule_id INTEGER PRIMARY KEY AUTOINCREMENT,
              name VARCHAR(100) NOT NULL
          );
        ''');

      await db.execute('''
          CREATE TABLE types_x_rules (
              type_rule_id INTEGER PRIMARY KEY AUTOINCREMENT,
              environment_id INTEGER NOT NULL,
              dispatch_rule_id INTEGER NOT NULL,
              FOREIGN KEY (environment_id) REFERENCES environments(environment_id),
              FOREIGN KEY (dispatch_rule_id) REFERENCES dispatch_rules(dispatch_rule_id)
          );
        ''');

      await db.execute('''
          CREATE TABLE orders (
              order_id INTEGER PRIMARY KEY AUTOINCREMENT,
              reg_date DATE NOT NULL
          );
        ''');
      await db.execute('''
          CREATE TABLE jobs (
              job_id INTEGER PRIMARY KEY AUTOINCREMENT,
              sequence_id INTEGER NOT NULL,
              order_id INTEGER NOT NULL,
              amount INTEGER NOT NULL,
              due_date DATE NOT NULL,
              available_date DATE NOT NULL,
              priority INTEGER NOT NULL,
              FOREIGN KEY (sequence_id) REFERENCES sequences(sequence_id),
              FOREIGN KEY (order_id) REFERENCES orders(order_id)
          );
        ''');

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

      await db.execute('''
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

      //DML TO POBLATE THE DATABASE BY DEFAULT FOR TESTING
      await db.execute('''
          -- Insert default statuses
          INSERT INTO status (status) VALUES ('Active');
          INSERT INTO status (status) VALUES ('Inactive');
          INSERT INTO status (status) VALUES ('Maintenance');

          ---------------------------------------------------------------------------------------------------------------------------
          --------------------------THIS INFO IS FUNDAMENTAL, ENVIRONMENTS AND DISPATCH RULES HAS TO BE INSERTED EVEN IN PRODUCTION
          ---------------------------------------------------------------------------------------------------------------------------
          -- Insert environments
          INSERT INTO environments (name) VALUES('SINGLE MACHINE');       --ID 1
          INSERT INTO environments (name) VALUES('PARALLEL MACHINES');    --ID 2
          INSERT INTO environments (name) VALUES('FLOW SHOP');            --ID 3
          INSERT INTO environments (name) VALUES('FLEXIBLE FLOW SHOP');   --ID 4
          INSERT INTO environments (name) VALUES('JOB SHOP');             --ID 5
          INSERT INTO environments (name) VALUES('FLEXIBLE JOB SHOP');    --ID 6
          INSERT INTO environments (name) VALUES('OPEN SHOP');            --ID 7

          -- Insert dispatch rules
          ------ SINGLE MACHINE RULES
          INSERT INTO dispatch_rules (name) VALUES('EDD');                --ID 1
          INSERT INTO dispatch_rules (name) VALUES('SPT');                --ID 2
          INSERT INTO dispatch_rules (name) VALUES('LPT');                --ID 3
          INSERT INTO dispatch_rules (name) VALUES('FIFO');               --ID 4
          INSERT INTO dispatch_rules (name) VALUES('WSPT');               --ID 5
          INSERT INTO dispatch_rules (name) VALUES('EDD_ADAPTADO');       --ID 6
          INSERT INTO dispatch_rules (name) VALUES('SPT_ADAPTADO');       --ID 7
          INSERT INTO dispatch_rules (name) VALUES('LPT_ADAPTADO');       --ID 8
          INSERT INTO dispatch_rules (name) VALUES('FIFO_ADAPTADO');      --ID 9
          INSERT INTO dispatch_rules (name) VALUES('WSPT_ADAPTADO');      --ID 10
          INSERT INTO dispatch_rules (name) VALUES('MINSLACK');           --ID 11
          INSERT INTO dispatch_rules (name) VALUES('CR');                 --ID 12
          INSERT INTO dispatch_rules (name) VALUES('ATCS');               --ID 13

          ------ PARALLEL MACHINE RULES
          INSERT INTO dispatch_rules (name) VALUES('FIFO');  --ID 14
          INSERT INTO dispatch_rules (name) VALUES('SPT_ADAPTADO');  --ID 15
          INSERT INTO dispatch_rules (name) VALUES('EDD_ADAPTADO');  --ID 16
          INSERT INTO dispatch_rules (name) VALUES('LPT_ADAPTADO');  --ID 17
          INSERT INTO dispatch_rules (name) VALUES('FIFO_ADAPTADO'); --ID 18
          INSERT INTO dispatch_rules (name) VALUES('WSPT_ADAPTADO'); --ID 19
          INSERT INTO dispatch_rules (name) VALUES('CR');    --ID 20
          INSERT INTO dispatch_rules (name) VALUES('MS');    --ID 21
          INSERT INTO dispatch_rules (name) VALUES('ATCS');  --ID 22

          ------ FLOW SHOP RULES
          INSERT INTO dispatch_rules (name) VALUES('JOHNSON');  --ID 23
          ------ FLEXIBLE FLOW SHOP RULES
          --INSERT INTO dispatch_rules (name) VALUES('JOHNSON_2_MACHINES'); --ID 24
          --INSERT INTO dispatch_rules (name) VALUES('JOHNSON_CDS');       --ID 25 

-- Insert types_x_rules
------- SINGLE MACHINE RULES
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 1);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 2);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 3);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 4);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 5);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 6);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 7);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 8);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 9);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 10);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 11);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 12);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (1, 13);

------- PARALLEL MACHINE RULES
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 2);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 3);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 1);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 14);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 11);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 12);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 5);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 6);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 7);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 10);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 15);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 16);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 17);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 18);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 19);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 20);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 21);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (2, 22);

------- FLOW SHOP MACHINE RULES (SPT,EDD,LPT,FIFO,WSPT,SPTA,EDDA,LPTA,FIFOA,WSPTA,CR, MS,ATCS,JOHNSON,JOHNSON3,CDS)
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 1);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 2);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 3);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 4);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 5);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 6);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 7);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 8);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 9);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 10);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 11);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 12);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 13);

INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 23);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 24);



------- FLEXIBLE FLOW SHOP MACHINE RULES
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 1);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 2);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 3);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 4);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 5);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 6);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 7);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 8);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 9);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 10);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 12);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 13);

INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 21);

INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 23);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 24);

-------- FLEXIBLE JOB SHOP MACHINE RULES
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 1);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 2);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 3);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 4);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 5);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 12);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 13);

-------- OPEN SHOP MACHINE RULES
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 1);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 2);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 3);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 4);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 5);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 11);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 12);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (7, 13);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 21);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 25);

        ''');
    }, onUpgrade: (Database db, int oldVersion, int newVersion) async {
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
            'ALTER TABLE job_task_machine_times_new RENAME TO job_task_machine_times;');
      }
      // Versión 4: Base de datos limpia, sin datos de ejemplo
      // No se requiere migración de datos
    });
    return _database!;
  }

  static Future<void> closeDatabaseConnection() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
