import 'package:flutter/material.dart';

class WrappedSlide10 extends StatelessWidget {
  const WrappedSlide10({super.key, required this.onNext, required this.totalPhotos});

  final VoidCallback onNext;
  final int totalPhotos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    _StatRow(label: 'Total photos taken:', value: '$totalPhotos'),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Most photos taken in a day:', value: '13/05/2026'),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Most photos taken at a location:', value: 'Location 1'),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Most photos taken with a person:', value: 'Person 1'),
                    const SizedBox(height: 28),
                    _StatRow(label: 'Your busiest month:', value: 'May 2026 (340 photos)'),
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
