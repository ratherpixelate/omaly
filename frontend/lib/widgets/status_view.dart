import 'package:flutter/material.dart';

/// Centered message used for the search screen's idle, empty and error
/// states. Shared so all three look like one family.
class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
    this.tone = StatusTone.neutral,
  });

  /// Nothing searched yet — invites the user to type.
  const StatusView.idle({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  })  : icon = Icons.search_rounded,
        detail = null,
        tone = StatusTone.neutral;

  /// Query ran fine, backend returned zero rows.
  const StatusView.empty({
    super.key,
    required this.title,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  })  : icon = Icons.image_search_outlined,
        tone = StatusTone.neutral;

  /// Backend unreachable, timed out, or broke the contract.
  const StatusView.error({
    super.key,
    required this.title,
    required this.message,
    this.detail,
    this.actionLabel,
    this.onAction,
  })  : icon = Icons.cloud_off_rounded,
        tone = StatusTone.error;

  final IconData icon;
  final String title;
  final String message;
  final String? detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorTint = theme.colorScheme.error;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 44,
                color: tone == StatusTone.error
                    ? errorTint
                    : theme.colorScheme.outlineVariant,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (detail != null) ...[
                const SizedBox(height: 14),
                // Monospace + selectable so an ApiException's technical detail
                // can be copied out of a screenshot during the demo.
                SelectableText(
                  detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tone == StatusTone.error
                        ? errorTint.withValues(alpha: 0.85)
                        : theme.colorScheme.outline,
                    fontFamily: 'monospace',
                    height: 1.45,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 22),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum StatusTone { neutral, error }

/// Skeleton tiles shown while a search is in flight. Keeps the grid's shape
/// stable so the layout doesn't jump when results land.
class LoadingGrid extends StatelessWidget {
  const LoadingGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 220).floor().clamp(2, 8);
        return GridView.builder(
          padding: const EdgeInsets.all(20),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ColoredBox(color: base),
          ),
        );
      },
    );
  }
}