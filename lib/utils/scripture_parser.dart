import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ScriptureReference {
  final String fullMatch;
  final String book;
  final int chapter;
  final int startVerse;
  final int? endVerse;

  ScriptureReference({
    required this.fullMatch,
    required this.book,
    required this.chapter,
    required this.startVerse,
    this.endVerse,
  });
}

class ScriptureParser {
  static const String _books = r'(Genesis|Gen|Exodus|Ex|Leviticus|Lev|Numbers|Num|Deuteronomy|Deut|Joshua|Josh|Judges|Judg|Ruth|1 Samuel|1 Sam|2 Samuel|2 Sam|1 Kings|1 Kgs|2 Kings|2 Kgs|1 Chronicles|1 Chron|2 Chronicles|2 Chron|Ezra|Nehemiah|Neh|Esther|Esth|Job|Psalms|Psalm|Ps|Proverbs|Prov|Ecclesiastes|Eccles|Song of Solomon|Song|Isaiah|Isa|Jeremiah|Jer|Lamentations|Lam|Ezekiel|Ezek|Daniel|Dan|Hosea|Hos|Joel|Amos|Obadiah|Obad|Jonah|Micah|Mic|Nahum|Nah|Habakkuk|Hab|Zephaniah|Zeph|Haggai|Hag|Zechariah|Zech|Malachi|Mal|Matthew|Matt|Mark|Luke|John|Acts|Romans|Rom|1 Corinthians|1 Cor|2 Corinthians|2 Cor|Galatians|Gal|Ephesians|Eph|Philippians|Phil|Colossians|Col|1 Thessalonians|1 Thess|2 Thessalonians|2 Thess|1 Timothy|1 Tim|2 Timothy|2 Tim|Titus|Philemon|Philem|Hebrews|Heb|James|1 Peter|1 Pet|2 Peter|2 Pet|1 John|2 John|3 John|Jude|Revelation|Rev)';

  static final RegExp _scriptureRegExp = RegExp(
    r'\b' + _books + r'\s+(\d+):(\d+)(?:-(\d+))?\b',
    caseSensitive: false,
  );

  static List<InlineSpan> parseText({
    required String text,
    required TextStyle defaultStyle,
    required TextStyle linkStyle,
    required Function(ScriptureReference) onReferenceTap,
  }) {
    List<InlineSpan> spans = [];
    int lastMatchEnd = 0;

    for (var match in _scriptureRegExp.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: defaultStyle,
        ));
      }

      final fullMatch = match.group(0)!;
      final book = match.group(1)!.trim();
      final chapter = int.parse(match.group(2)!);
      final startVerse = int.parse(match.group(3)!);
      final endVerse = match.group(4) != null ? int.parse(match.group(4)!) : null;

      final reference = ScriptureReference(
        fullMatch: fullMatch,
        book: book,
        chapter: chapter,
        startVerse: startVerse,
        endVerse: endVerse,
      );

      spans.add(
        TextSpan(
          text: fullMatch,
          style: linkStyle,
          recognizer: TapGestureRecognizer()..onTap = () => onReferenceTap(reference),
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: defaultStyle,
      ));
    }

    return spans;
  }
}
