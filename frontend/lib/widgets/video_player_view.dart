import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// In-app video player (libmpv backend via media_kit — same ffmpeg decoding
/// power as VLC, no external player needed).
///
/// Opens [uri] on mount, autoplays, and releases the player on dispose, so
/// each focus-view opening gets a fresh player and nothing leaks when it
/// closes.
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
    _player = Player();
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
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(controller: _controller, fit: BoxFit.contain),
        // Minimal transport controls, overlaid at the bottom.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _TransportControls(player: _player),
        ),
      ],
    );
  }
}

/// Play/pause toggle plus a seek bar, rebuilt from the player's streams.
class _TransportControls extends StatelessWidget {
  const _TransportControls({required this.player});

  final Player player;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: true,
            builder: (context, snap) => IconButton(
              tooltip: (snap.data ?? true) ? 'Pause' : 'Play',
              icon: Icon(
                (snap.data ?? true)
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: Colors.white,
              ),
              onPressed: () => player.playOrPause(),
            ),
          ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: player.stream.position,
              initialData: Duration.zero,
              builder: (context, posSnap) => StreamBuilder<Duration>(
                stream: player.stream.duration,
                initialData: Duration.zero,
                builder: (context, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur = durSnap.data ?? Duration.zero;
                  final maxMs = dur.inMilliseconds;
                  return Slider(
                    value: maxMs == 0
                        ? 0
                        : pos.inMilliseconds.clamp(0, maxMs).toDouble(),
                    max: (maxMs == 0 ? 1 : maxMs).toDouble(),
                    onChanged: (v) =>
                        player.seek(Duration(milliseconds: v.toInt())),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
