import 'dart:async';

import 'package:flutter/material.dart';

import '../models/insight_model.dart';
import '../services/insight_service.dart';
import 'saved_insight_card.dart';

typedef SavedInsightEmptyBuilder = Widget Function(BuildContext context);
typedef SavedInsightErrorBuilder =
    Widget Function(BuildContext context, Object error, VoidCallback retry);

/// Bounded cursor-based saved-reflection history.
class PagedSavedInsightsList extends StatefulWidget {
  final InsightService service;
  final String userId;
  final EdgeInsets padding;
  final SavedInsightEmptyBuilder emptyBuilder;
  final SavedInsightErrorBuilder errorBuilder;
  final ValueChanged<InsightModel> onDelete;

  const PagedSavedInsightsList({
    super.key,
    required this.service,
    required this.userId,
    this.padding = EdgeInsets.zero,
    required this.emptyBuilder,
    required this.errorBuilder,
    required this.onDelete,
  });

  @override
  State<PagedSavedInsightsList> createState() => _PagedSavedInsightsListState();
}

class _PagedSavedInsightsListState extends State<PagedSavedInsightsList> {
  List<InsightModel> _insights = const [];
  SavedInsightPage? _page;
  Object? _error;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirstPage());
  }

  @override
  void didUpdateWidget(PagedSavedInsightsList oldWidget) {
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
      _insights = const [];
      _page = null;
    });
    try {
      final page = await widget.service.getSavedInsightPage(
        userId: widget.userId,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _insights = page.insights;
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
      final nextPage = await widget.service.getSavedInsightPage(
        userId: widget.userId,
        after: page.cursor,
      );
      if (!mounted) return;
      final byId = <String, InsightModel>{
        for (final insight in _insights) insight.id: insight,
        for (final insight in nextPage.insights) insight.id: insight,
      };
      final merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _page = nextPage;
        _insights = merged;
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _insights.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _insights.isEmpty) {
      return widget.errorBuilder(context, _error!, _loadFirstPage);
    }
    if (_insights.isEmpty) return widget.emptyBuilder(context);

    final hasMore = _page?.hasMore == true;
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        padding: widget.padding,
        itemCount: _insights.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, index) => index == _insights.length - 1
            ? const SizedBox(height: 4)
            : const SizedBox(height: 0),
        itemBuilder: (context, index) {
          if (index == _insights.length) {
            return _LoadMoreSavedInsightsButton(
              isLoading: _isLoadingMore,
              hasError: _error != null,
              onPressed: _loadMore,
            );
          }
          final insight = _insights[index];
          return SavedInsightCard(
            insight: insight,
            onDelete: () => widget.onDelete(insight),
          );
        },
      ),
    );
  }
}

class _LoadMoreSavedInsightsButton extends StatelessWidget {
  final bool isLoading;
  final bool hasError;
  final VoidCallback onPressed;

  const _LoadMoreSavedInsightsButton({
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
                ? 'Loading older saved reflections…'
                : hasError
                ? 'Retry older saved reflections'
                : 'Load older saved reflections',
          ),
        ),
      ),
    );
  }
}
