import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/bible_model.dart';

class BibleService {
  static final BibleService _instance = BibleService._internal();
  factory BibleService() => _instance;
  BibleService._internal();

  final Map<String, BibleModel> _bibles = {};
  
  bool get isLoaded => _bibles.isNotEmpty;
  
  List<String> get availableTranslations => ['KJV', 'WEB', 'ESV', 'BBE', 'NIV', 'NLT', 'MSG', 'AMP'];

  Future<void> init() async {
    // Start loading in background, don't await all here if we don't want to block
    _loadTranslation('KJV', 'assets/bibles/kjv.json');
    _loadTranslation('WEB', 'assets/bibles/web.json');
    _loadTranslation('ESV', 'assets/bibles/esv.json');
    _loadTranslation('BBE', 'assets/bibles/bbe.json');
  }

  Future<void> _loadTranslation(String name, String path) async {
    try {
      final String response = await rootBundle.loadString(path);
      final List<dynamic> data = json.decode(response);
      _bibles[name] = BibleModel.fromJson(name, data);
    } catch (e) {
      print('Failed to load Bible $name: $e');
    }
  }

  /// Returns the text for a given reference. Returns null if not found.
  String? getVerseText(String translation, String bookName, int chapter, int startVerse, [int? endVerse]) {
    final bible = _bibles[translation];
    // REMOVED: fallback to KJV if null! The user explicitly requested no silent fallback.
    if (bible == null) return null;

    final normalizedSearch = bookName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    
    BibleBook? targetBook;
    for (var book in bible.books) {
      final nameNorm = book.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      final abbrevNorm = book.abbreviation.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (nameNorm == normalizedSearch || abbrevNorm == normalizedSearch || nameNorm.startsWith(normalizedSearch)) {
        targetBook = book;
        break;
      }
    }

    if (targetBook == null) return null;
    
    // Chapters are 0-indexed in the array, so chapter 1 is index 0
    if (chapter < 1 || chapter > targetBook.chapters.length) return null;
    final chapterVerses = targetBook.chapters[chapter - 1];

    if (startVerse < 1 || startVerse > chapterVerses.length) return null;
    
    int end = endVerse ?? startVerse;
    if (end > chapterVerses.length) end = chapterVerses.length;
    if (end < startVerse) end = startVerse;

    List<String> texts = [];
    for (int i = startVerse; i <= end; i++) {
      // verses are 0-indexed in the chapter array
      texts.add('${i}. ${chapterVerses[i - 1]}');
    }

    return texts.join(' ');
  }
}
