import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'pages/pages.dart';
import 'theme/palette.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/sidebar_destination.dart';

final String? _kFontFamily = GoogleFonts.googleSansFlex().fontFamily;

void main() {
  runApp(const OmalyApp());
}

ThemeData omalyTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6C5CE7),
    brightness: brightness,
  );
  final surface = isDark ? kContentColorDark : kContentColor;

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: surface,
    canvasColor: surface,
    fontFamily: _kFontFamily,
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

class OmalyApp extends StatefulWidget {
  const OmalyApp({super.key});

  @override
  State<OmalyApp> createState() => _OmalyAppState();
}

class _OmalyAppState extends State<OmalyApp> {
  ThemeMode _themeMode = ThemeMode.light;

  bool get _isDark => _themeMode == ThemeMode.dark;

  void _toggleTheme() => setState(
        () => _themeMode = _isDark ? ThemeMode.light : ThemeMode.dark,
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'omaly',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: omalyTheme(Brightness.light),
      darkTheme: omalyTheme(Brightness.dark),
      home: HomeShell(isDark: _isDark, onToggleTheme: _toggleTheme),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return Scaffold(
            backgroundColor: kChromeColor,
            body: Row(
              children: [
                Theme(
                  data: omalyTheme(Brightness.dark),
                  child: AppSidebar(
                    selectedIndex: _index,
                    onSelected: (i) => setState(() => _index = i),
                    isDark: widget.isDark,
                    onToggleTheme: widget.onToggleTheme,
                  ),
                ),
                Expanded(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(8),
                        ),
                        child: IndexedStack(
                          index: _index,
                          children: const [
                            GalleryPage(),
                            FoldersPage(),
                            CollectionsPage(),
                            SettingsPage(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        } else {
          return Scaffold(
            backgroundColor: kChromeColor,
            appBar: AppBar(
              backgroundColor: kChromeColor,
              foregroundColor: Colors.white,
              title: const Text('omaly'),
              actions: [
                IconButton(
                  icon: Icon(
                    widget.isDark
                        ? Icons.light_mode_rounded
                        : Icons.dark_mode_rounded,
                  ),
                  onPressed: widget.onToggleTheme,
                ),
              ],
            ),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: IndexedStack(
                    index: _index,
                    children: const [
                      GalleryPage(),
                      FoldersPage(),
                      CollectionsPage(),
                      SettingsPage(),
                    ],
                  ),
                ),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in SidebarDestination.all)
                  NavigationDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: d.label,
                  ),
              ],
            ),
          );
        }
      },
    );
  }
}
