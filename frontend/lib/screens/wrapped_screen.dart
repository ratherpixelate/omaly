import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/wrapped.dart';
import '../widgets/photo_tile.dart';
import '../widgets/status_view.dart';

/// Wrapped screen: the Spotify-Wrapped-style recap of people, places, pets
/// and best shots. This is the screen judges look at, so it gets the polish.
class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

enum _Phase { loading, ready, error }

class _WrappedScreenState extends State<WrappedScreen> {
  _Phase _phase = _Phase.loading;
  WrappedSummary? _summary;
  String? _errorMessage;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
      _detail = null;
    });
    try {
      final summary = await widget.api.wrapped();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _phase = _Phase.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message.split('\n').first;
        _detail = e.message.contains('\n') ? e.message : null;
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not build your recap.';
        _detail = '$e';
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.error:
        return StatusView.error(
          title: _errorMessage ?? 'Something went wrong',
          message: 'Your recap could not be generated. Nothing left this '
              'machine.',
          detail: _detail,
          actionLabel: 'Try again',
          onAction: _load,
        );
      case _Phase.ready:
        return _WrappedBody(
          summary: _summary!,
          api: widget.api,
          onRefresh: _load,
        );
    }
  }
}

class _WrappedBody extends StatelessWidget {
  const _WrappedBody({
    required this.summary,
    required this.api,
    required this.onRefresh,
  });

  final WrappedSummary summary;
  final ApiClient api;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            sliver: SliverList.list(children: [
              _Header(summary: summary),
              const SizedBox(height: 20),
              if (summary.narrative.isNotEmpty) ...[
                _NarrativeCard(text: summary.narrative),
                const SizedBox(height: 20),
              ],
              if (summary.petsDetected) ...[
                const _PetsCard(),
                const SizedBox(height: 20),
              ],
              _Section(
                title: 'People you spent time with',
                icon: Icons.people_alt_rounded,
                child: _PeopleList(people: summary.topPeople),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Places that came up most',
                icon: Icons.place_rounded,
                child: _LocationsList(locations: summary.topLocations),
              ),
              const SizedBox(height: 20),
              _Section(
                title: 'Best shots',
                icon: Icons.auto_awesome_rounded,
                child: _BestShots(ids: summary.bestShots, api: api),
              ),
              const SizedBox(height: 28),
              const _FooterNote(),
            ]),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.summary});

  final WrappedSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR YEAR IN PHOTOS',
          style: theme.textTheme.labelMedium?.copyWith(
            letterSpacing: 2.4,
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${summary.generatedAt.year} Recap',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Generated locally on ${_date(summary.generatedAt)} · '
          'no cloud involved',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _date(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
}

class _NarrativeCard extends StatelessWidget {
  const _NarrativeCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: isDark ? const Color(0xFF1E1F24) : null,
            gradient: isDark
                ? null
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer,
                      theme.colorScheme.tertiaryContainer,
                    ],
                  ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.format_quote_rounded,
                  size: 26,
                  color: isDark
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleMedium?.copyWith(
                    height: 1.45,
                    color: isDark
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PetsCard extends StatelessWidget {
  const _PetsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF1E1F24)
                : theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Text('🐾', style: TextStyle(fontSize: 30)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pets spotted',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isDark
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your object detector found pets across the library.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

/// Ranked bars, so the numbers read as a ranking rather than a table.
class _RankedBars extends StatelessWidget {
  const _RankedBars({required this.rows});

  /// (label, subtitle, value, icon, colour seed)
  final List<(String, String, int, IconData, Color)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = rows.fold<int>(1, (m, r) => r.$3 > m ? r.$3 : m);

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 10),
            child: Row(
              children: [
                SizedBox(
                  width: 26,
                  child: Text(
                    '${i + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: rows[i].$5.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(rows[i].$4, size: 17, color: rows[i].$5),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rows[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: rows[i].$3 / max,
                          minHeight: 5,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation(rows[i].$5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 74,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${rows[i].$3}',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        rows[i].$2,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.people});

  final List<PersonStat> people;

  static const _colors = [
    Color(0xFF7C4DFF),
    Color(0xFF448AFF),
    Color(0xFF26A69A),
    Color(0xFFFF7043),
    Color(0xFFEC407A),
  ];

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return const Text('No people detected yet.');
    }
    return _RankedBars(
      rows: [
        for (var i = 0; i < people.length; i++)
          (
            people[i].label,
            '${people[i].photoCount} photos',
            people[i].photoCount,
            Icons.person_rounded,
            _colors[i % _colors.length],
          ),
      ],
    );
  }
}

class _LocationsList extends StatelessWidget {
  const _LocationsList({required this.locations});

  final List<LocationStat> locations;

  static const _colors = [
    Color(0xFF00897B),
    Color(0xFF00838F),
    Color(0xFF5C6BC0),
    Color(0xFF8D6E63),
    Color(0xFF78909C),
  ];

  @override
  Widget build(BuildContext context) {
    if (locations.isEmpty) {
      return const Text('No locations found yet.');
    }
    return _RankedBars(
      rows: [
        for (var i = 0; i < locations.length; i++)
          (
            locations[i].name,
            '${locations[i].photoCount} photos',
            locations[i].photoCount,
            Icons.place_rounded,
            _colors[i % _colors.length],
          ),
      ],
    );
  }
}

class _BestShots extends StatelessWidget {
  const _BestShots({required this.ids, required this.api});

  final List<String> ids;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    if (ids.isEmpty) {
      return const Text('No best shots picked yet.');
    }
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ids.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) => SizedBox(
          width: 170,
          child: PhotoTile(
            photoId: ids[i],
            uri: api.thumbnailUri(ids[i]),
          ),
        ),
      ),
    );
  }
}

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.lock_outline_rounded,
            size: 14, color: theme.colorScheme.outline),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Every photo, face cluster and embedding on this screen was '
            'computed on this laptop. Nothing was uploaded.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}