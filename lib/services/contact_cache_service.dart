import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactCacheService {
  static final ContactCacheService _instance = ContactCacheService._internal();
  factory ContactCacheService() => _instance;
  ContactCacheService._internal();

  Map<String, String> _uidToNameMap = {};
  bool _hasLoaded = false;
  bool _isSyncing = false;
  bool _hasSynced = false;

  Future<void> loadCache() async {
    if (_hasLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('uidToNameMap');
      if (cachedStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(cachedStr);
        _uidToNameMap = decoded.map((key, value) => MapEntry(key, value.toString()));
      }
      _hasLoaded = true;
    } catch (e) {
      debugPrint('Error loading contact cache: $e');
    }
  }

  Future<void> syncContactsInBackground() async {
    if (_isSyncing || _hasSynced) return;
    _isSyncing = true;
    try {
      await loadCache();
      
      if (!await FlutterContacts.requestPermission(readonly: true)) return;

      final contacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
      List<Map<String, String>> simpleContacts = [];
      for (var c in contacts) {
        if (c.phones.isNotEmpty) {
          simpleContacts.add({
            'name': c.displayName,
            'phone': c.phones.first.number,
          });
        }
      }

      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      final allUsers = usersSnapshot.docs.map((d) => d.data()).toList();

      final map = await compute(_buildCacheIsolate, {
        'contacts': simpleContacts,
        'users': allUsers,
      });

      _uidToNameMap = map;
      _hasSynced = true;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('uidToNameMap', jsonEncode(_uidToNameMap));
    } catch (e) {
      debugPrint('Error syncing contacts: $e');
    } finally {
      _isSyncing = false;
    }
  }

  String getContactName(String uid, String fallbackGoogleName) {
    if (_uidToNameMap.containsKey(uid) && _uidToNameMap[uid]!.isNotEmpty) {
      return _uidToNameMap[uid]!;
    }
    return fallbackGoogleName;
  }
}

Map<String, String> _buildCacheIsolate(Map<String, dynamic> args) {
  final simpleContacts = args['contacts'] as List<Map<String, String>>;
  final allUsers = args['users'] as List<Map<String, dynamic>>;

  String cleanPhone(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  final userPhoneMap = <String, String>{};
  for (var u in allUsers) {
    final uid = u['uid'] ?? u['id'] as String?;
    
    List<String> phones = [];
    if (u['phone'] != null) phones.add(u['phone'].toString());
    if (u['phoneNumber'] != null) phones.add(u['phoneNumber'].toString());
    if (u['phoneNumbers'] != null && u['phoneNumbers'] is List) {
      for (var p in u['phoneNumbers']) {
        phones.add(p.toString());
      }
    }
    
    if (uid == null || phones.isEmpty) continue;
    
    for (String phone in phones) {
      final cleanUPhone = cleanPhone(phone);
    if (cleanUPhone.length >= 7) {
      for (int i = 7; i <= cleanUPhone.length && i <= 12; i++) {
        userPhoneMap[cleanUPhone.substring(cleanUPhone.length - i)] = uid;
      }
    }
    } // Closes for (String phone in phones)
  } // Closes for (var u in allUsers)

  final uidToName = <String, String>{};

  for (var contact in simpleContacts) {
    final rawPhone = contact['phone'] ?? '';
    final name = contact['name'] ?? '';
    final cleanContactPhone = cleanPhone(rawPhone);

    if (cleanContactPhone.length >= 7) {
      for (int i = cleanContactPhone.length > 12 ? 12 : cleanContactPhone.length; i >= 7; i--) {
        final testPhone = cleanContactPhone.substring(cleanContactPhone.length - i);
        if (userPhoneMap.containsKey(testPhone)) {
          final uid = userPhoneMap[testPhone]!;
          if (name.isNotEmpty) {
            uidToName[uid] = name;
          }
          break;
        }
      }
    }
  }

  return uidToName;
}
