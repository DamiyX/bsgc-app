import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note_model.dart';

class NoteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<NoteModel>> getUserNotes(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('notes')
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => NoteModel.fromFirestore(doc))
              .toList();
        });
  }

  Future<void> saveNote(NoteModel note) async {
    await _firestore
        .collection('users')
        .doc(note.authorUid)
        .collection('notes')
        .doc(note.id)
        .set({
          'schemaVersion': 2,
          'authorUid': note.authorUid,
          'title': note.title.trim(),
          'body': note.body.trim(),
          'themeId': note.themeId,
          'createdAt': Timestamp.fromDate(note.createdAt),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<void> deleteNote(String userId, String noteId) async {
    await _firestore
        .collection('users')
        .doc(userId)
        .collection('notes')
        .doc(noteId)
        .delete();
  }
}
