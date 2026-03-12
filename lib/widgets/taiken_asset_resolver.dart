// =============================================================================
// taiken_asset_resolver.dart
//
// Centralised helpers for resolving Taiken visual assets.
//
// Priority order for every asset:
//   1. Custom upload (XFile path / remote URL from Supabase) — user always wins
//   2. Predefined asset key  → assets/taiken/characters/<key>.png
//                            → assets/taiken/backgrounds/<key>.png
//   3. Placeholder widget
//
// Used by both TaikenCreatePage (preview) and TaikenExperiencePage (playback).
// =============================================================================

import 'dart:io';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Asset key lists  — single source of truth for the whole app
// ─────────────────────────────────────────────────────────────────────────────

class TaikenAssets {
  TaikenAssets._();

  static const List<String> characters = [
    'alex', 'maya', 'ken', 'sara', 'leo',
    'nina', 'arjun', 'emma', 'ryan', 'zoe',
  ];

  static const List<String> backgrounds = [
    'classroom', 'office', 'library', 'city', 'tech_lab',
    'startup_office', 'study_room', 'conference_room',
  ];

  // ── Path helpers ──────────────────────────────────────────────────────────

  static String characterPath(String key, {bool talking = false}) {
    final suffix = talking ? '_talking' : '';
    return 'assets/taiken/characters/$key$suffix.png';
  }

  static String backgroundPath(String key) =>
      'assets/taiken/backgrounds/$key.png';

  // ── Validation helpers ────────────────────────────────────────────────────

  static String? validateCharacter(String? v) =>
      characters.contains(v) ? v : null;

  static String? validateBackground(String? v) =>
      backgrounds.contains(v) ? v : null;

  // ── Display names ─────────────────────────────────────────────────────────

  static String characterLabel(String key) =>
      key[0].toUpperCase() + key.substring(1);

  static String backgroundLabel(String key) =>
      key.replaceAll('_', ' ').split(' ')
          .map((w) => w[0].toUpperCase() + w.substring(1))
          .join(' ');
}

// ─────────────────────────────────────────────────────────────────────────────
// CharacterAvatar
//
// Shows a character portrait in a circle.  Used on the character card in the
// create page and in the experience page.
//
// Priority: localFile > remoteUrl > assetKey > placeholder icon
// ─────────────────────────────────────────────────────────────────────────────

class CharacterAvatar extends StatelessWidget {
  /// Local file picked by the user (create page only).
  final File? localFile;

  /// Remote Supabase URL (experience page / edit page).
  final String? remoteUrl;

  /// Predefined asset key (e.g. 'alex').  Falls back to bundle PNG.
  final String? assetKey;

  final double size;
  final bool talking;
  final BoxShape shape;

  const CharacterAvatar({
    super.key,
    this.localFile,
    this.remoteUrl,
    this.assetKey,
    this.size        = 72,
    this.talking     = false,
    this.shape       = BoxShape.circle,
  });

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width:  size,
        height: size,
        child: _resolveImage(context),
      ),
    );
  }

  Widget _resolveImage(BuildContext context) {
    // 1. Local file (custom upload, not yet submitted)
    if (localFile != null) {
      return Image.file(localFile!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context));
    }

    // 2. Remote URL (already uploaded to Supabase)
    if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      return Image.network(remoteUrl!, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(context));
    }

    // 3. Bundle asset (predefined key)
    if (assetKey != null && TaikenAssets.characters.contains(assetKey)) {
      return Image.asset(
        TaikenAssets.characterPath(assetKey!, talking: talking),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(context),
      );
    }

    // 4. Placeholder
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) => Container(
    color: Colors.grey[800],
    child: Icon(Icons.person, size: size * 0.5, color: Colors.grey[500]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundImage
//
// Fills a container with a background.
// Priority: localFile > remoteUrl > assetKey > solid colour
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundImage extends StatelessWidget {
  final File? localFile;
  final String? remoteUrl;
  final String? assetKey;
  final Widget child;
  final double? width;
  final double? height;
  final Color fallbackColor;

  const BackgroundImage({
    super.key,
    this.localFile,
    this.remoteUrl,
    this.assetKey,
    required this.child,
    this.width,
    this.height,
    this.fallbackColor = const Color(0xFF1A1A2E),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width:       width,
      height:      height,
      decoration:  BoxDecoration(
        color: fallbackColor,
        image: _resolveDecorationImage(),
      ),
      child: child,
    );
  }

  DecorationImage? _resolveDecorationImage() {
    ImageProvider? provider;

    if (localFile != null) {
      provider = FileImage(localFile!);
    } else if (remoteUrl != null && remoteUrl!.isNotEmpty) {
      provider = NetworkImage(remoteUrl!);
    } else if (assetKey != null && TaikenAssets.backgrounds.contains(assetKey)) {
      provider = AssetImage(TaikenAssets.backgroundPath(assetKey!));
    }

    if (provider == null) return null;
    return DecorationImage(image: provider, fit: BoxFit.cover);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BackgroundThumbnail
//
// Small preview tile used in the background picker grid.
// ─────────────────────────────────────────────────────────────────────────────

class BackgroundThumbnail extends StatelessWidget {
  final String assetKey;
  final bool selected;
  final VoidCallback onTap;

  const BackgroundThumbnail({
    super.key,
    required this.assetKey,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                TaikenAssets.backgroundPath(assetKey),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey[800],
                  child: Icon(Icons.landscape,
                      color: Colors.grey[600], size: 28),
                ),
              ),
              // Label overlay
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Text(
                    TaikenAssets.backgroundLabel(assetKey),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (selected)
                Positioned(
                  top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check,
                        color: Colors.white, size: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CharacterPickerTile
//
// Thumbnail used in the character asset picker grid.
// ─────────────────────────────────────────────────────────────────────────────

class CharacterPickerTile extends StatelessWidget {
  final String assetKey;
  final bool selected;
  final VoidCallback onTap;

  const CharacterPickerTile({
    super.key,
    required this.assetKey,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[700]!,
            width: selected ? 3 : 1.5,
          ),
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
              : Theme.of(context).cardColor,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipOval(
              child: SizedBox(
                width: 52, height: 52,
                child: Image.asset(
                  TaikenAssets.characterPath(assetKey),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey[800],
                    child: Icon(Icons.person,
                        color: Colors.grey[500], size: 28),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              TaikenAssets.characterLabel(assetKey),
              style: TextStyle(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}