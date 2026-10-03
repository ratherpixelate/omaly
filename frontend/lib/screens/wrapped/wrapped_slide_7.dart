import 'package:flutter/material.dart';

class WrappedSlide7 extends StatelessWidget {
  const WrappedSlide7({super.key, required this.onNext});

  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                  'you visited 13 different locations this year',
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
