import 'package:flutter/material.dart';

import '../theme/palette.dart';
import 'sidebar_destination.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.isDark,
    required this.onToggleTheme,
    this.items = SidebarDestination.all,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final List<SidebarDestination> items;

  static const double width = 270;
  static const double tileHeight = 76;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: width,
      color: kChromeColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 14),
            child: Text('omaly', style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
              itemCount: items.length,
              itemBuilder: (context, i) => _DestinationCard(
                destination: items[i],
                selected: i == selectedIndex,
                onTap: () => onSelected(i),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: _ThemeToggle(isDark: isDark, onToggle: onToggleTheme),
          ),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final SidebarDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.label,
        child: Material(
          color: selected
              ? const Color(0xFF21232F)
              : const Color(0xFF1E1F24),
          borderRadius: BorderRadius.circular(
            selected ? AppSidebar.tileHeight / 2 : 6,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: Colors.white.withValues(alpha: 0.04),
            splashColor: Colors.white.withValues(alpha: 0.06),
            highlightColor: Colors.white.withValues(alpha: 0.02),
            child: SizedBox(
              height: AppSidebar.tileHeight,
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 10, 20, 10),
                child: Row(
                  children: [
                    Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 24,
                      color: selected ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      destination.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w700,
                        color: selected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.isDark, required this.onToggle});

  final bool isDark;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isDark ? 'Light theme' : 'Dark theme',
      child: Material(
        color: const Color(0xFF1E1F24),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          hoverColor: Colors.white.withValues(alpha: 0.04),
          splashColor: Colors.white.withValues(alpha: 0.06),
          highlightColor: Colors.white.withValues(alpha: 0.02),
          child: SizedBox(
            height: AppSidebar.tileHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 10, 20, 10),
              child: Row(
                children: [
                  Icon(
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    size: 24,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 14),
                  Text(
                    isDark ? 'Light theme' : 'Dark theme',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
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
}
