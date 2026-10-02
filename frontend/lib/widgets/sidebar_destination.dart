import 'package:flutter/material.dart';

/// One sidebar destination. Kept as a const record list so the shell, the
/// sidebar and the tests all agree on the same source of truth.
class SidebarDestination {
  const SidebarDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;

  /// The four top-level pages, in the order they appear in the sidebar.
  static const List<SidebarDestination> all = [
    SidebarDestination(
      label: 'Gallery',
      icon: Icons.image_outlined,
      selectedIcon: Icons.image_rounded,
    ),
    SidebarDestination(
      label: 'Folders',
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder_rounded,
    ),
    SidebarDestination(
      label: 'Collections',
      icon: Icons.photo_library_outlined,
      selectedIcon: Icons.photo_library_rounded,
    ),
    SidebarDestination(
      label: 'Settings',
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
    ),
  ];
}