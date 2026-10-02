import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/search_result.dart';
import '../widgets/photo_tile.dart';
import '../widgets/status_view.dart';

/// Search screen: query bar + results grid, with loading / empty / error
/// states for every in-flight request.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Phase { idle, loading, results, empty, error }

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  _Phase _phase = _Phase.idle;
  SearchResponse? _response;
  String? _errorMessage;
  String? _detail;
  String _submittedQuery = '';

  /// Monotonic id so a slow earlier response can't overwrite a newer one.
  int _requestId = 0;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit([String? override]) async {
    final query = (override ?? _controller.text).trim();
    if (query.isEmpty) return;

    final id = ++_requestId;
    FocusScope.of(context).unfocus();
    setState(() {
      _submittedQuery = query;
      _phase = _Phase.loading;
      _errorMessage = null;
      _detail = null;
    });

    try {
      final res = await widget.api.search(query);
      if (!mounted || id != _requestId) return; // stale response
      setState(() {
        _response = res;
        _phase = res.results.isEmpty ? _Phase.empty : _Phase.results;
      });
    } on ApiException catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _errorMessage = e.message.split('\n').first;
        _detail = e.message.contains('\n') ? e.message : null;
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _errorMessage = 'Something went wrong.';
        _detail = '$e';
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(
          controller: _controller,
          focusNode: _focusNode,
          onSubmit: _submit,
          busy: _phase == _Phase.loading,
        ),
        const Divider(height: 1),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.idle:
        return StatusView.idle(
          title: 'Search your own photos',
          message:
              'Describe a moment in plain words — "me and Arjun at the beach". '
              'Everything runs on this machine.',
          actionLabel: 'Try "beach"',
          onAction: () => _sample('beach'),
        );
      case _Phase.loading:
        return const LoadingGrid();
      case _Phase.empty:
        return StatusView.empty(
          title: 'No matches for "$_submittedQuery"',
          message: 'Try different words, or something broader.',
          actionLabel: 'Clear search',
          onAction: _clear,
        );
      case _Phase.error:
        return StatusView.error(
          title: _errorMessage ?? 'Something went wrong',
          message:
              'The local backend did not answer. Nothing was uploaded — this '
              'request never left your machine.',
          detail: _detail,
          actionLabel: 'Try again',
          onAction: () => _submit(_submittedQuery),
        );
      case _Phase.results:
        return _ResultsGrid(
          response: _response!,
          api: widget.api,
        );
    }
  }

  void _sample(String query) {
    _controller.text = query;
    _submit(query);
  }

  void _clear() {
    _requestId++;
    _controller.clear();
    setState(() {
      _phase = _Phase.idle;
      _response = null;
      _errorMessage = null;
      _detail = null;
      _submittedQuery = '';
    });
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.busy,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmit;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onSubmitted: onSubmit,
                  textInputAction: TextInputAction.search,
                  style: Theme.of(context).textTheme.titleMedium,
                  decoration: InputDecoration(
                    hintText: 'me and Arjun at the beach',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: value.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Clear',
                            onPressed: () {
                              controller.clear();
                              focusNode.requestFocus();
                            },
                          ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy ? null : () => onSubmit(controller.text),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Search'),
          ),
        ],
      ),
    );
  }
}

class _ResultsGrid extends StatelessWidget {
  const _ResultsGrid({required this.response, required this.api});

  final SearchResponse response;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: Row(
            children: [
              Text(
                '${response.results.length} '
                '${response.results.length == 1 ? 'photo' : 'photos'}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(width: 8),
              // Flexible, so a long query ellipsizes instead of overflowing
              // the header on a narrow desktop window.
              Flexible(
                child: Text(
                  'for "${response.query}"',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Reinforces the pitch on the screen judges are staring at.
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined,
                        size: 14, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'searched on this device',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive columns so the same build looks right on a laptop
              // and on the demo machine's bigger screen.
              final columns =
                  (constraints.maxWidth / 230).floor().clamp(2, 10);
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemCount: response.results.length,
                itemBuilder: (context, i) =>
                    _ResultCard(result: response.results[i], api: api),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.api});

  final SearchResult result;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: PhotoTile(
            photoId: result.id,
            uri: api.thumbnailUri(result.id,
                relativePath: result.thumbnailUrl),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                _formatDate(result.takenAt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 6),
            // Similarity score as a compact chip.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: _scoreColor(context).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${result.scorePercent}%',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: _scoreColor(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Icon(Icons.place_outlined,
                size: 12, color: theme.colorScheme.outline),
            const SizedBox(width: 3),
            Expanded(
              // `location` is nullable in the contract — show a dash rather
              // than an icon for photos with no GPS.
              child: Text(
                result.location == null
                    ? 'No location'
                    : '${result.location!.lat.toStringAsFixed(2)}, '
                        '${result.location!.lon.toStringAsFixed(2)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Green for a confident match, fading to neutral for weak ones. Gives the
  /// grid a readable sense of ranking at a glance.
  Color _scoreColor(BuildContext context) {
    if (result.score >= 0.85) return const Color(0xFF3FB950);
    if (result.score >= 0.7) return const Color(0xFFD29922);
    return Theme.of(context).colorScheme.outline;
  }

  static String _formatDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}