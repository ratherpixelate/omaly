import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
// ScrollCacheExtent lives in the rendering layer and is not re-exported by
// material.dart.
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../config.dart';
import '../models/burst.dart';
import '../models/person.dart';
import '../screens/wrapped_screen.dart';
import '../widgets/photo_tile.dart';
import '../widgets/video_player_view.dart';
import 'burst_detail_page.dart';
import 'person_detail_page.dart';
import 'photo_detail_page.dart';

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

  /// Decode width for gallery grid tiles. The grid caps tiles at 140 logical
  /// px, so 280 covers a 2x display without decoding the full-size photo.
  static const int _kTileDecodeWidth = 280;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounceTimer;

  List<Map<String, dynamic>>? _photos;
  Object? _error;
  String _query = '';

  // Server-side object search: /search (CLIP text search in the backend).
  List<Map<String, dynamic>>? _searchResults;
  bool _searching = false;
  Object? _searchError;
  int _searchSeq = 0;

  bool _showTimelineControls = false;
  String _orderBy = 'capture_time'; // 'capture_time' | 'date_modified'
  bool _newestFirst = true;
  String _typeFilter = 'all'; // 'all' | 'photo' | 'video'
  int? _yearFilter;
  String? _sourceFilter;

  /// Photo currently shown in the right preview panel (follows the mouse and
  /// keeps the last one after the cursor leaves).
  Map<String, dynamic>? _hovered;

  /// Photo opened in focus mode (click): grid covered, photo fills the card.
  Map<String, dynamic>? _focused;

  /// Whether the right preview panel is open. Starts closed; toggled by the
  /// sidebar button beside the filter button.
  bool _panelOpen = false;

  /// Identifies the current filter selection. Used as the grid's key so
  /// changing any filter crossfades the whole grid instead of rearranging
  /// tiles in place.
  String get _filterSignature =>
      '$_typeFilter|$_yearFilter|$_sourceFilter|$_newestFirst|$_orderBy|${_photos?.length}';

  /// Key used by AnimatedSwitcher to smoothly transition when filtering or searching.
  String get _viewSignature {
    final q = _query.trim();
    if (q.isNotEmpty) {
      return 'search|$q|$_searchSeq|${_searchResults?.length}|$_newestFirst|$_searching';
    }
    return _filterSignature;
  }

  /// True when any filter pill differs from its default.
  bool get _hasActiveFilter =>
      _typeFilter != 'all' || _yearFilter != null || _sourceFilter != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
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

  Future<void> _runSearch(String q) async {
    final seq = ++_searchSeq;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final uri = Uri.parse('$kApiBaseUrl/search')
          .replace(queryParameters: {'q': q, 'top_k': '40'});
      debugPrint('[omaly search] Requesting $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted || seq != _searchSeq) return;
      final results = (body['results'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      debugPrint('[omaly search] Found ${results.length} results for "$q"');
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (e) {
      debugPrint('[omaly search] Error: $e');
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _searchError = e;
        _searching = false;
      });
    }
  }

  Future<void> _openBurstForPhoto(String burstGroupId) async {
    try {
      final client = createApiClient();
      final bursts = await client.getBursts();
      final target = bursts.firstWhere(
        (b) => b.id == burstGroupId,
        orElse: () => bursts.first,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BurstDetailPage(
            burst: target,
            api: client,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open burst: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // The grid + preview panel stay mounted under the focus view so closing
      // it never re-fetches or re-renders the tiles.
      body: Stack(
        children: [
          Column(
            children: [
              // Pill-shaped search bar, filter button and panel toggle.
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
                          onChanged: (v) {
                            _debounceTimer?.cancel();
                            setState(() => _query = v);
                            final q = v.trim();
                            if (q.isEmpty) {
                              _searchSeq++;
                              setState(() {
                                _searchResults = null;
                                _searchError = null;
                                _searching = false;
                              });
                            } else {
                              _debounceTimer = Timer(
                                const Duration(milliseconds: 350),
                                () => _runSearch(q),
                              );
                            }
                          },
                          onSubmitted: (v) {
                            _debounceTimer?.cancel();
                            final q = v.trim();
                            if (q.isNotEmpty) {
                              _runSearch(q);
                            } else {
                              _searchSeq++;
                              setState(() {
                                _searchResults = null;
                                _searchError = null;
                                _searching = false;
                              });
                            }
                          },
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            hintText: 'Search photos',
                            hintStyle: const TextStyle(fontSize: 18),
                            // The icon's box is exactly as tall as the field,
                            // so the icon stays vertically centred inside a
                            // circle of _kSearchHeight placed at the left edge.
                            prefixIconConstraints: BoxConstraints.tightFor(
                              width: _kSearchHeight + _kSearchIconInset,
                              height: _kSearchHeight,
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(left: _kSearchIconInset),
                              child: Icon(Icons.search_rounded, size: 32),
                            ),
                            suffixIconConstraints: const BoxConstraints.tightFor(
                              width: 48,
                              height: _kSearchHeight,
                            ),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.only(right: 14),
                                    child: Center(
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  )
                                : (_query.isNotEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 20,
                                          ),
                                          tooltip: 'Clear search',
                                          onPressed: () {
                                            _debounceTimer?.cancel();
                                            _searchController.clear();
                                            _searchSeq++;
                                            setState(() {
                                              _query = '';
                                              _searchResults = null;
                                              _searchError = null;
                                              _searching = false;
                                            });
                                          },
                                        ),
                                      )
                                    : null),
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
                    // Circular filter button, same height and fill as the
                    // search field. Colored when filters are active.
                    _roundIconButton(
                      icon: Icons.filter_list_rounded,
                      active: _showTimelineControls || _hasActiveFilter,
                      onTap: () => setState(
                        () => _showTimelineControls = !_showTimelineControls,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Circular sidebar/panel toggle button, same style.
                    _roundIconButton(
                      icon: Icons.view_sidebar_outlined,
                      active: _panelOpen,
                      onTap: () => setState(() => _panelOpen = !_panelOpen),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: KeyedSubtree(
                          key: ValueKey(_viewSignature),
                          child: _grid(context),
                        ),
                      ),
                    ),
                    // Right preview panel: follows the hovered tile and keeps
                    // the last one; collapses smoothly when closed.
                    ClipRect(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        width: _panelOpen ? 380 : 0,
                        child: _panelOpen
                            ? (_hovered == null
                                  ? _emptyPreview(context)
                                  : _previewPanel(context, _hovered!))
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Tap anywhere outside the Timeline controls card to close it.
          if (_showTimelineControls)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showTimelineControls = false),
              ),
            ),
          // Timeline controls card floats above the photos, anchored to the
          // filter button; it does not push the grid down.
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
          // Focus view on top; the grid underneath stays mounted.
          if (_focused != null) _focusView(context),
        ],
      ),
    );
  }

  /// Square icon button matching the search field's height and fill.
  ///
  /// Rests as a rounded rectangle (32px corners) and becomes a full circle
  /// when [active], which is also when it takes the #DBE2FF tint and dark
  /// glyph. The shape change is animated so the morph reads as one control.
  Widget _roundIconButton({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    // A square needs radius == half its side to render as a full circle.
    final restingRadius = BorderRadius.circular(32);
    final activeRadius = BorderRadius.circular(_kSearchHeight / 2);

    return TweenAnimationBuilder<BorderRadius?>(
      tween: BorderRadiusTween(
        begin: restingRadius,
        end: active ? activeRadius : restingRadius,
      ),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, radius, _) {
        return Material(
          color: active
              ? const Color(0xFFDBE2FF)
              : Theme.of(context).colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(borderRadius: radius ?? restingRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // customBorder needs a non-null radius; the tween never yields null.
            customBorder: RoundedRectangleBorder(
              borderRadius: radius ?? restingRadius,
            ),
            onTap: onTap,
            child: SizedBox(
              width: _kSearchHeight,
              height: _kSearchHeight,
              child: Icon(
                icon,
                size: 32,
                color: active
                    ? const Color(0xFF1A1C2E)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        );
      },
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
              pill(
                label: 'Bursts',
                selected: _typeFilter == 'burst',
                onTap: () => setState(() => _typeFilter = 'burst'),
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
      'burst' =>
        _yearFilter == null && _sourceFilter == null
            ? 'No burst photos found.'
            : 'No burst photos match the selected filters.',
      _ => 'No matches for the selected filters.',
    };
  }

  /// Placeholder shown in the preview panel when no photo has been hovered.
  Widget _emptyPreview(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 24, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: Text(
          'No preview',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  /// Right-side preview card: the hovered photo fitted inside the card, with
  /// its name and metadata.
  Widget _previewPanel(BuildContext context, Map<String, dynamic> p) {
    final theme = Theme.of(context);
    final url = p['url'] as String?;
    final uri = url == null ? null : Uri.parse('$kApiBaseUrl$url');
    final isVideo = p['type'] == 'video';

    final folder = p['folder'] as String?;
    var meta = (folder != null && folder.isNotEmpty) ? folder : '';
    final size = (p['size'] as num?)?.toInt();
    if (size != null) {
      if (meta.isNotEmpty) meta += '  •  ';
      meta += size < 1024 * 1024
          ? '${(size / 1024).toStringAsFixed(0)} KB'
          : '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    final burstGroupId = p['burst_group_id'] as String?;
    if (burstGroupId != null) {
      if (meta.isNotEmpty) meta += '  •  ';
      meta += 'Burst: $burstGroupId';
    }
    final matchedPerson = p['matched_person'] as String?;
    if (matchedPerson != null) {
      if (meta.isNotEmpty) meta += '  •  ';
      meta += 'Person: $matchedPerson';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 24, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p['name'] as String? ?? p['id'] as String,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close preview',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _hovered = null;
                    _panelOpen = false;
                  }),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: isVideo
                  ? VideoTile(
                      photoId: p['id'] as String,
                      name: p['name'] as String? ?? '',
                    )
                  : (uri == null
                        ? PhotoTile(
                            photoId: p['id'] as String,
                            uri: null,
                            borderRadius: 12,
                          )
                        : InteractiveViewer(
                            child: Center(
                              child: Image.network(
                                uri.toString(),
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                    PhotoTile(
                                      photoId: p['id'] as String,
                                      uri: uri,
                                      borderRadius: 12,
                                    ),
                              ),
                            ),
                          )),
            ),
          ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          if (burstGroupId != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: FilledButton.icon(
                onPressed: () => _openBurstForPhoto(burstGroupId),
                icon: const Icon(Icons.burst_mode_rounded, size: 16),
                label: const Text('View Burst & Best Shot'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Focus mode: the clicked photo fitted to the whole content card, with a
  /// back button to return to the grid.
  Widget _focusView(BuildContext context) {
    final p = _focused!;
    final theme = Theme.of(context);
    final url = p['url'] as String?;
    final uri = url == null ? null : Uri.parse('$kApiBaseUrl$url');
    final isVideo = p['type'] == 'video';

    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: isVideo
                ? (uri == null
                      ? VideoTile(
                          photoId: p['id'] as String,
                          name: p['name'] as String? ?? '',
                        )
                      : VideoPlayerView(uri: uri))
                : (uri == null
                      ? PhotoTile(
                          photoId: p['id'] as String,
                          uri: null,
                          borderRadius: 0,
                        )
                      : InteractiveViewer(
                          child: Center(
                            child: Image.network(
                              uri.toString(),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  PhotoTile(
                                    photoId: p['id'] as String,
                                    uri: uri,
                                    borderRadius: 0,
                                  ),
                            ),
                          ),
                        )),
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Back to grid',
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => setState(() {
                    _focused = null;
                    _panelOpen = false;
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p['matched_person'] != null
                        ? '${p['name'] ?? p['id']}  •  ${p['matched_person']}'
                        : (p['name'] as String? ?? p['id'] as String),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (p['burst_group_id'] != null) ...[
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _openBurstForPhoto(p['burst_group_id'] as String),
                    icon: const Icon(Icons.burst_mode_rounded, size: 16),
                    label: const Text('View Burst & Best Shot'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF6C5CE7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Wrap a grid tile so hover updates the preview panel and a click opens the
  /// focus view.
  Widget _tile(Map<String, dynamic> p, Widget child, {Uri? uri}) {
    final hasBurst = p['burst_group_id'] != null;
    final matchedPerson = p['matched_person'] as String?;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = p),
      child: GestureDetector(
        onTap: () => setState(() {
          _focused = p;
          _hovered = null;
          _panelOpen = false;
        }),
        child: (hasBurst || matchedPerson != null)
            ? Stack(
                fit: StackFit.expand,
                children: [
                  child,
                  if (hasBurst)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.burst_mode_rounded,
                              color: Colors.white,
                              size: 11,
                            ),
                            SizedBox(width: 3),
                            Text(
                              'Burst',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (matchedPerson != null)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 11,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              matchedPerson,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              )
            : child,
      ),
    );
  }

  Widget _searchGrid(BuildContext context, String q) {
    if (_searchError != null && _searchResults == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(
                'Search failed.\n$_searchError',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    final results = _searchResults;
    if (results == null) {
      // While debouncing or fetching initial search results, keep showing the
      // regular gallery with smooth dimmed opacity so the page never blanks out.
      return Stack(
        children: [
          AnimatedOpacity(
            opacity: _searching ? 0.45 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: _regularGrid(context),
          ),
          if (_searching)
            const Positioned(
              top: 0,
              left: 24,
              right: 24,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      );
    }

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.3,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              'No photos found for "$q"',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try searching for objects, scenes, or activities\n(e.g., "nature", "friends", "beach")',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                  ),
            ),
          ],
        ),
      );
    }

    // Honour the timeline direction pill using each result's taken_at date.
    final ordered = results.toList()
      ..sort((a, b) {
        final aTs = DateTime.tryParse(a['taken_at'] as String? ?? '');
        final bTs = DateTime.tryParse(b['taken_at'] as String? ?? '');
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return _newestFirst ? bTs.compareTo(aTs) : aTs.compareTo(bTs);
      });

    final searchView = GridView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 2),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      scrollCacheExtent: ScrollCacheExtent.pixels(800),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      itemCount: ordered.length,
      itemBuilder: (context, i) {
        final r = ordered[i];
        final thumb = r['thumbnail_url'] as String?;
        final originalUrl = r['url'] as String?;
        final uri = thumb == null ? null : Uri.parse('$kApiBaseUrl$thumb');
        final item = {
          'id': r['id'] as String,
          'name': (r['filename'] as String?) ??
              (r['name'] as String?) ??
              (r['id'] as String),
          'url': originalUrl ?? thumb,
          'burst_group_id': r['burst_group_id'],
          'matched_person': r['matched_person'],
          'type': 'photo',
        };
        return _tile(
          item,
          PhotoTile(
            photoId: r['id'] as String,
            uri: uri,
            borderRadius: 0,
            cacheWidth: _kTileDecodeWidth,
          ),
          uri: uri,
        );
      },
    );

    if (_searching) {
      return Stack(
        children: [
          AnimatedOpacity(
            opacity: 0.5,
            duration: const Duration(milliseconds: 150),
            child: searchView,
          ),
          const Positioned(
            top: 0,
            left: 24,
            right: 24,
            child: LinearProgressIndicator(minHeight: 2),
          ),
        ],
      );
    }
    return searchView;
  }

  Widget _regularGrid(BuildContext context) {
    final photos = _photos;
    final visible = photos?.toList();

    // Sort by the chosen date, direction by the pill. We only have filesystem
    // mtime (the backend's `modified_at`); "capture time" equals it until the
    // backend starts extracting EXIF dates.
    visible?.sort((a, b) {
      final aTs = (a['modified_at'] as num?)?.toDouble() ?? 0;
      final bTs = (b['modified_at'] as num?)?.toDouble() ?? 0;
      return _newestFirst ? bTs.compareTo(aTs) : aTs.compareTo(bTs);
    });

    // Apply the Type / Time / Source filters.
    final filtered = visible?.where((p) {
      if (_typeFilter == 'burst') {
        if (p['burst_group_id'] == null) return false;
      } else if (_typeFilter != 'all' && p['type'] != _typeFilter) {
        return false;
      }
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
      [] => Center(child: Text(_emptyMessage(_query.trim()))),
      final photos => GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 2),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        // Build tiles a bit beyond the viewport so fast scrolling lands on
        // already-decoded images instead of shimmer placeholders.
        scrollCacheExtent: ScrollCacheExtent.pixels(800),
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemCount: photos.length,
        itemBuilder: (context, i) {
          final p = photos[i];
          final isVideo = p['type'] == 'video';
          final uri = isVideo ? null : Uri.parse('$kApiBaseUrl${p['url']}');
          return _tile(
            p,
            isVideo
                ? VideoTile(
                    photoId: p['id'] as String,
                    name: p['name'] as String? ?? p['id'] as String,
                  )
                : PhotoTile(
                    photoId: p['id'] as String,
                    uri: uri,
                    borderRadius: 0,
                    cacheWidth: _kTileDecodeWidth,
                  ),
            uri: uri,
          );
        },
      ),
    };
  }

  Widget _grid(BuildContext context) {
    final q = _query.trim();
    if (q.isNotEmpty) return _searchGrid(context, q);
    return _regularGrid(context);
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

  /// Folder currently opened ('' is the photos root). Null = folder list.
  String? _openFolder;

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

  /// Human-readable byte size, e.g. "1.4 GB".
  static String _formatSize(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  /// Sum of the listed file sizes in a folder.
  static int _folderBytes(List<Map<String, dynamic>> items) {
    var total = 0;
    for (final p in items) {
      final s = (p['size'] as num?)?.toInt();
      if (s != null) total += s;
    }
    return total;
  }

  /// A single folder opened: header with back button, name, item count and
  /// total size, then that folder's photos.
  Widget _folderView(BuildContext context) {
    final theme = Theme.of(context);
    final folder = _openFolder!;
    final items =
        (_photos ?? [])
            .where((p) => (p['folder'] as String? ?? '') == folder)
            .toList()
          ..sort((a, b) {
            final aTs = (a['modified_at'] as num?)?.toDouble() ?? 0;
            final bTs = (b['modified_at'] as num?)?.toDouble() ?? 0;
            return bTs.compareTo(aTs);
          });
    final label = folder.isEmpty ? '(root)' : folder;
    final bytes = _folderBytes(items);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Row(
            children: [
              // Back arrow (Android drawable arrow_back_24).
              IconButton(
                tooltip: 'Back to folders',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _openFolder = null),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${items.length} item${items.length == 1 ? '' : 's'}'
                      '  •  ${_formatSize(bytes)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text('This folder is empty.'))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  scrollCacheExtent: ScrollCacheExtent.pixels(800),
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final p = items[i];
                    final isVideo = p['type'] == 'video';
                    return GestureDetector(
                      onTap: () {
                        if (isVideo) return;
                        PhotoDetailPage.open(
                          context,
                          photoId: p['id'] as String,
                          imageUrl: Uri.parse('$kApiBaseUrl${p['url']}'),
                        );
                      },
                      child: isVideo
                          ? VideoTile(
                              photoId: p['id'] as String,
                              name: p['name'] as String? ?? p['id'] as String,
                            )
                          : PhotoTile(
                              photoId: p['id'] as String,
                              uri: Uri.parse('$kApiBaseUrl${p['url']}'),
                              borderRadius: 0,
                              cacheWidth: 280,
                            ),
                    );
                  },
                ),
        ),
      ],
    );
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
    } else if (_openFolder != null) {
      body = _folderView(context);
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
                scrollCacheExtent: ScrollCacheExtent.pixels(600),
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
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
                  final bytes = _folderBytes(items);

                  return GestureDetector(
                    onTap: () => setState(() => _openFolder = entry.key),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: PhotoTile(
                            photoId: latest['id'] as String,
                            uri: Uri.parse('$kApiBaseUrl${latest['url']}'),
                            borderRadius: 24,
                            // Folder cards are up to 260 logical px wide.
                            cacheWidth: 520,
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
                          '${items.length} item${items.length == 1 ? '' : 's'}'
                          '  •  ${_formatSize(bytes)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
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

/// Collections — face clusters as an interactive horizontal strip of circular tiles,
/// plus the Omaly Wrapped recap card.
class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key, this.api});

  final ApiClient? api;

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  late final ApiClient _api = widget.api ?? createApiClient();
  List<PersonCluster> _people = [];
  List<BurstGroup> _bursts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await _api.getPeople();
      List<BurstGroup> bursts = [];
      try {
        bursts = await _api.getBursts();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _people = people;
        _bursts = bursts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openBurstDetail(BurstGroup burst) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BurstDetailPage(burst: burst, api: _api),
      ),
    );
  }

  Future<void> _renamePerson(PersonCluster person) async {
    final controller = TextEditingController(text: person.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1F24),
        title: const Text(
          'Rename Person',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF2A2B32),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (val) => Navigator.of(context).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != person.name) {
      final oldPeople = List<PersonCluster>.from(_people);
      setState(() {
        _people = [
          for (final p in _people)
            if (p.id == person.id) p.copyWith(name: newName) else p,
        ];
      });
      try {
        final updated = await _api.renamePerson(person.id, newName);
        if (!mounted) return;
        setState(() {
          _people = [
            for (final p in _people)
              if (p.id == updated.id)
                p.copyWith(
                  name: updated.name,
                  photoCount: updated.photoCount,
                  coverPhotoId: updated.coverPhotoId ?? p.coverPhotoId,
                  thumbnailUrl: updated.thumbnailUrl ?? p.thumbnailUrl,
                )
              else
                p,
          ];
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _people = oldPeople);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename: $e')),
        );
      }
    }
  }

  Future<void> _openPersonDetail(PersonCluster person) async {
    final updated = await Navigator.push<PersonCluster>(
      context,
      MaterialPageRoute(
        builder: (_) => PersonDetailPage(person: person, api: _api),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _people = [
          for (final p in _people)
            if (p.id == updated.id)
              p.copyWith(
                name: updated.name,
                photoCount: updated.photoCount,
                coverPhotoId: updated.coverPhotoId ?? p.coverPhotoId,
                thumbnailUrl: updated.thumbnailUrl ?? p.thumbnailUrl,
              )
            else
              p,
        ];
      });
    }
  }

  void _openWrapped(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('omaly wrapped'),
          ),
          body: WrappedScreen(api: _api),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder(String name) {
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Navigation button colors (from sidebar): dark bg with white text.
    const navBg = Color(0xFF1E1F24);
    const navTextDim = Colors.white70;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'omaly wrapped',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 24),
            // Wrapped card
            SizedBox(
              width: 520,
              child: Material(
                color: navBg,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openWrapped(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 52),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Your omaly wrapped is ready',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Relive your year in photos, places, and memories.',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: navTextDim,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Material(
                            color: const Color(0xFFDCE4F7),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: () => _openWrapped(context),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 16,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'see my wrapped',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      color: Colors.black87,
                                      size: 18,
                                    ),
                                  ],
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
            ),
            const SizedBox(height: 36),
            Row(
              children: [
                Text(
                  'People',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                if (!_loading && _people.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1F24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_people.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 172,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Could not load people.\n$_error',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const SizedBox(width: 16),
                              FilledButton(
                                onPressed: _load,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        )
                      : _people.isEmpty
                          ? Center(
                              child: Text(
                                'No face clusters detected yet.',
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
                              separatorBuilder: (_, _) => const SizedBox(width: 24),
                              itemBuilder: (context, i) {
                                final person = _people[i];
                                final thumbUri = person.thumbnailUrl != null
                                    ? Uri.parse('$kApiBaseUrl${person.thumbnailUrl}')
                                    : null;
                                return InkWell(
                                  onTap: () => _openPersonDetail(person),
                                  borderRadius: BorderRadius.circular(16),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 96,
                                          height: 96,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF1E1F24),
                                            border: Border.all(
                                              color: Colors.white24,
                                              width: 2,
                                            ),
                                          ),
                                          child: ClipOval(
                                            child: thumbUri != null
                                                ? Image.network(
                                                    thumbUri.toString(),
                                                    width: 96,
                                                    height: 96,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, _, _) =>
                                                        _avatarPlaceholder(person.name),
                                                  )
                                                : _avatarPlaceholder(person.name),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          width: 104,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  person.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: theme.textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              InkWell(
                                                onTap: () => _renamePerson(person),
                                                borderRadius: BorderRadius.circular(8),
                                                child: const Padding(
                                                  padding: EdgeInsets.all(2),
                                                  child: Icon(
                                                    Icons.edit_outlined,
                                                    size: 13,
                                                    color: Colors.white54,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${person.photoCount} photos',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurface.withValues(
                                              alpha: 0.6,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
            const SizedBox(height: 36),
            Row(
              children: [
                Text(
                  'Bursts & Best Shots',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 12),
                if (!_loading && _bursts.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1F24),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_bursts.length} ${_bursts.length == 1 ? "group" : "groups"}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Near-duplicate bursts automatically ranked by eye openness and face sharpness.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 220,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _bursts.isEmpty
                      ? Center(
                          child: Text(
                            'No burst groups detected yet.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _bursts.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 20),
                          itemBuilder: (context, i) {
                            final burst = _bursts[i];
                            final bestPhoto = burst.bestPhoto;
                            final photoUri = bestPhoto?.url != null
                                ? Uri.parse('$kApiBaseUrl${bestPhoto!.url}')
                                : (bestPhoto?.thumbnailUrl != null
                                    ? Uri.parse('$kApiBaseUrl${bestPhoto!.thumbnailUrl}')
                                    : null);

                            return InkWell(
                              onTap: () => _openBurstDetail(burst),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                width: 220,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1F24),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white12,
                                    width: 1,
                                  ),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          PhotoTile(
                                            photoId: burst.bestPhotoId,
                                            uri: photoUri,
                                            borderRadius: 0,
                                            cacheWidth: 600,
                                          ),
                                          Positioned(
                                            top: 10,
                                            left: 10,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 9,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFDCE4F7),
                                                borderRadius: BorderRadius.circular(8),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Colors.black26,
                                                    blurRadius: 6,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.star_rounded,
                                                    color: Color(0xFF1A1C2E),
                                                    size: 13,
                                                  ),
                                                  SizedBox(width: 4),
                                                  Text(
                                                    'Best Shot',
                                                    style: TextStyle(
                                                      color: Color(0xFF1A1C2E),
                                                      fontWeight: FontWeight.w800,
                                                      fontSize: 10,
                                                      letterSpacing: 0.3,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 10,
                                            right: 10,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.75),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(
                                                    Icons.burst_mode_rounded,
                                                    color: Colors.white70,
                                                    size: 12,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${burst.photoCount} shots',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 10,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Burst ${burst.id}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            bestPhoto?.score != null
                                                ? '${(bestPhoto!.score! * 100).toInt()}% quality score'
                                                : '${burst.photoCount} burst frames',
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.6,
                                              ),
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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

  /// Icon per settings row — the Material equivalents of the Android
  /// drawables each row was specified with (palette_24, fullscreen_24,
  /// settings_24, backup_24, manage_accounts_24, robot_2_24, info_24).
  static const Map<String, IconData> _icons = {
    'Appearance': Icons.palette_outlined,
    'Media Viewer': Icons.fullscreen_rounded,
    'General': Icons.settings_outlined,
    'Backup & restore': Icons.backup_outlined,
    'Manage Local Models': Icons.manage_accounts_outlined,
    'Smart Features': Icons.smart_toy_outlined,
    'About': Icons.info_outline_rounded,
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
                  icon: _icons[_items[i]],
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
    this.icon,
    this.radius = BorderRadius.zero,
  });

  final String label;
  final String body;

  /// Icon shown inside the leading circle.
  final IconData? icon;

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
          height: 125,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: Row(
              children: [
                // Circle on the left of the title and body. Light mode uses the
                // light brand colour, dark mode keeps the near-black one.
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF17181E)
                        : const Color(0xFFF9F8FE),
                    shape: BoxShape.circle,
                  ),
                  child: icon == null
                      ? null
                      : Icon(
                          icon,
                          size: 28,
                          // Glyph contrast follows the circle it sits on.
                          color: isDark ? Colors.white70 : textColor,
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
                          fontSize: 17,
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
                          fontSize: 14,
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
