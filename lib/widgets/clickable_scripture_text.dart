import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../utils/scripture_parser.dart';
import '../theme.dart';
import 'bible_verse_bottom_sheet.dart';

class ClickableScriptureText extends StatefulWidget {
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
  State<ClickableScriptureText> createState() => _ClickableScriptureTextState();
}

class _ClickableScriptureTextState extends State<ClickableScriptureText> {
  List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = const [];
  bool _hasBuiltSpans = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildSpans(notify: _hasBuiltSpans);
    _hasBuiltSpans = true;
  }

  @override
  void didUpdateWidget(ClickableScriptureText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.linkStyle != widget.linkStyle) {
      _rebuildSpans(notify: true);
    }
  }

  void _rebuildSpans({required bool notify}) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers = [];
    _spans = ScriptureParser.parseText(
      text: widget.text,
      defaultStyle: widget.style,
      linkStyle: widget.style.merge(
        widget.linkStyle ??
            TextStyle(
              color: _linkColor(),
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
              decorationColor: _linkColor(),
            ),
      ),
      recognizerCollector: _recognizers,
      onReferenceTap: (reference) {
        showDialog(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16),
            child: BibleVerseBottomSheet(reference: reference),
          ),
        );
      },
    );
    if (notify && mounted) setState(() {});
  }

  Color _linkColor() {
    final theme = Theme.of(context);
    return theme.extension<BraidSemanticColors>()?.focus ??
        theme.colorScheme.primary;
  }

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
      text: TextSpan(children: _spans),
    );
  }
}
