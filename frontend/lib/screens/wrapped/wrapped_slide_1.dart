import 'package:flutter/material.dart';

import '../../config.dart';
import '../../widgets/photo_tile.dart';

class WrappedSlide1 extends StatelessWidget {
  const WrappedSlide1({
    super.key,
    required this.onNext,
    this.photoIds = const [],
  });

  final VoidCallback onNext;
  final List<String> photoIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onNext,
      child: Container(
        color: const Color(0xFF121318),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                // Preview cards strip extending till the end (20 cards with real photos)
                SizedBox(
                  height: 320,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    itemCount: photoIds.isNotEmpty ? (photoIds.length < 20 ? 20 : photoIds.length) : 20,
                    separatorBuilder: (context, index) => const SizedBox(width: 24),
                    itemBuilder: (context, index) {
                      final isMiddle = index == 4;
                      final photoId = photoIds.isNotEmpty
                          ? photoIds[index % photoIds.length]
                          : null;
                      final thumbUri = photoId != null
                          ? Uri.parse('$kApiBaseUrl/thumbnails/$photoId.jpg')
                          : null;

                      return Container(
                        width: 190,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1F24),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: isMiddle ? const Color(0xFFDCE4F7) : Colors.white24,
                            width: isMiddle ? 3 : 1.5,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: photoId != null
                            ? PhotoTile(
                                photoId: photoId,
                                uri: thumbUri,
                                borderRadius: 0,
                                cacheWidth: 400,
                              )
                            : const Center(
                                child: Icon(
                                  Icons.photo_outlined,
                                  color: Colors.white24,
                                  size: 40,
                                ),
                              ),
                      );
                    },
                  ),
                ),
                // Bottom right aligned Omaly Wrapped + 150% scaled button and text pushed more to the bottom
                Padding(
                  padding: const EdgeInsets.only(right: 64, bottom: 16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Omaly Wrapped',
                          style: theme.textTheme.displayMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 52, // 150% scale
                          ),
                        ),
                        const SizedBox(width: 40),
                        Material(
                          color: const Color(0xFFDCE4F7),
                          borderRadius: BorderRadius.circular(44),
                          child: InkWell(
                            onTap: onNext,
                            borderRadius: BorderRadius.circular(44),
                            child: const Padding(
                              padding: EdgeInsets.all(28), // 150% scale button
                              child: Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.black87,
                                size: 48, // 150% scale icon
                              ),
                            ),
                          ),
                        ),
                      ],
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
