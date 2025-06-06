import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SQLLiteDatabaseProvider{
  static Database? _database;

  static Future<Database> open(String workspace) async{
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

    _database = await openDatabase(
      path,
      version: 1,
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
              processing_time DATETIME NOT NULL,
              preparation_time DATETIME NOT NULL,
              rest_time DATETIME,
              continue_capacity INTEGER,
              FOREIGN KEY (machine_type_id) REFERENCES machine_types(machine_type_id),
              FOREIGN KEY (status_id) REFERENCES status(status_id)
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

        //DML TO POBLATE THE DATABASE BY DEFAULT FOR TESTING
        await db.execute('''
          -- Insert default statuses
          INSERT INTO status (status) VALUES ('Active');
          INSERT INTO status (status) VALUES ('Inactive');
          INSERT INTO status (status) VALUES ('Maintenance');

          -- Insert default machine types
          INSERT INTO machine_types (name, description) VALUES ('Type A', 'Basic machine type A');
          INSERT INTO machine_types (name, description) VALUES ('Type B', 'Advanced machine type B');
          INSERT INTO machine_types (name, description) VALUES ('Type C', 'High capacity machine type C');

          -- Insert default machines
          INSERT INTO machines (machine_type_id, machine_name, status_id, processing_time, preparation_time, rest_time, continue_capacity)
          VALUES (1,'type A 1', 1, '2024-09-08 10:00:00', '2024-09-08 09:30:00', '2024-09-08 12:00:00', 5);

          INSERT INTO machines (machine_type_id,machine_name, status_id, processing_time, preparation_time, rest_time, continue_capacity)
          VALUES (2, 'type B 1', 1, '2024-09-08 11:00:00', '2024-09-08 10:00:00', '2024-09-08 13:00:00', 3);

          INSERT INTO machines (machine_type_id, machine_name, status_id, processing_time, preparation_time, rest_time, continue_capacity)
          VALUES (3,'type C 1', 2, '2024-09-08 12:00:00', '2024-09-08 11:30:00', NULL, 7);

          -- Insert default sequences
          INSERT INTO sequences (name) VALUES ('Sequence Alpha');
          INSERT INTO sequences (name) VALUES ('Sequence Beta');
          INSERT INTO sequences (name) VALUES ('Sequence Gamma');

          -- Insert default tasks
          INSERT INTO tasks ( n_proc_units, description, sequence_id, machine_type_id)
          VALUES ('2024-09-08 09:00:00', 'Task 1 description', 1, 1);

          INSERT INTO tasks (n_proc_units, description, sequence_id, machine_type_id)
          VALUES ('2024-09-08 10:00:00', 'Task 2 description', 2, 2);

          INSERT INTO tasks (n_proc_units, description, sequence_id, machine_type_id)
          VALUES ('2024-09-08 11:00:00', 'Task 3 description', 3, 3);

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
          INSERT INTO dispatch_rules (name) VALUES('JOHNSON3'); --ID 24
          INSERT INTO dispatch_rules (name) VALUES('CDS');      --ID 25

          ------ FLEXIBLE FLOW SHOP RULES
          --INSERT INTO dispatch_rules (name) VALUES('JOHNSON_2_MACHINES');
          --INSERT INTO dispatch_rules (name) VALUES('JOHNSON_CDS');      

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
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 14);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 15);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 16);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 17);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 18);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 19);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 20);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 21);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 22);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 23);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 24);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (3, 25);


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
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 11);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 12);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 13);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 14);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 15);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 16);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 17);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 18);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 19);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 20);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 21);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 22);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 23);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 24);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 25);
-- INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 26);
-- INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (4, 27);

-------- FLEXIBLE JOB SHOP MACHINE RULES
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 2);
INSERT INTO types_x_rules(environment_id, dispatch_rule_id) VALUES (6, 3);


          ---------------------------------------------------------------------------------------------------------------------------
          ---------------------------------------------------------------------------------------------------------------------------

          -- Insert default orders
          INSERT INTO orders (reg_date) VALUES ('2024-09-08');
          INSERT INTO orders (reg_date) VALUES ('2024-09-07');
          INSERT INTO orders (reg_date) VALUES ('2024-09-06');

          -- Insert default jobs (associating sequences with orders)
          INSERT INTO jobs (sequence_id, order_id, amount, due_date, priority, available_date)
          VALUES (1, 1, 100, '2024-09-10', 1, '2024-09-10');

          INSERT INTO jobs (sequence_id, order_id, amount, due_date, priority, available_date)
          VALUES (2, 2, 200, '2024-09-11', 2, '2024-09-10' );

          INSERT INTO jobs (sequence_id, order_id, amount, due_date, priority, available_date)
          VALUES (3, 3, 150, '2024-09-12', 3, '2024-09-10');


          ---------------------------------------------------------------------------------------------------------------------------
          -------------------------------------------------CUSTOM ORDERS TO CHECK----------------------------------------------------
          ---------------------------------------------------------------------------------------------------------------------------

           -- SINGLE MACHINE ORDER

          --machine type ID = 4
          INSERT INTO machine_types (name, description) VALUES ('Maquina coser', 'Maquina para coser prendas de vestir');

          --machine ID = 4
          INSERT INTO machines (machine_type_id, machine_name, status_id, processing_time, preparation_time, rest_time, continue_capacity)
          VALUES (4,'Maquina de coser pro', 1, '2024-09-08 01:00:00', '2024-09-08 00:00:00', '2024-09-08 00:00:00', 1);


          INSERT INTO sequences (name) VALUES ('Coser pantalon'); --sequence ID = 4
          INSERT INTO sequences (name) VALUES ('Coser camiseta'); --sequence ID = 5

          INSERT INTO tasks (n_proc_units, description, sequence_id, machine_type_id)
          VALUES ('2024-09-08 04:30:00', 'Coser pantalon', 4, 4);

          INSERT INTO tasks (n_proc_units, description, sequence_id, machine_type_id)
          VALUES ('2024-09-08 06:30:00', 'Coser camiseta', 5, 4);

          INSERT INTO orders (reg_date) VALUES ('2024-10-08');  --order ID = 4

          INSERT INTO jobs (sequence_id, order_id, amount, due_date, priority, available_date)
          VALUES (4, 4, 3, '2024-10-14', 1, '2024-10-10 14:30');
          INSERT INTO jobs (sequence_id, order_id, amount, due_date, priority, available_date)
          VALUES (5, 4, 2, '2024-10-18', 1, '2024-10-10 17:30');
          INSERT INTO jobs (sequence_id, order_id, amount, due_date, priority, available_date)
          VALUES (4, 4, 5, '2024-10-17', 1, '2024-10-10 14:30');
          INSERT INTO jobs (sequence_id, order_id, amount, due_date, priority, available_date)
          VALUES (5, 4, 7, '2024-10-21', 1, '2024-10-10 22:30');

        ''');
      }
    );
    return _database!;
  }

  static Future<void> closeDatabaseConnection() async{
    if(_database != null){
      await _database!.close();
      _database = null;
    }
  }

}