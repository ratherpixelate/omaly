import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../widgets/photo_tile.dart';

/// A single opened photo.
///
/// This is the one thing that takes over the whole window: [open] pushes an
/// opaque full-screen route, so the sidebar is hidden behind it. Push with
/// `Navigator.pop` to come back to the sidebar.
class PhotoDetailPage extends StatelessWidget {
  const PhotoDetailPage({
    super.key,
    required this.photoId,
    this.api,
    this.imageUrl,
  });

  final String photoId;

  /// Optional, so the page stays usable before the client is wired in.
  final ApiClient? api;

  /// Full-resolution image URL. Preferred over [api]'s thumbnail when set,
  /// so the viewer shows the real photo fitted to the screen.
  final Uri? imageUrl;

  /// Open [photoId] full-screen, hiding the sidebar.
  ///
  /// The route is opaque and pushed over the shell, which is what takes the
  /// sidebar off screen — no shell state has to change.
  ///
  /// Returns the route's future, which completes only when the photo is
  /// closed. Do **not** `await` this when you just want to navigate; await it
  /// only if you need the result of the photo page.
  static Future<void> open(
    BuildContext context, {
    required String photoId,
    ApiClient? api,
    Uri? imageUrl,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, _, _) =>
            PhotoDetailPage(photoId: photoId, api: api, imageUrl: imageUrl),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uri = imageUrl ?? api?.thumbnailUri(photoId);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Photo fitted to the screen, with pinch-zoom / pan for free.
          InteractiveViewer(
            child: Center(
              child: uri == null
                  ? PhotoTile(photoId: photoId, uri: null, borderRadius: 0)
                  : Image.network(
                      uri.toString(),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => PhotoTile(
                        photoId: photoId,
                        uri: uri,
                        borderRadius: 0,
                      ),
                    ),
            ),
          ),
          // Escape is the desktop equivalent of a back arrow, so the photo can
          // always be dismissed without needing any on-screen chrome.
          Positioned(
            top: 12,
            left: 12,
            child: IconButton(
              tooltip: 'Close (Esc)',
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }
}
