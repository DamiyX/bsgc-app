import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _groupDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

class GroupModel {
  final String id;
  final int schemaVersion;
  final String ownerId;
  String name;
  final List<String> members; // user IDs
  final Map<String, double> readingProgress; // mapping user ID to progress 0.0-1.0
  final String pinnedScripture;
  String description;
  String? photoUrl;
  final DateTime createdAt;
  final String? studyBook;
  final int totalChapters;
  final Map<String, List<int>> userCompletedChapters;
  final String groupType; // 'Bible' or 'Devotional'
  final String? topic;
  final DateTime? startDate;
  final DateTime? endDate;
  final DateTime? lastMessageTime;
  final String? lastMessageText;
  final String? lastMessageSenderName;
  final String? lastMessageSenderId;
  final Map<String, int> unreadCounts;
  final int extensionCount;
  final String lifecycle;

  GroupModel({
    required this.id,
    this.schemaVersion = 2,
    required this.ownerId,
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
    this.lastMessageTime,
    this.lastMessageText,
    this.lastMessageSenderName,
    this.lastMessageSenderId,
    this.unreadCounts = const {},
    this.extensionCount = 0,
    this.lifecycle = 'active',
  });

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    final rawData = doc.data();
    final data = rawData is Map<String, dynamic>
        ? rawData
        : const <String, dynamic>{};
    
    // Parse readingProgress safely
    Map<String, double> parsedProgress = {};
    if (data['readingProgress'] is Map) {
      final rawProgress = Map<String, dynamic>.from(
        data['readingProgress'] as Map,
      );
      rawProgress.forEach((key, value) {
        if (value is num) {
          parsedProgress[key] = value.toDouble().clamp(0, 1).toDouble();
        }
      });
    }

    // Parse userCompletedChapters safely
    Map<String, List<int>> parsedCompletedChapters = {};
    if (data['userCompletedChapters'] is Map) {
      final rawChapters = Map<String, dynamic>.from(
        data['userCompletedChapters'] as Map,
      );
      rawChapters.forEach((key, value) {
        if (value is List) {
          parsedCompletedChapters[key] = value
              .whereType<num>()
              .map((chapter) => chapter.toInt())
              .toList();
        }
      });
    }

    // Parse unreadCounts safely
    Map<String, int> parsedUnreadCounts = {};
    if (data['unreadCounts'] is Map) {
      final rawUnreads = Map<String, dynamic>.from(
        data['unreadCounts'] as Map,
      );
      rawUnreads.forEach((key, value) {
        if (value is num) parsedUnreadCounts[key] = value.toInt();
      });
    }

    final members = data['members'] is List
        ? (data['members'] as List).whereType<String>().toList()
        : <String>[];
    return GroupModel(
      id: doc.id,
      schemaVersion: data['schemaVersion'] is int ? data['schemaVersion'] : 1,
      ownerId: data['ownerId']?.toString() ??
          (members.isNotEmpty ? members.first : ''),
      name: data['name']?.toString() ?? 'Study group',
      members: members,
      readingProgress: parsedProgress,
      pinnedScripture: data['pinnedScripture']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      photoUrl: data['photoUrl']?.toString(),
      createdAt: _groupDate(data['createdAt']) ?? DateTime.now(),
      studyBook: data['studyBook']?.toString(),
      totalChapters: data['totalChapters'] is num
          ? (data['totalChapters'] as num).toInt()
          : 0,
      userCompletedChapters: parsedCompletedChapters,
      groupType: data['groupType']?.toString() ?? 'Bible',
      topic: data['topic']?.toString(),
      startDate: _groupDate(data['startDate']),
      endDate: _groupDate(data['endDate']),
      lastMessageTime: _groupDate(data['lastMessageTime']),
      lastMessageText: data['lastMessageText']?.toString(),
      lastMessageSenderName: data['lastMessageSenderName']?.toString(),
      lastMessageSenderId: data['lastMessageSenderId']?.toString(),
      unreadCounts: parsedUnreadCounts,
      extensionCount: data['extensionCount'] is num
          ? (data['extensionCount'] as num).toInt().clamp(0, 3).toInt()
          : 0,
      lifecycle: const {
        'draft',
        'scheduled',
        'active',
        'completed',
        'archived',
      }.contains(data['lifecycle'])
          ? data['lifecycle'] as String
          : 'active',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'ownerId': ownerId,
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
      if (lastMessageTime != null) 'lastMessageTime': Timestamp.fromDate(lastMessageTime!),
      if (lastMessageText != null) 'lastMessageText': lastMessageText,
      if (lastMessageSenderName != null) 'lastMessageSenderName': lastMessageSenderName,
      if (lastMessageSenderId != null) 'lastMessageSenderId': lastMessageSenderId,
      'unreadCounts': unreadCounts,
      'extensionCount': extensionCount,
      'lifecycle': lifecycle,
    };
  }
}
