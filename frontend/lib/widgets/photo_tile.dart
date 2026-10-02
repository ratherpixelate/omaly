import 'package:flutter/material.dart';

/// A single photo tile.
///
/// Deliberately built on [Image.network] rather than `cached_network_image`:
/// that package pulls in `flutter_cache_manager` -> `sqflite`, which has no
/// Linux/Windows desktop implementation, so its cache DB throws
/// `MissingPluginException` off macOS. [Image.network] uses Flutter's built-in
/// in-memory `ImageCache` and works on every desktop platform. If you want
/// disk caching later, initialise `sqflite_common_ffi` in `main()` and swap
/// this one widget's body — nothing else references it.
class PhotoTile extends StatelessWidget {
  const PhotoTile({
    super.key,
    required this.photoId,
    required this.uri,
    this.borderRadius = 12,
  });

  final String photoId;

  /// Absolute thumbnail URL, or `null` when running on mock data. `null`
  /// renders a deterministic coloured placeholder so the grid still looks
  /// like a real photo grid during development.
  final Uri? uri;
  final double borderRadius;

  /// Stable per-photo colour so a mock tile doesn't jump around between
  /// rebuilds or scroll positions.
  Color get _placeholderColor {
    var hash = 0;
    for (final unit in photoId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return HSLColor.fromAHSL(1, (hash % 360).toDouble(), 0.42, 0.38).toColor();
  }

  @override
  Widget build(BuildContext context) {
    if (uri == null) {
      return _placeholder(context);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Image.network(
        uri.toString(),
        fit: BoxFit.cover,
        // Decode at roughly grid size instead of full resolution: much less
        // memory and far smoother scrolling with many photos.
        cacheWidth: 480,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) =>
            _broken(context, error),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _shimmer(context);
        },
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final base = _placeholderColor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base,
              Color.lerp(base, Colors.black, 0.35)!,
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.photo_outlined,
            color: Colors.white.withValues(alpha: 0.55),
            size: 28,
          ),
        ),
      ),
    );
  }

  Widget _shimmer(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }

  /// A thumbnail that failed to load (backend down, or no such photo id).
  /// Deliberately still shows the photo id so a wiring problem is diagnosable
  /// on screen instead of just looking like a broken grid.
  Widget _broken(BuildContext context, Object error) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Tooltip(
            message: '$photoId\n$error',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    photoId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}