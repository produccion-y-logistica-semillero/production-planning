import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class SQLLiteDatabaseProvider{
  static Database? _database;

  static Future<Database> open() async{
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'database.db');

    //I'm using this to manually locate my database and deleting it when I need new creation, it's not
    //the best way, but anyways, it works for me at the moment, can comment the line while we don't need it
    print(path);

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
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
              machine_type_id INTEGER NOT NULL,
              status_id INTEGER NOT NULL,
              processing_time DATETIME NOT NULL,
              preparation_time DATETIME NOT NULL,
              rest_time DATETIME,
              continue_capacity INTEGER,
              FOREIGN KEY (machine_type_id) REFERENCES machine_type(machine_type_id),
              FOREIGN KEY (status_id) REFERENCES status(status_id)
          );
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