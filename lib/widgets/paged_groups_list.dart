import 'dart:async';

import 'package:flutter/material.dart';

import '../models/group_model.dart';
import '../services/chat_service.dart';

typedef GroupItemBuilder =
    Widget Function(BuildContext context, GroupModel group);
typedef GroupEmptyBuilder = Widget Function(BuildContext context);
typedef GroupErrorBuilder =
    Widget Function(BuildContext context, Object error, VoidCallback retry);

/// Cursor-based active/scheduled study list. Archived studies have their own
/// route so the primary Groups path stays bounded to actionable studies.
class PagedGroupsList extends StatefulWidget {
  final ChatService service;
  final String userId;
  final EdgeInsets padding;
  final GroupItemBuilder itemBuilder;
  final GroupEmptyBuilder emptyBuilder;
  final GroupErrorBuilder errorBuilder;

  const PagedGroupsList({
    super.key,
    required this.service,
    required this.userId,
    this.padding = EdgeInsets.zero,
    required this.itemBuilder,
    required this.emptyBuilder,
    required this.errorBuilder,
  });

  @override
  State<PagedGroupsList> createState() => _PagedGroupsListState();
}

class _PagedGroupsListState extends State<PagedGroupsList> {
  List<GroupModel> _groups = const [];
  GroupPage? _page;
  Object? _error;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFirstPage());
  }

  @override
  void didUpdateWidget(PagedGroupsList oldWidget) {
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
      _groups = const [];
      _page = null;
    });
    try {
      final page = await widget.service.getUserGroupPage(userId: widget.userId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _groups = page.groups;
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
      final nextPage = await widget.service.getUserGroupPage(
        userId: widget.userId,
        after: page.cursor,
      );
      if (!mounted) return;
      final byId = <String, GroupModel>{
        for (final group in _groups) group.id: group,
        for (final group in nextPage.groups) group.id: group,
      };
      final merged = byId.values.toList()
        ..sort((a, b) {
          final aTime = a.lastMessageTime ?? a.createdAt;
          final bTime = b.lastMessageTime ?? b.createdAt;
          return bTime.compareTo(aTime);
        });
      setState(() {
        _page = nextPage;
        _groups = merged;
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
    if (_isLoading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _groups.isEmpty) {
      return widget.errorBuilder(context, _error!, _loadFirstPage);
    }
    if (_groups.isEmpty) return widget.emptyBuilder(context);

    final hasMore = _page?.hasMore == true;
    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        padding: widget.padding,
        itemCount: _groups.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, index) => index == _groups.length - 1
            ? const SizedBox(height: 4)
            : const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _groups.length) {
            return _LoadMoreGroupsButton(
              isLoading: _isLoadingMore,
              hasError: _error != null,
              onPressed: _loadMore,
            );
          }
          return widget.itemBuilder(context, _groups[index]);
        },
      ),
    );
  }
}

class _LoadMoreGroupsButton extends StatelessWidget {
  final bool isLoading;
  final bool hasError;
  final VoidCallback onPressed;

  const _LoadMoreGroupsButton({
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
                ? 'Loading older studies…'
                : hasError
                ? 'Retry older studies'
                : 'Load older studies',
          ),
        ),
      ),
    );
  }
}
