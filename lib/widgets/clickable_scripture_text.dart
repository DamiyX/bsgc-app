import 'package:flutter/material.dart';
import '../utils/scripture_parser.dart';
import 'bible_verse_bottom_sheet.dart';

class ClickableScriptureText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;

  const ClickableScriptureText({
    super.key,
    required this.text,
    required this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        children: ScriptureParser.parseText(
          text: text,
          defaultStyle: style,
          linkStyle: style.merge(linkStyle ?? TextStyle(
            color: Colors.purpleAccent,
            fontWeight: FontWeight.bold,
            decoration: TextDecoration.underline,
            decorationColor: Colors.purpleAccent,
          )),
          onReferenceTap: (reference) {
            showDialog(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.symmetric(horizontal: 16),
                child: BibleVerseBottomSheet(reference: reference),
              ),
            );
          },
        ),
      ),
    );
  }
}
