import 'package:flutter/material.dart';

class WrappedSlide7 extends StatelessWidget {
  const WrappedSlide7({
    super.key,
    required this.onNext,
    this.locationCount = 0,
  });

  final VoidCallback onNext;
  final int locationCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locationText = locationCount > 0
        ? 'you visited $locationCount different locations this year'
        : 'your location details stayed 100% private & offline';
    return GestureDetector(
      onTap: onNext,
      child: Container(
        color: const Color(0xFF121318),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Let\'s see places you',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    fontSize: 52,
                  ),
                ),
                Text(
                  'visited the most.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    fontSize: 52,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  locationText,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 64),
                Material(
                  color: const Color(0xFFDCE4F7),
                  borderRadius: BorderRadius.circular(36),
                  child: InkWell(
                    onTap: onNext,
                    borderRadius: BorderRadius.circular(36),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 56,
                        vertical: 20,
                      ),
                      child: Text(
                        'continue',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
