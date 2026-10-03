import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../models/person.dart';
import '../widgets/photo_tile.dart';
import 'photo_detail_page.dart';

/// Person detail page — shows all photos featuring a specific person cluster,
/// with the ability to rename the person directly from the header.
class PersonDetailPage extends StatefulWidget {
  const PersonDetailPage({
    super.key,
    required this.person,
    this.api,
  });

  final PersonCluster person;
  final ApiClient? api;

  @override
  State<PersonDetailPage> createState() => _PersonDetailPageState();
}

class _PersonDetailPageState extends State<PersonDetailPage> {
  late final ApiClient _api = widget.api ?? createApiClient();
  late PersonCluster _person = widget.person;

  List<Map<String, dynamic>> _photos = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final photos = await _api.getPersonPhotos(_person.id);
      if (!mounted) return;
      setState(() {
        _photos = photos;
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

  Future<void> _renamePerson() async {
    final controller = TextEditingController(text: _person.name);
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

    if (newName != null && newName.isNotEmpty && newName != _person.name) {
      final old = _person;
      setState(() => _person = _person.copyWith(name: newName));
      try {
        final updated = await _api.renamePerson(_person.id, newName);
        if (!mounted) return;
        setState(() => _person = _person.copyWith(
              name: updated.name,
              photoCount: updated.photoCount,
              coverPhotoId: updated.coverPhotoId ?? _person.coverPhotoId,
              thumbnailUrl: updated.thumbnailUrl ?? _person.thumbnailUrl,
            ));
      } catch (e) {
        if (!mounted) return;
        setState(() => _person = old);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbUri = _person.thumbnailUrl != null
        ? Uri.parse('$kApiBaseUrl${_person.thumbnailUrl}')
        : null;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        // Return updated person to caller
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(_person),
          ),
          title: Text(
            _person.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          actions: [
            TextButton.icon(
              onPressed: _renamePerson,
              icon: const Icon(Icons.edit_rounded, size: 18),
              label: const Text('Rename'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card with person avatar and details
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E1F24),
                      border: Border.all(color: Colors.white24, width: 2),
                    ),
                    child: ClipOval(
                      child: thumbUri != null
                          ? Image.network(
                              thumbUri.toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => _avatarFallback(),
                            )
                          : _avatarFallback(),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _person.name,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: 'Rename person',
                              onPressed: _renamePerson,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        Text(
                          '${_photos.isNotEmpty ? _photos.length : _person.photoCount} photos',
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
            const Divider(height: 1),
            // Photos grid
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Could not load photos.\n$_error',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _loadPhotos,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        )
                      : _photos.isEmpty
                          ? Center(
                              child: Text(
                                'No photos found for ${_person.name}.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            )
                          : GridView.builder(
                              padding: const EdgeInsets.all(24),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 220,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: _photos.length,
                              itemBuilder: (context, index) {
                                final photo = _photos[index];
                                final photoId = photo['id'] as String;
                                final imgUrl = photo['url'] != null
                                    ? Uri.parse('$kApiBaseUrl${photo['url']}')
                                    : null;
                                final thumbUri = photo['thumbnail_url'] != null
                                    ? Uri.parse('$kApiBaseUrl${photo['thumbnail_url']}')
                                    : null;

                                return GestureDetector(
                                  onTap: () {
                                    PhotoDetailPage.open(
                                      context,
                                      photoId: photoId,
                                      api: _api,
                                      imageUrl: imgUrl,
                                    );
                                  },
                                  child: PhotoTile(
                                    photoId: photoId,
                                    uri: thumbUri ?? imgUrl,
                                    borderRadius: 12,
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

  Widget _avatarFallback() {
    final initial = _person.name.trim().isNotEmpty
        ? _person.name.trim()[0].toUpperCase()
        : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 28,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
