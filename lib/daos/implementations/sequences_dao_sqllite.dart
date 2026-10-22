import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/repositories/models/sequence_model.dart';
import 'package:sqflite/sqflite.dart';


class SequencesDaoSqllite implements SequencesDao{

  final Database db;
  SequencesDaoSqllite(this.db);

  @override
  Future<int> createSequence(SequenceModel sequence,
      {DatabaseExecutor? executor}) async {
    try{
      int id = await (executor ?? db).insert("SEQUENCES", sequence.toJson());
      return id;
    }catch(e){
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<List<SequenceModel>> getSequences() async{
    try{
      return (await db.query('SEQUENCES'))
      .map((map) => SequenceModel.fromJson(map))
      .toList();
    }catch(e){
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<SequenceModel?> getSequenceById(int id) async{
    try{
      final sequences = (await db.query('SEQUENCES', where: 'sequence_id = ?', whereArgs: [id]));
      if(sequences.isNotEmpty){
        return  SequenceModel.fromJson(sequences[0]);
      }
      return null;
    }catch(e){
      throw LocalStorageFailure();
    }
  }
  
  @override
  Future<bool> deleteSequence(int id, {DatabaseExecutor? executor}) async {
    try{
      int numberDeleted = await (executor ?? db)
          .delete('SEQUENCES', where: 'sequence_id = ? ', whereArgs: [id]);
      return numberDeleted> 0;
    }catch(e){
      throw LocalStorageFailure();
    }
  }

  @override
  Future<void> renameSequence(int id, String name,
      {DatabaseExecutor? executor}) async {
    try {
      await (executor ?? db).update('SEQUENCES', {'name': name},
          where: 'sequence_id = ?', whereArgs: [id]);
    } catch (e) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<int> countJobsUsing(int id) async {
    try {
      final rows = await db.rawQuery(
          'SELECT COUNT(*) AS n FROM jobs WHERE sequence_id = ?', [id]);
      return (rows.first['n'] as int?) ?? 0;
    } catch (e) {
      throw LocalStorageFailure();
    }
  }
  
}
