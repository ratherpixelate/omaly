import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/wrapped.dart';

class WrappedSlide8 extends StatelessWidget {
  const WrappedSlide8({
    super.key,
    required this.onNext,
    this.locations = const [],
  });

  final VoidCallback onNext;
  final List<LocationStat> locations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topLocations = locations.take(3).toList();

    return GestureDetector(
      onTap: onNext,
      child: Container(
        color: const Color(0xFF121318),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (topLocations.isNotEmpty)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < topLocations.length; i++) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(
                                '${i + 1}.',
                                textAlign: TextAlign.right,
                                style: theme.textTheme.displayMedium?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 32),
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1F24),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(color: Colors.white24, width: 2),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: topLocations[i].thumbnailUrl != null
                                  ? Image.network(
                                      '$kApiBaseUrl${topLocations[i].thumbnailUrl}',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Center(
                                        child: Icon(
                                          Icons.location_on_outlined,
                                          color: Colors.white60,
                                          size: 36,
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.location_on_outlined,
                                        color: Colors.white60,
                                        size: 36,
                                      ),
                                    ),
                            ),
                            const SizedBox(width: 40),
                            SizedBox(
                              width: 340,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    topLocations[i].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'You took ${topLocations[i].photoCount} pictures here!',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (i < topLocations.length - 1) const SizedBox(height: 40),
                      ],
                    ],
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 72, color: Colors.white38),
                      const SizedBox(height: 24),
                      Text(
                        '100% Private & Offline',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No GPS location tags were found in your photo collection.\nYour whereabouts stayed completely private on this device.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 64),
                Text(
                  'click anywhere to proceed',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white54,
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
