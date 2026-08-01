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
        .limit(100)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => NoteModel.fromFirestore(doc))
              .toList();
        });
  }

  Future<NotePage> getUserNotePage({
    required String userId,
    DocumentSnapshot<Map<String, dynamic>>? after,
    int pageSize = 50,
  }) async {
    final boundedPageSize = pageSize.clamp(1, 100).toInt();
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(userId)
        .collection('notes')
        .orderBy('updatedAt', descending: true)
        .limit(boundedPageSize + 1);
    if (after != null) query = query.startAfterDocument(after);

    final snapshot = await query.get();
    final documents = snapshot.docs.take(boundedPageSize).toList();
    return NotePage(
      notes: documents.map(NoteModel.fromFirestore).toList(growable: false),
      cursor: documents.lastOrNull,
      hasMore: snapshot.docs.length > boundedPageSize,
    );
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

class NotePage {
  final List<NoteModel> notes;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;

  const NotePage({
    required this.notes,
    required this.cursor,
    required this.hasMore,
  });
}
