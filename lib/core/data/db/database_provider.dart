import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseProvider{
  static Database? _database;

  static Future<Database> open() async{
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, 'database.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''

        ''');
        await db.execute('''

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