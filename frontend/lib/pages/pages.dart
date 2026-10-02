import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../widgets/photo_tile.dart';

/// Gallery — the default landing page.
///
/// Grid of every photo the backend finds in its photos directory.
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  /// Single source of truth for the search field's height. The prefix icon's
  /// box is the same value, so the icon is exactly centred in a circle of the
  /// field's full height placed at the left edge.
  static const double _kSearchHeight = 88;

  /// Extra left inset applied to the prefix icon, on top of Material's own
  /// minimum prefix padding.
  static const double _kSearchIconInset = 20;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  List<Map<String, dynamic>>? _photos;
  Object? _error;
  String _query = '';
  bool _showTimelineControls = false;
  String _orderBy = 'capture_time'; // 'capture_time' | 'date_modified'
  bool _newestFirst = true;
  String _typeFilter = 'all'; // 'all' | 'photo' | 'video'
  int? _yearFilter;
  String? _sourceFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/photos'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final photos = (body['photos'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _photos = photos;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              // Pill-shaped search bar.
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: _kSearchHeight,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: (v) => setState(() => _query = v),
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            hintText: 'Search photos',
                            hintStyle: const TextStyle(fontSize: 18),
                            // The icon's box is exactly as tall as the field, so the icon
                            // stays vertically centred inside a circle of
                            // _kSearchHeight placed at the very left edge. Its width
                            // carries the extra left inset, so the icon moves right
                            // without leaving that box.
                            prefixIconConstraints: BoxConstraints.tightFor(
                              width: _kSearchHeight + _kSearchIconInset,
                              height: _kSearchHeight,
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(left: _kSearchIconInset),
                              child: Icon(Icons.search_rounded, size: 32),
                            ),
                            isDense: true,
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(100),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(100),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(100),
                              borderSide: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Circular filter button to the right of the search bar, same
                    // height and fill as the search field for matching styling.
                    Material(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.6),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () {
                          setState(
                            () =>
                                _showTimelineControls = !_showTimelineControls,
                          );
                        },
                        child: const SizedBox(
                          width: _kSearchHeight,
                          height: _kSearchHeight,
                          child: Center(
                            child: Icon(Icons.filter_list_rounded, size: 32),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _grid(context)),
            ],
          ),
          // Timeline controls card floats above the photos, like an
          // anchored dropdown; it does not push the grid down.
          if (_showTimelineControls)
            Positioned(
              top: 32 + _kSearchHeight + 12,
              right: 24,
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: 340,
                  child: _timelineControlsCard(context),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timelineControlsCard(BuildContext context) {
    final theme = Theme.of(context);

    Widget orderButton({
      required String value,
      required String title,
      required String description,
    }) {
      final selected = _orderBy == value;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Material(
          color: selected
              ? const Color(0xFFDBE2FF)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _orderBy = value),
            child: SizedBox(
              width: double.infinity,
              height: 84,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w700,
                        // Selected background is the light #DBE2FF, so the text
                        // must stay dark in both themes to remain readable.
                        color: selected
                            ? const Color(0xFF1A1C2E)
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color:
                            (selected
                                    ? const Color(0xFF1A1C2E)
                                    : theme.colorScheme.onSurface)
                                .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget pill({
      required String label,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Material(
        color: selected
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      );
    }

    Widget pillRow(List<Widget> pills) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Wrap(spacing: 10, runSpacing: 8, children: pills),
      );
    }

    Widget sectionLabel(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    // Years present in the photo metadata, newest first.
    final years = <int>{};
    for (final p in _photos ?? const []) {
      final ts = (p['modified_at'] as num?)?.toDouble();
      if (ts != null) {
        years.add(
          DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt()).year,
        );
      }
    }
    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));

    // Distinct folders ("" for photos at the root), root excluded.
    final sources = <String>{};
    for (final p in _photos ?? const []) {
      final f = p['folder'] as String? ?? '';
      if (f.isNotEmpty) sources.add(f);
    }
    final sortedSources = sources.toList()..sort();

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Timeline controls',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Order by',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 6),
            orderButton(
              value: 'capture_time',
              title: 'Capture time',
              description: 'Embedded photo or video date, with modified time as fallback',
            ),
            orderButton(
              value: 'date_modified',
              title: 'Date modified',
              description: 'When the file was last changed',
            ),
            const SizedBox(height: 12),
            pillRow([
              pill(
                label: 'Newest first',
                selected: _newestFirst,
                onTap: () => setState(() => _newestFirst = true),
              ),
              pill(
                label: 'Oldest first',
                selected: !_newestFirst,
                onTap: () => setState(() => _newestFirst = false),
              ),
            ]),
            sectionLabel('Type'),
            pillRow([
              pill(
                label: 'All',
                selected: _typeFilter == 'all',
                onTap: () => setState(() => _typeFilter = 'all'),
              ),
              pill(
                label: 'Photos',
                selected: _typeFilter == 'photo',
                onTap: () => setState(() => _typeFilter = 'photo'),
              ),
              pill(
                label: 'Videos',
                selected: _typeFilter == 'video',
                onTap: () => setState(() => _typeFilter = 'video'),
              ),
            ]),
            sectionLabel('Time'),
            pillRow([
              pill(
                label: 'All',
                selected: _yearFilter == null,
                onTap: () => setState(() => _yearFilter = null),
              ),
              for (final y in sortedYears)
                pill(
                  label: '$y',
                  selected: _yearFilter == y,
                  onTap: () => setState(() => _yearFilter = y),
                ),
            ]),
            sectionLabel('Source'),
            pillRow([
              pill(
                label: 'All',
                selected: _sourceFilter == null,
                onTap: () => setState(() => _sourceFilter = null),
              ),
              for (final s in sortedSources)
                pill(
                  label: s,
                  selected: _sourceFilter == s,
                  onTap: () => setState(() => _sourceFilter = s),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  String _emptyMessage(String q) {
    if (q.isNotEmpty) return 'No photos match "$q".';
    final hasFilters =
        _typeFilter != 'all' || _yearFilter != null || _sourceFilter != null;
    if (!hasFilters) return 'No photos found.';
    return switch (_typeFilter) {
      'video' =>
        _yearFilter == null && _sourceFilter == null
            ? 'No videos found.'
            : 'No videos match the selected filters.',
      'photo' =>
        _yearFilter == null && _sourceFilter == null
            ? 'No photos found.'
            : 'No photos match the selected filters.',
      _ => 'No matches for the selected filters.',
    };
  }

  Widget _grid(BuildContext context) {
    final photos = _photos;
    final q = _query.trim().toLowerCase();
    final visible = (photos == null || q.isEmpty)
        ? photos?.toList()
        : photos
              .where((p) => (p['name'] as String).toLowerCase().contains(q))
              .toList();

    // Apply the timeline controls: sort by the chosen date, direction by the pill.
    // We only have filesystem mtime (the backend's `modified_at`); "capture time"
    // equals it until the backend starts extracting EXIF dates.
    visible?.sort((a, b) {
      final aTs = (a['modified_at'] as num?)?.toDouble() ?? 0;
      final bTs = (b['modified_at'] as num?)?.toDouble() ?? 0;
      return _newestFirst ? bTs.compareTo(aTs) : aTs.compareTo(bTs);
    });

    // Apply the Type / Time / Source filters.
    final filtered = visible?.where((p) {
      if (_typeFilter != 'all' && p['type'] != _typeFilter) return false;
      if (_yearFilter != null) {
        final ts = (p['modified_at'] as num?)?.toDouble();
        if (ts == null) return false;
        final year = DateTime.fromMillisecondsSinceEpoch((ts * 1000).toInt())
            .year;
        if (year != _yearFilter) return false;
      }
      if (_sourceFilter != null && p['folder'] != _sourceFilter) return false;
      return true;
    }).toList();

    return switch (filtered) {
      null when _error != null => Center(
        child: Text(
          'Could not load photos.\nIs the backend running?\n$_error',
          textAlign: TextAlign.center,
        ),
      ),
      null => const Center(child: CircularProgressIndicator()),
      [] => Center(child: Text(_emptyMessage(q))),
      final photos => GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 0, 2, 2),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: photos.length,
        itemBuilder: (context, i) {
          final p = photos[i];
          return PhotoTile(
            photoId: p['id'] as String,
            uri: Uri.parse('$kApiBaseUrl${p['url']}'),
            borderRadius: 0,
          );
        },
      ),
    };
  }
}

/// Folders — groups photos by their folder, each shown as a large rounded
/// thumbnail of the folder's most recently modified image, plus its name and
/// item count.
class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  List<Map<String, dynamic>>? _photos;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBaseUrl/photos'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _photos = (body['photos'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(
        child: Text(
          'Could not load photos.\nIs the backend running?\n$_error',
          textAlign: TextAlign.center,
        ),
      );
    } else if (_photos == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      // Group by folder ('' = photos directly in the root).
      final byFolder = <String, List<Map<String, dynamic>>>{};
      for (final p in _photos!) {
        byFolder.putIfAbsent(p['folder'] as String? ?? '', () => []).add(p);
      }
      final folders = byFolder.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      // Filter folders by the search query (matches folder name).
      final q = _query.trim().toLowerCase();
      final visibleFolders = q.isEmpty
          ? folders
          : folders
                .where(
                  (e) => (e.key.isEmpty ? '(root)' : e.key)
                      .toLowerCase()
                      .contains(q),
                )
                .toList();

      if (visibleFolders.isEmpty) {
        body = Center(
          child: Text(
            q.isEmpty ? 'No folders found.' : 'No folders match "$q".',
          ),
        );
      } else {
        body = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
              child: SizedBox(
                height: 88,
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    hintText: 'Search folders',
                    hintStyle: const TextStyle(fontSize: 18),
                    prefixIconConstraints: const BoxConstraints.tightFor(
                      width: 108,
                      height: 88,
                    ),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 20),
                      child: Icon(Icons.search_rounded, size: 32),
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.6),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  mainAxisExtent: 300,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                itemCount: visibleFolders.length,
                itemBuilder: (context, i) {
                  final entry = visibleFolders[i];
                  final items = entry.value;
                  items.sort((a, b) {
                    final aTs = (a['modified_at'] as num?)?.toDouble() ?? 0;
                    final bTs = (b['modified_at'] as num?)?.toDouble() ?? 0;
                    return bTs.compareTo(aTs);
                  });
                  final latest = items.first;
                  final label = entry.key.isEmpty ? '(root)' : entry.key;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: PhotoTile(
                          photoId: latest['id'] as String,
                          uri: Uri.parse('$kApiBaseUrl${latest['url']}'),
                          borderRadius: 24,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${items.length} item${items.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      }
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: body,
    );
  }
}

/// Collections — face clusters as a horizontal strip of circles.
///
/// Temporary: the circles are placeholders until the backend's face-grouping
/// endpoint is wired in. The strip never wraps; it scrolls horizontally, and
/// Shift + mouse wheel scrolls it too (Flutter's default desktop behaviour).
class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  // TODO: replace with the backend's face-grouping response.
  static const List<(String, int)> _people = [];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Collections',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              height: 160,
              child: _people.isEmpty
                  ? Center(
                      child: Text(
                        'Face clusters will appear here once the backend\n'
                        'endpoint is ready.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _people.length,
                      separatorBuilder: (_, i) => const SizedBox(width: 24),
                      itemBuilder: (context, i) {
                        final (name, count) = _people[i];
                        return Column(
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.person_rounded,
                                size: 48,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '$count items',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.6,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings — title plus a stack of placeholder cards styled like the
/// sidebar navigation buttons.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static const List<String> _items = [
    'Appearance',
    'Media Viewer',
    'General',
    'Backup & restore',
    'Manage Local Models',
    'Smart Features',
    'About',
  ];

  static const Map<String, String> _bodies = {
    'Appearance': 'Theme, colors and visual effects',
    'Media Viewer': 'Viewing experience, editor, video playback',
    'General': 'Various general settings',
    'Backup & restore': 'Export and import settings',
    'Manage Local Models': 'Manage models installed on your device',
    'Smart Features': 'Control what smart features you want to use',
    'About': 'Know more about the application',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, i) => const SizedBox(height: 2),
                itemBuilder: (context, i) => _SettingsCard(
                  label: _items[i],
                  body: _bodies[_items[i]] ?? '',
                  radius: BorderRadius.vertical(
                    top: Radius.circular(i == 0 ? 24 : 6),
                    bottom: Radius.circular(i == _items.length - 1 ? 24 : 6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A settings row styled exactly like a sidebar navigation button: same
/// height, fill colour, corner radius, and inner padding.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.label,
    required this.body,
    this.radius = BorderRadius.zero,
  });

  final String label;
  final String body;

  /// Corner radius — the first card gets a rounder top, the last a rounder
  /// bottom, so the stack reads as one grouped list.
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white70 : const Color(0xFF1A1C2E);

    return Material(
      // Light mode gets the light card colour; dark mode keeps the dark one.
      color: isDark ? const Color(0xFF1E1F24) : const Color(0xFFE8E7EF),
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {},
        hoverColor: Colors.white.withValues(alpha: 0.04),
        splashColor: Colors.white.withValues(alpha: 0.06),
        highlightColor: Colors.white.withValues(alpha: 0.02),
        child: SizedBox(
          height: 109,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Row(
              children: [
                // Circle on the left of the title and body.
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
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
