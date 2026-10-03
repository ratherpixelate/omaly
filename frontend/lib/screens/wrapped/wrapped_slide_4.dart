import 'package:flutter/material.dart';

class WrappedSlide4 extends StatelessWidget {
  const WrappedSlide4({
    super.key,
    required this.onNext,
    required this.totalPhotos,
    this.year,
    this.peakDay,
    this.peakCount,
  });

  final VoidCallback onNext;
  final int totalPhotos;
  final int? year;
  final String? peakDay;
  final int? peakCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentYear = DateTime.now().year;
    final yearLabel = (year != null && year != currentYear)
        ? 'photos in $year'
        : 'photos this year';

    final peakText = (peakDay != null && peakCount != null)
        ? 'You took the most pics on $peakDay ($peakCount photos)'
        : 'Every moment captured, preserved 100% on this device.';

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
                  'You took $totalPhotos',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    fontSize: 52,
                  ),
                ),
                Text(
                  yearLabel,
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
                  peakText,
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
                        'wohoo!',
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
