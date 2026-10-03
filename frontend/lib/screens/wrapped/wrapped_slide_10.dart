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

    final mostDay = stats?.mostPhotosTakenInADay != null
        ? '${stats!.mostPhotosTakenInADay!.formattedDate} (${stats.mostPhotosTakenInADay!.photoCount} photos)'
        : 'No single peak day recorded';

    final mostLoc = stats?.mostVisitedLocation != null
        ? stats!.mostVisitedLocation!.name
        : (summary.topLocations.isNotEmpty
            ? summary.topLocations.first.name
            : 'Private / Offline (No GPS)');

    final mostPerson = stats?.mostPhotosWithAPerson != null
        ? '${stats!.mostPhotosWithAPerson!.label} (${stats.mostPhotosWithAPerson!.photoCount} photos)'
        : (summary.topPeople.isNotEmpty
            ? '${summary.topPeople.first.label} (${summary.topPeople.first.photoCount} photos)'
            : 'None identified');

    final busiestM = stats?.busiestMonth != null
        ? '${stats!.busiestMonth!.formattedMonth} (${stats.busiestMonth!.photoCount} photos)'
        : 'N/A';

    return GestureDetector(
      onTap: onNext,
      child: Container(
        color: const Color(0xFF121318),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
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
                    const SizedBox(height: 40),
                    _StatRow(label: 'Total photos taken:', value: '$photosCount'),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Most photos taken in a day:', value: mostDay),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Most photos taken at a location:', value: mostLoc),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Most photos taken with a person:', value: mostPerson),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Your busiest month:', value: busiestM),
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
