import 'package:production_planning/core/errors/failure.dart';
import 'package:production_planning/daos/interfaces/sequences_dao.dart';
import 'package:production_planning/repositories/models/sequence_model.dart';
import 'package:sqflite/sqflite.dart';

class SequencesDaoSqllite implements SequencesDao {
  final Database db;
  SequencesDaoSqllite(this.db);

  @override
  Future<int> createSequence(SequenceModel sequence) async {
    try {
      int id = await db.insert("SEQUENCES", sequence.toJson());
      return id;
    } catch (e) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<List<SequenceModel>> getSequences() async {
    try {
      return (await db.query('SEQUENCES'))
          .map((map) => SequenceModel.fromJson(map))
          .toList();
    } catch (e) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<SequenceModel?> getSequenceById(int id) async {
    try {
      final sequences = (await db
          .query('SEQUENCES', where: 'sequence_id = ?', whereArgs: [id]));
      if (sequences.isNotEmpty) {
        return SequenceModel.fromJson(sequences[0]);
      }
      return null;
    } catch (e) {
      throw LocalStorageFailure();
    }
  }

  @override
  Future<bool> deleteSequence(int id) async {
    try {
      int numberDeleted = await db
          .delete('SEQUENCES', where: 'sequence_id = ? ', whereArgs: [id]);
      return numberDeleted > 0;
    } catch (e) {
      throw LocalStorageFailure();
    }
  }
}
