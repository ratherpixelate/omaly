import 'package:flutter/material.dart';

import '../../models/wrapped.dart';

class WrappedSlide10 extends StatelessWidget {
  const WrappedSlide10({
    super.key,
    required this.onNext,
    required this.summary,
    this.totalPhotos,
  });

  final VoidCallback onNext;
  final WrappedSummary summary;
  final int? totalPhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = summary.statistics;
    final photosCount = totalPhotos ??
        (summary.totalPhotos > 0
            ? summary.totalPhotos
            : (summary.photosInYear.isNotEmpty ? summary.photosInYear.length : 0));

    final statItems = <Widget>[
      _StatRow(label: 'Total photos taken:', value: '$photosCount'),
    ];

    if (stats?.mostPhotosTakenInADay != null) {
      final day = stats!.mostPhotosTakenInADay!;
      statItems.add(
        _StatRow(
          label: 'Most photos taken in a day:',
          value: '${day.formattedDate} (${day.photoCount} photos)',
        ),
      );
    }

    if (stats?.busiestMonth != null) {
      final m = stats!.busiestMonth!;
      statItems.add(
        _StatRow(
          label: 'Your busiest month:',
          value: '${m.formattedMonth} (${m.photoCount} photos)',
        ),
      );
    }

    if (stats?.mostActiveTime != null) {
      statItems.add(
        _StatRow(
          label: 'Most active time of day:',
          value: stats!.mostActiveTime!,
        ),
      );
    }

    final topPerson = stats?.mostPhotosWithAPerson ??
        (summary.topPeople.isNotEmpty ? summary.topPeople.first : null);
    if (topPerson != null && topPerson.photoCount > 0) {
      statItems.add(
        _StatRow(
          label: 'Most photos taken with:',
          value: '${topPerson.label} (${topPerson.photoCount} photos)',
        ),
      );
    }

    final topLoc = stats?.mostVisitedLocation ??
        (summary.topLocations.isNotEmpty ? summary.topLocations.first : null);
    if (topLoc != null) {
      statItems.add(
        _StatRow(
          label: 'Most photos taken at a location:',
          value: topLoc.name,
        ),
      );
    }

    final burstCount = stats?.burstGroupsCount;
    if (burstCount != null && burstCount > 0) {
      statItems.add(
        _StatRow(
          label: 'Burst moments captured:',
          value: '$burstCount burst ${burstCount == 1 ? "group" : "groups"}',
        ),
      );
    }

    return GestureDetector(
      onTap: onNext,
      child: Container(
        color: const Color(0xFF121318),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Statistics',
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 36),
                    for (var i = 0; i < statItems.length; i++) ...[
                      if (i > 0) const SizedBox(height: 24),
                      statItems[i],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
