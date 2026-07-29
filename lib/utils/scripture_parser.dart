import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class ScriptureReference {
  final String fullMatch;
  final String book;
  final int chapter;
  final int? startVerse;
  final int? endVerse;

  ScriptureReference({
    required this.fullMatch,
    required this.book,
    required this.chapter,
    this.startVerse,
    this.endVerse,
  });
}

class ScriptureParser {
  static const String _books =
      r'(Second Thessalonians|First Thessalonians|Second Corinthians|1st Thessalonians|2nd Thessalonians|First Corinthians|Second Chronicles|First Chronicles|1st Corinthians|2nd Corinthians|2 Thessalonians|1 Thessalonians|Song of Solomon|1st Chronicles|Second Timothy|2nd Chronicles|2 Corinthians|First Timothy|Second Samuel|1 Corinthians|2 Chronicles|1 Chronicles|Second Kings|Lamentations|First Samuel|Second Peter|Ecclesiastes|Second John|2nd Timothy|1st Timothy|Deuteronomy|Philippians|First Kings|First Peter|Revelation|1st Samuel|Colossians|2nd Samuel|Third John|First John|2nd Peter|Zephaniah|Leviticus|1st Kings|2 Timothy|1st Peter|Galatians|Ephesians|1 Timothy|2nd Kings|Zechariah|1st John|Jeremiah|Habakkuk|Philemon|Nehemiah|Proverbs|1 Samuel|2nd John|2 Samuel|3rd John|2 Kings|1 Kings|Hebrews|2 Peter|Matthew|Malachi|1 Chron|2 Chron|1 Peter|Numbers|Ezekiel|2 Thess|1 Thess|Genesis|Obadiah|Exodus|Joshua|Judges|Philem|Isaiah|Romans|Esther|Daniel|2 John|Psalms|1 John|Eccles|Haggai|3 John|1 Kgs|2 Kgs|Nahum|2 Cor|Micah|1 Pet|Hosea|1 Tim|2 Tim|2 Sam|Titus|1 Sam|James|Psalm|2 Pet|1 Cor|Jonah|Deut|Prov|Josh|Judg|Ezek|Zeph|Zech|Esth|Song|Matt|2 Jn|Jude|John|Obad|Amos|1 Jn|Ezra|Acts|3 Jn|Mark|Ruth|Luke|Joel|Phil|Heb|Jas|Rev|Dan|Lam|Jer|Nah|Mic|Hos|Isa|Lev|Exo|Gen|Job|Neh|Num|Hab|Rom|Tit|Gal|Col|Eph|Joh|Mal|Hag|Ps|Ex|Mt|Lk|Jn|Ro|Mk)';

  static final RegExp _scriptureRegExp = RegExp(
    r'\b' +
        _books +
        r'\.?\s+(\d+)(?:\s*:\s*(\d+)[a-zA-Z]?)?(?:\s*[-–—,]\s*(\d+)[a-zA-Z]?)?\b',
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
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: defaultStyle,
          ),
        );
      }

      final fullMatch = match.group(0)!;
      final book = match.group(1)!.trim();
      final chapter = int.parse(match.group(2)!);
      final startVerse = match.group(3) != null
          ? int.parse(match.group(3)!)
          : null;
      final endVerse = match.group(4) != null
          ? int.parse(match.group(4)!)
          : null;

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
          recognizer: TapGestureRecognizer()
            ..onTap = () => onReferenceTap(reference),
        ),
      );

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(text: text.substring(lastMatchEnd), style: defaultStyle),
      );
    }

    return spans;
  }
}
