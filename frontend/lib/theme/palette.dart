import 'package:flutter/material.dart';

/// Chrome colour: the sidebar rail and app frame.
///
/// Fixed regardless of theme. The dark rail is part of omaly's identity rather
/// than a theme preference, so it does not flip with the theme toggle.
const Color kChromeColor = Color(0xFF121318);

/// Content surface in light mode — the near-white panel photos sit on.
const Color kContentColor = Color(0xFFF9F8FE);

/// Content surface in dark mode.
///
/// Deliberately a shade lighter than [kChromeColor]: the divider that used to
/// separate the sidebar from the content area is gone, so the two surfaces need
/// to stay distinguishable by value alone.
const Color kContentColorDark = Color(0xFF17181E);
