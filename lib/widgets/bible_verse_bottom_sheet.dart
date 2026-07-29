import 'package:flutter/material.dart';
import '../services/bible_service.dart';
import '../utils/scripture_parser.dart';
import '../theme.dart';

class BibleVerseBottomSheet extends StatefulWidget {
  final ScriptureReference reference;

  const BibleVerseBottomSheet({super.key, required this.reference});

  @override
  State<BibleVerseBottomSheet> createState() => _BibleVerseBottomSheetState();
}

class _BibleVerseBottomSheetState extends State<BibleVerseBottomSheet> {
  final BibleService _bibleService = BibleService();
  late String _currentTranslation;
  String? _verseText;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _currentTranslation = _bibleService.availableTranslations.isNotEmpty
        ? _bibleService.availableTranslations.first
        : 'KJV';
    _loadVerse();
  }

  Future<void> _loadVerse() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _bibleService.init();
      final text = _bibleService.getVerseText(
        _currentTranslation,
        widget.reference.book,
        widget.reference.chapter,
        widget.reference.startVerse,
        widget.reference.endVerse,
      );
      if (!mounted) return;
      setState(() {
        _verseText = text;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verseText = null;
        _isLoading = false;
      });
    }
  }

  String getTranslationFullName(String code) {
    switch (code) {
      case 'KJV':
        return 'King James Version';
      case 'WEB':
        return 'World English Bible';
      default:
        return code;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: EdgeInsets.all(24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.reference.fullMatch,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.87),
                  ),
                ),
              ),
              if (_bibleService.isLoaded)
                DropdownButton<String>(
                  value: _currentTranslation,
                  underline: SizedBox(),
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.54),
                  ),
                  items: _bibleService.availableTranslations.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text(
                        t,
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _currentTranslation = val;
                      });
                      _loadVerse();
                    }
                  },
                ),
            ],
          ),
          Divider(height: 24),
          Flexible(
            child: SingleChildScrollView(
              child: _isLoading
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(
                          color: AppColors.gradientEnd,
                        ),
                      ),
                    )
                  : _verseText == null
                  ? Text(
                      'This verse could not be found in the bundled '
                      '$_currentTranslation text. KJV and WEB are available '
                      'offline; Braid does not silently substitute another translation.',
                      style: TextStyle(color: Colors.red, height: 1.5),
                    )
                  : Text(
                      _verseText!,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.5,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.87),
                      ),
                    ),
            ),
          ),
          SizedBox(height: 16),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(
              getTranslationFullName(_currentTranslation),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.45),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
