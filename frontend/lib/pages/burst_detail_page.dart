import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../models/burst.dart';
import '../widgets/photo_tile.dart';
import 'photo_detail_page.dart';

/// Full-page inspection view for a burst group and its ranked best shots.
class BurstDetailPage extends StatefulWidget {
  const BurstDetailPage({
    super.key,
    required this.burst,
    required this.api,
  });

  final BurstGroup burst;
  final ApiClient api;

  @override
  State<BurstDetailPage> createState() => _BurstDetailPageState();
}

class _BurstDetailPageState extends State<BurstDetailPage> {
  late BurstGroup _burst;
  BurstPhoto? _selectedPhoto;

  @override
  void initState() {
    super.initState();
    _burst = widget.burst;
    _selectedPhoto = _burst.bestPhoto ?? (_burst.photos.isNotEmpty ? _burst.photos.first : null);
  }

  void _openPhoto(BurstPhoto photo) {
    final imgUrl = photo.url != null
        ? Uri.parse('$kApiBaseUrl${photo.url}')
        : (photo.thumbnailUrl != null
            ? Uri.parse('$kApiBaseUrl${photo.thumbnailUrl}')
            : null);
    PhotoDetailPage.open(
      context,
      photoId: photo.id,
      api: widget.api,
      imageUrl: imgUrl,
    );
  }

  Widget _buildHeroPreview(
    ThemeData theme,
    BurstPhoto photo, {
    required Color cardBg,
    required Color borderColor,
  }) {
    final fullUri = photo.url != null
        ? Uri.parse('$kApiBaseUrl${photo.url}')
        : (photo.thumbnailUrl != null
            ? Uri.parse('$kApiBaseUrl${photo.thumbnailUrl}')
            : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          photo.isBest ? 'AI Best Shot' : 'Selected Frame (Rank #${photo.rank})',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: photo.isBest
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : borderColor,
              width: photo.isBest ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    height: 500,
                    width: double.infinity,
                    color: Colors.black,
                    child: InkWell(
                      onTap: () => _openPhoto(photo),
                      child: fullUri != null
                          ? Image.network(
                              fullUri.toString(),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) => PhotoTile(
                                photoId: photo.id,
                                uri: fullUri,
                                borderRadius: 0,
                              ),
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (photo.thumbnailUrl != null)
                                      Center(
                                        child: Image.network(
                                          '$kApiBaseUrl${photo.thumbnailUrl}',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    Center(
                                      child: CircularProgressIndicator(
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                );
                              },
                            )
                          : PhotoTile(
                              photoId: photo.id,
                              uri: null,
                              borderRadius: 0,
                            ),
                    ),
                  ),
                  if (photo.isBest)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCE4F7),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black38,
                              blurRadius: 8,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star_rounded, color: Color(0xFF1A1C2E), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'AI BEST SHOT',
                              style: TextStyle(
                                color: Color(0xFF1A1C2E),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: FilledButton.icon(
                      onPressed: () => _openPhoto(photo),
                      icon: const Icon(Icons.fullscreen_rounded, size: 18),
                      label: const Text('View Full Screen'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.75),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _MetricChip(
                      label: 'Overall Score',
                      value: photo.score != null
                          ? '${(photo.score! * 100).toStringAsFixed(1)}%'
                          : 'N/A',
                      icon: Icons.score_rounded,
                      highlight: photo.isBest,
                    ),
                    _MetricChip(
                      label: 'Eye Openness',
                      value: photo.nClosed == 0 ? 'All Open' : '${photo.nClosed} Closed',
                      icon: Icons.remove_red_eye_outlined,
                      highlight: photo.nClosed == 0,
                    ),
                    _MetricChip(
                      label: 'Sharpness',
                      value: photo.sharpness != null
                          ? '${(photo.sharpness! * 100).toStringAsFixed(0)}%'
                          : 'N/A',
                      icon: Icons.shutter_speed_rounded,
                    ),
                    if (photo.nFaces != null && photo.nFaces! > 0)
                      _MetricChip(
                        label: 'Faces Tracked',
                        value: '${photo.nFaces}',
                        icon: Icons.face_rounded,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1F24) : const Color(0xFFE8E7EF);
    final borderColor = isDark ? Colors.white10 : Colors.black12;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.burst_mode_rounded, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              'Burst ${_burst.id}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Text(
                '${_burst.photoCount} photos',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 16, 32, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // AI Explanation Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Eye-Aware & Clarity Best Shot Picker',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Evaluated facial landmarks for blinking (EAR), multi-scale sharpness, and facial clarity across all ${_burst.photoCount} burst frames.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Top Hero: Selected / Best Photo
            if (_selectedPhoto != null)
              _buildHeroPreview(
                theme,
                _selectedPhoto!,
                cardBg: cardBg,
                borderColor: borderColor,
              ),

            const SizedBox(height: 36),

            // All Burst Candidates Grid
            Text(
              'All Burst Shots',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.82,
              ),
              itemCount: _burst.photos.length,
              itemBuilder: (context, index) {
                final photo = _burst.photos[index];
                final isSelected = _selectedPhoto?.id == photo.id;

                final photoUri = photo.url != null
                    ? Uri.parse('$kApiBaseUrl${photo.url}')
                    : (photo.thumbnailUrl != null
                        ? Uri.parse('$kApiBaseUrl${photo.thumbnailUrl}')
                        : null);

                return InkWell(
                  onTap: () => setState(() => _selectedPhoto = photo),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (photo.isBest
                                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                                : borderColor),
                        width: isSelected || photo.isBest ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PhotoTile(
                                photoId: photo.id,
                                uri: photoUri,
                                borderRadius: 0,
                                cacheWidth: 600,
                              ),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: photo.isBest
                                        ? const Color(0xFFDCE4F7)
                                        : Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: photo.isBest
                                        ? const [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 4,
                                              offset: Offset(0, 1),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Text(
                                    photo.isBest ? '★ Best Shot' : '#${photo.rank}',
                                    style: TextStyle(
                                      color: photo.isBest ? const Color(0xFF1A1C2E) : Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                photo.filename,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    photo.score != null
                                        ? '${(photo.score! * 100).toInt()}% quality'
                                        : 'Candidate',
                                    style: TextStyle(
                                      color: photo.isBest
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (photo.nClosed == 0)
                                    Icon(
                                      Icons.check_circle_outline_rounded,
                                      size: 14,
                                      color: theme.colorScheme.primary,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final chipBg = highlight
        ? (isDark
            ? const Color(0xFF6C5CE7).withValues(alpha: 0.16)
            : const Color(0xFFDCE4F7).withValues(alpha: 0.6))
        : (isDark
            ? const Color(0xFF2A2B32)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5));

    final border = highlight
        ? Border.all(
            color: isDark
                ? const Color(0xFF6C5CE7).withValues(alpha: 0.4)
                : const Color(0xFF6C5CE7).withValues(alpha: 0.3),
            width: 1,
          )
        : Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 1,
          );

    final textColor = highlight
        ? (isDark ? const Color(0xFFDCE4F7) : const Color(0xFF1A1C2E))
        : theme.colorScheme.onSurface;

    final iconColor = highlight
        ? (isDark ? const Color(0xFFA29BFE) : const Color(0xFF6C5CE7))
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: chipBg,
        borderRadius: BorderRadius.circular(12),
        border: border,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
