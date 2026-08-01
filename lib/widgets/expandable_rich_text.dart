import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../utils/scripture_parser.dart';
import '../theme.dart';

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
  List<TapGestureRecognizer> _recognizers = [];
  List<InlineSpan> _spans = const [];
  bool _hasBuiltSpans = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rebuildSpans(notify: _hasBuiltSpans);
    _hasBuiltSpans = true;
  }

  @override
  void didUpdateWidget(ExpandableRichText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.defaultStyle != widget.defaultStyle ||
        oldWidget.linkStyle != widget.linkStyle ||
        oldWidget.onReferenceTap != widget.onReferenceTap) {
      _rebuildSpans(notify: true);
    }
  }

  void _rebuildSpans({required bool notify}) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers = [];
    _spans = ScriptureParser.parseText(
      text: _displayText,
      defaultStyle: widget.defaultStyle,
      linkStyle: widget.linkStyle,
      recognizerCollector: _recognizers,
      onReferenceTap: widget.onReferenceTap,
    );
    if (notify && mounted) setState(() {});
  }

  String get _displayText {
    const maxLength = 350;
    if (widget.text.length <= maxLength || _isExpanded) return widget.text;

    var breakIndex = maxLength;
    while (breakIndex > 0 &&
        widget.text[breakIndex] != ' ' &&
        widget.text[breakIndex] != '\n') {
      breakIndex--;
    }
    if (breakIndex == 0) breakIndex = maxLength;
    return '${widget.text.substring(0, breakIndex).trimRight()}...';
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
    final isLong = widget.text.length > 350;
    final semantic = Theme.of(context).extension<BraidSemanticColors>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(text: TextSpan(children: _spans)),
        if (isLong && !_isExpanded)
          Semantics(
            button: true,
            label: 'Read full reflection',
            child: InkWell(
              onTap: () {
                setState(() {
                  _isExpanded = true;
                  _rebuildSpans(notify: false);
                });
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 2),
                    child: Text(
                      'Read more',
                      style: TextStyle(
                        color:
                            widget.linkStyle.color ??
                            semantic?.focus ??
                            Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: widget.defaultStyle.fontSize,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
