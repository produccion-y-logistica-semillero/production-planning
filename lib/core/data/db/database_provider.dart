import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseProvider{
  static Database? _database;

  static Future<Database> open() async{
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'database.db');

    //I'm using this to manually locate my database and deleting it when I need new creation, it's not
    //the best way, but anyways, it works for me at the moment, can comment the line while we don't need it
    //print(path);

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
        /*await db.execute('''

        ''');*/
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