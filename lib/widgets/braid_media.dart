import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/media_reference_policy.dart';
import '../services/voice_cache_service.dart';

class BraidAvatar extends StatelessWidget {
  final String identity;
  final String displayName;
  final String? imageUrl;
  final double radius;
  final bool showBorder;

  const BraidAvatar({
    super.key,
    required this.identity,
    required this.displayName,
    this.imageUrl,
    this.radius = 20,
    this.showBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = _AvatarFallback(
      identity: identity,
      displayName: displayName,
      radius: radius,
    );
    final normalizedUrl = imageUrl?.trim() ?? '';
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: normalizedUrl.isEmpty
            ? fallback
            : isCanonicalProfilePhotoPath(normalizedUrl, identity)
            ? _AuthenticatedCoverImage(
                storagePath: normalizedUrl,
                fit: BoxFit.cover,
                fallback: fallback,
                cacheWidth: (radius * 4).round(),
                cacheHeight: (radius * 4).round(),
              )
            : isAllowedLegacyProfileUrl(normalizedUrl, identity)
            ? CachedNetworkImage(
                imageUrl: normalizedUrl,
                fit: BoxFit.cover,
                memCacheWidth: (radius * 4).round(),
                memCacheHeight: (radius * 4).round(),
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
                fadeInDuration: const Duration(milliseconds: 120),
              )
            : fallback,
      ),
    );

    return Semantics(
      image: true,
      label: '$displayName profile picture',
      child: showBorder
          ? DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
              child: avatar,
            )
          : avatar,
    );
  }
}

class BraidCoverImage extends StatelessWidget {
  final String identity;
  final String? imageUrl;
  final double width;
  final double height;
  final double borderRadius;
  final BoxFit fit;
  final IconData fallbackIcon;
  final String semanticLabel;

  const BraidCoverImage({
    super.key,
    required this.identity,
    required this.imageUrl,
    required this.width,
    required this.height,
    this.borderRadius = 12,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.auto_stories_rounded,
    this.semanticLabel = 'Study cover',
  });

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: _identityColor(identity).withValues(alpha: 0.14),
      child: Center(
        child: Icon(
          fallbackIcon,
          size: (width < height ? width : height) * 0.38,
          color: _identityColor(identity),
        ),
      ),
    );
    final normalizedUrl = imageUrl?.trim() ?? '';

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: width,
          height: height,
          child: normalizedUrl.isEmpty
              ? fallback
              : isCanonicalGroupCoverPath(normalizedUrl, identity)
              ? _AuthenticatedCoverImage(
                  storagePath: normalizedUrl,
                  fit: fit,
                  fallback: fallback,
                  cacheWidth: (width * 2).round(),
                  cacheHeight: (height * 2).round(),
                )
              : fallback,
        ),
      ),
    );
  }
}

class _AuthenticatedCoverImage extends StatefulWidget {
  final String storagePath;
  final BoxFit fit;
  final Widget fallback;
  final int cacheWidth;
  final int cacheHeight;

  const _AuthenticatedCoverImage({
    required this.storagePath,
    required this.fit,
    required this.fallback,
    required this.cacheWidth,
    required this.cacheHeight,
  });

  @override
  State<_AuthenticatedCoverImage> createState() =>
      _AuthenticatedCoverImageState();
}

class _AuthenticatedCoverImageState extends State<_AuthenticatedCoverImage> {
  late final Future<VoiceCacheEntry> _entry = _load();

  Future<VoiceCacheEntry> _load() {
    final accountId = FirebaseAuth.instance.currentUser?.uid;
    if (accountId == null) {
      return Future.error(StateError('Sign in to view this cover.'));
    }
    return VoiceCacheService.shared.prepare(
      accountId: accountId,
      sourceUrl: 'firebase-storage:///${widget.storagePath}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VoiceCacheEntry>(
      future: _entry,
      builder: (context, snapshot) {
        final entry = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.hasError ||
            entry == null) {
          return widget.fallback;
        }
        return Image.file(
          entry.file,
          fit: widget.fit,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
        );
      },
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  final String identity;
  final String displayName;
  final double radius;

  const _AvatarFallback({
    required this.identity,
    required this.displayName,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedName = displayName.trim();
    final initials = trimmedName.isEmpty
        ? '?'
        : trimmedName
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part[0].toUpperCase())
              .join();
    return ColoredBox(
      color: _identityColor(identity),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

Color _identityColor(String identity) {
  const colors = [
    Color(0xFF6A4BBC),
    Color(0xFF336B87),
    Color(0xFF3F7652),
    Color(0xFF9A5A2E),
    Color(0xFF8B3F68),
    Color(0xFF4B5EAA),
  ];
  var hash = 0;
  for (final codeUnit in identity.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return colors[hash % colors.length];
}
