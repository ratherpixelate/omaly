import 'package:flutter/material.dart';

class WrappedSlide8 extends StatelessWidget {
  const WrappedSlide8({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locations = [
      ('Location 1', 'You took 178 pictures here!'),
      ('Location 2', 'You took 129 pictures here!'),
      ('Location 3', 'You took 117 pictures here!'),
    ];

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
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < locations.length; i++) ...[
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
                          ),
                          const SizedBox(width: 40),
                          SizedBox(
                            width: 340,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  locations[i].$1,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  locations[i].$2,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (i < locations.length - 1) const SizedBox(height: 40),
                    ],
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
