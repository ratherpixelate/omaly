import 'package:flutter/material.dart';

/// Gallery — the default landing page.
///
/// Stub for now: navigation and structure only, no content yet.
class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PageShell(title: 'Gallery');
  }
}

/// Shared frame for the top-level pages. Deliberately empty inside — page
/// content gets built once the real data source for that page is agreed.
class _PageShell extends StatelessWidget {
  const _PageShell({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // scaffoldBackgroundColor, not colorScheme.surface: the content surface
      // is a specified brand colour and M3's surface is only near it.
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    );
  }
}

/// Folders — stub.
class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageShell(title: 'Folders');
}

/// Collections — stub.
class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageShell(title: 'Collections');
}

/// Settings — stub.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const _PageShell(title: 'Settings');
}