import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/note_model.dart';
import 'firestore_commit_service.dart';

abstract interface class NoteWriter {
  Future<void> saveNote(NoteModel note);
}

class NoteService implements NoteWriter {
  final FirebaseFirestore _firestore;

  NoteService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

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

  @override
  Future<void> saveNote(NoteModel note) async {
    final reference = _firestore
        .collection('users')
        .doc(note.authorUid)
        .collection('notes')
        .doc(note.id);
    await reference.set({
      'schemaVersion': 2,
      'authorUid': note.authorUid,
      'title': note.title.trim(),
      'body': note.body.trim(),
      'themeId': note.themeId,
      'createdAt': Timestamp.fromDate(note.createdAt),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await waitForDocumentCommit(reference);
  }

  Future<void> deleteNote(String userId, String noteId) async {
    final reference = _firestore
        .collection('users')
        .doc(userId)
        .collection('notes')
        .doc(noteId);
    await reference.delete();
    await waitForDocumentCommit(reference);
  }
}
