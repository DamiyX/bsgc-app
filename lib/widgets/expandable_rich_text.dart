import 'package:flutter/material.dart';
import '../utils/scripture_parser.dart';

class ExpandableRichText extends StatefulWidget {
  final String text;
  final TextStyle defaultStyle;
  final TextStyle linkStyle;
  final Function(ScriptureReference) onReferenceTap;

  const ExpandableRichText({
    super.key,
    required this.text,
    required this.defaultStyle,
    required this.linkStyle,
    required this.onReferenceTap,
  });

  @override
  State<ExpandableRichText> createState() => _ExpandableRichTextState();
}

class _ExpandableRichTextState extends State<ExpandableRichText> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final int maxLength = 350;
    final bool isLong = widget.text.length > maxLength;

    String displayText = widget.text;
    if (isLong && !_isExpanded) {
      // Find a natural break point instead of cutting a word
      int breakIndex = maxLength;
      while (breakIndex > 0 && widget.text[breakIndex] != ' ' && widget.text[breakIndex] != '\n') {
        breakIndex--;
      }
      if (breakIndex == 0) breakIndex = maxLength; // fallback
      
      displayText = widget.text.substring(0, breakIndex).trimRight() + '...';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            children: ScriptureParser.parseText(
              text: displayText,
              defaultStyle: widget.defaultStyle,
              linkStyle: widget.linkStyle,
              onReferenceTap: widget.onReferenceTap,
            ),
          ),
        ),
        if (isLong && !_isExpanded)
          GestureDetector(
            onTap: () {
              setState(() {
                _isExpanded = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 2.0),
              child: Text(
                'Read more',
                style: TextStyle(
                  color: widget.linkStyle.color ?? Colors.purpleAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: widget.defaultStyle.fontSize,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
