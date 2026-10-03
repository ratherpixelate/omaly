import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// In-app video player (libmpv backend via media_kit — same ffmpeg decoding
/// power as VLC, no external player needed).
///
/// Opens [uri] on mount, autoplays, and releases the player on dispose, so
/// each focus-view opening gets a fresh player and nothing leaks when it
/// closes.
///
/// Controls: mpv's own on-screen controller (osc) is enabled and is the single
/// control surface. We deliberately do not overlay a Flutter transport bar —
/// stacking both made the mpv bar and our seekbar overlap, and mpv's bar
/// swallowed clicks meant for ours.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key, required this.uri});

  final Uri uri;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    // osc: true — use mpv's built-in on-screen controller as the only controls.
    _player = Player(configuration: const PlayerConfiguration(osc: true));
    _controller = VideoController(_player);
    _player.open(Media(widget.uri.toString()), play: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Video(controller: _controller, fit: BoxFit.contain);
  }
}
