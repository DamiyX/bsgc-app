import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/bible_model.dart';

class BibleService {
  static final BibleService _instance = BibleService._internal();
  factory BibleService() => _instance;
  BibleService._internal();

  final Map<String, BibleModel> _bibles = {};
  final Map<String, Future<void>> _translationLoads = {};
  static const _translationAssets = {
    'KJV': 'assets/bibles/kjv.json',
    'WEB': 'assets/bibles/web.json',
  };

  bool get isLoaded => _bibles.isNotEmpty;

  List<String> get availableTranslations =>
      _translationAssets.keys.toList(growable: false);

  Future<void> init() => ensureTranslation('KJV');

  Future<void> ensureTranslation(String name) {
    if (_bibles.containsKey(name)) return Future<void>.value();
    final asset = _translationAssets[name];
    if (asset == null) {
      return Future<void>.error(
        ArgumentError.value(name, 'name', 'Unknown Bible translation.'),
      );
    }
    return _translationLoads[name] ??= _loadTranslation(name, asset).then((
      loaded,
    ) {
      if (!loaded) {
        _translationLoads.remove(name);
        throw StateError('$name could not be loaded.');
      }
    });
  }

  Future<bool> _loadTranslation(String name, String path) async {
    try {
      final String response = await rootBundle.loadString(path);
      final dynamic data = await compute(jsonDecode, response);
      _bibles[name] = BibleModel.fromJson(name, data as List<dynamic>);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to load Bible $name: $e');
      return false;
    }
  }

  /// Returns the text for a given reference. Returns null if not found.
  String? getVerseText(
    String translation,
    String bookName,
    int chapter, [
    int? startVerse,
    int? endVerse,
  ]) {
    final bible = _bibles[translation];
    // REMOVED: fallback to KJV if null! The user explicitly requested no silent fallback.
    if (bible == null) return null;

    final normalizedSearch = bookName.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9]'),
      '',
    );

    BibleBook? targetBook;
    for (var book in bible.books) {
      final nameNorm = book.name.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      final abbrevNorm = book.abbreviation.toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9]'),
        '',
      );
      if (nameNorm == normalizedSearch ||
          abbrevNorm == normalizedSearch ||
          nameNorm.startsWith(normalizedSearch)) {
        targetBook = book;
        break;
      }
    }

    if (targetBook == null) return null;

    // Chapters are 0-indexed in the array, so chapter 1 is index 0
    if (chapter < 1 || chapter > targetBook.chapters.length) return null;
    final chapterVerses = targetBook.chapters[chapter - 1];

    int start = startVerse ?? 1;
    if (start < 1 || start > chapterVerses.length) return null;

    int end = endVerse ?? (startVerse == null ? chapterVerses.length : start);
    if (end > chapterVerses.length) end = chapterVerses.length;
    if (end < start) end = start;

    List<String> texts = [];
    for (int i = start; i <= end; i++) {
      // verses are 0-indexed in the chapter array
      texts.add('$i. ${chapterVerses[i - 1]}');
    }

    return texts.join(' ');
  }
}
