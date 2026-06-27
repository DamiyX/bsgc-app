import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String name;
  final List<String> members; // user IDs
  final Map<String, double> readingProgress; // mapping user ID to progress 0.0-1.0
  final String pinnedScripture;
  final String description;
  final String? photoUrl;
  final DateTime createdAt;
  final String? studyBook;
  final int totalChapters;
  final Map<String, List<int>> userCompletedChapters;
  final String groupType; // 'Bible' or 'Devotional'
  final String? topic;
  final DateTime? startDate;
  final DateTime? endDate;

  GroupModel({
    required this.id,
    required this.name,
    required this.members,
    required this.readingProgress,
    required this.pinnedScripture,
    this.description = '',
    this.photoUrl,
    required this.createdAt,
    this.studyBook,
    this.totalChapters = 0,
    this.userCompletedChapters = const {},
    this.groupType = 'Bible',
    this.topic,
    this.startDate,
    this.endDate,
  });

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    // Parse readingProgress safely
    Map<String, double> parsedProgress = {};
    if (data['readingProgress'] != null) {
      final Map<String, dynamic> rawProgress = Map<String, dynamic>.from(data['readingProgress']);
      rawProgress.forEach((key, value) {
        parsedProgress[key] = (value as num).toDouble();
      });
    }

    // Parse userCompletedChapters safely
    Map<String, List<int>> parsedCompletedChapters = {};
    if (data['userCompletedChapters'] != null) {
      final Map<String, dynamic> rawChapters = Map<String, dynamic>.from(data['userCompletedChapters']);
      rawChapters.forEach((key, value) {
        parsedCompletedChapters[key] = List<int>.from(value);
      });
    }

    return GroupModel(
      id: doc.id,
      name: data['name'] ?? '',
      members: List<String>.from(data['members'] ?? []),
      readingProgress: parsedProgress,
      pinnedScripture: data['pinnedScripture'] ?? '',
      description: data['description'] ?? '',
      photoUrl: data['photoUrl'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      studyBook: data['studyBook'],
      totalChapters: data['totalChapters'] ?? 0,
      userCompletedChapters: parsedCompletedChapters,
      groupType: data['groupType'] ?? 'Bible',
      topic: data['topic'],
      startDate: (data['startDate'] as Timestamp?)?.toDate(),
      endDate: (data['endDate'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'members': members,
      'readingProgress': readingProgress,
      'pinnedScripture': pinnedScripture,
      'description': description,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'createdAt': Timestamp.fromDate(createdAt),
      'studyBook': studyBook,
      'totalChapters': totalChapters,
      'userCompletedChapters': userCompletedChapters,
      'groupType': groupType,
      'topic': topic,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    };
  }
}
