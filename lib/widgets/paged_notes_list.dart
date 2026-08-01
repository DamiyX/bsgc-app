import 'dart:async';

import 'package:flutter/material.dart';

import '../models/note_model.dart';
import '../services/note_service.dart';

typedef NoteItemBuilder = Widget Function(BuildContext context, NoteModel note);
typedef NoteEmptyBuilder = Widget Function(BuildContext context);
typedef NoteErrorBuilder =
    Widget Function(BuildContext context, Object error, VoidCallback retry);

/// Bounded, cursor-based journal history for screens that need older notes.
///
/// The first page is intentionally small and refreshable. Older records are
/// loaded only after an explicit user action, so a long-lived journal cannot
/// turn a screen open into an unbounded read or render operation.
class PagedNotesList extends StatefulWidget {
  final NoteService service;
  final String userId;
  final String searchQuery;
  final EdgeInsets padding;
  final NoteItemBuilder itemBuilder;
  final NoteEmptyBuilder emptyBuilder;
  final NoteErrorBuilder errorBuilder;

  const PagedNotesList({
    super.key,
    required this.service,
    required this.userId,
    this.searchQuery = '',
    this.padding = EdgeInsets.zero,
    required this.itemBuilder,
    required this.emptyBuilder,
    required this.errorBuilder,
  });

  @override
  State<PagedNotesList> createState() => _PagedNotesListState();
}

class _PagedNotesListState extends State<PagedNotesList> {
  List<NoteModel> _notes = const [];
  NotePage? _page;
  Object? _error;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirstPage());
  }

  @override
  void didUpdateWidget(PagedNotesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.service != widget.service) {
      unawaited(_loadFirstPage());
    }
  }

  Future<void> _loadFirstPage() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _notes = const [];
      _page = null;
    });
    try {
      final page = await widget.service.getUserNotePage(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _notes = page.notes;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final page = _page;
    if (_isLoadingMore || page == null || !page.hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = await widget.service.getUserNotePage(
        userId: widget.userId,
        after: page.cursor,
      );
      if (!mounted) return;
      final byId = <String, NoteModel>{
        for (final note in _notes) note.id: note,
        for (final note in nextPage.notes) note.id: note,
      };
      final merged = byId.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _page = nextPage;
        _notes = merged;
        _error = null;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _isLoadingMore = false;
      });
    }
  }

  List<NoteModel> get _visibleNotes {
    final query = widget.searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _notes;
    return _notes
        .where(
          (note) =>
              note.title.toLowerCase().contains(query) ||
              note.body.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _notes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _notes.isEmpty) {
      return widget.errorBuilder(context, _error!, _loadFirstPage);
    }

    final notes = _visibleNotes;
    if (notes.isEmpty) return widget.emptyBuilder(context);

    final hasMore = _page?.hasMore == true;
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        padding: widget.padding,
        itemCount: notes.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, index) => index == notes.length - 1
            ? const SizedBox(height: 4)
            : const SizedBox(height: 0),
        itemBuilder: (context, index) {
          if (index == notes.length) {
            return _LoadMoreNotesButton(
              isLoading: _isLoadingMore,
              hasError: _error != null,
              onPressed: _loadMore,
            );
          }
          return widget.itemBuilder(context, notes[index]);
        },
      ),
    );
  }
}

class _LoadMoreNotesButton extends StatelessWidget {
  final bool isLoading;
  final bool hasError;
  final VoidCallback onPressed;

  const _LoadMoreNotesButton({
    required this.isLoading,
    required this.hasError,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(hasError ? Icons.refresh_rounded : Icons.history_rounded),
          label: Text(
            isLoading
                ? 'Loading older reflections…'
                : hasError
                ? 'Retry older reflections'
                : 'Load older reflections',
          ),
        ),
      ),
    );
  }
}
