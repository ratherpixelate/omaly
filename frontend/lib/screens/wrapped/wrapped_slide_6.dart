import 'package:flutter/material.dart';

import '../../config.dart';
import '../../models/wrapped.dart';

class WrappedSlide6 extends StatelessWidget {
  const WrappedSlide6({
    super.key,
    required this.onNext,
    this.people = const [],
  });

  final VoidCallback onNext;
  final List<PersonStat> people;

  Widget _avatarFallback(String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 40,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topPeople = people.take(3).toList();

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
                if (topPeople.isNotEmpty)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < topPeople.length; i++) ...[
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
                              child: topPeople[i].thumbnailUrl != null
                                  ? Image.network(
                                      '$kApiBaseUrl${topPeople[i].thumbnailUrl}',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => _avatarFallback(topPeople[i].label),
                                    )
                                  : _avatarFallback(topPeople[i].label),
                            ),
                            const SizedBox(width: 40),
                            SizedBox(
                              width: 340,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    topPeople[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.headlineMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'You took ${topPeople[i].photoCount} pictures together!',
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (i < topPeople.length - 1) const SizedBox(height: 40),
                      ],
                    ],
                  )
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_outline_rounded, size: 72, color: Colors.white38),
                      const SizedBox(height: 24),
                      Text(
                        'Solo Memories',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No recurring face clusters detected in this year.',
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
