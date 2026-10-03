import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/wrapped.dart';
import '../widgets/status_view.dart';
import 'wrapped/wrapped_slideshow.dart';

/// Wrapped screen: the 11-slide Spotify-Wrapped-style slideshow recap.
class WrappedScreen extends StatefulWidget {
  const WrappedScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<WrappedScreen> createState() => _WrappedScreenState();
}

enum _Phase { loading, ready, error }

class _WrappedScreenState extends State<WrappedScreen> {
  _Phase _phase = _Phase.loading;
  WrappedSummary? _summary;
  String? _errorMessage;
  String? _detail;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([int? year]) async {
    setState(() {
      _phase = _Phase.loading;
      _errorMessage = null;
      _detail = null;
    });
    try {
      final summary = await widget.api.wrapped(year);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _phase = _Phase.ready;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message.split('\n').first;
        _detail = e.message.contains('\n') ? e.message : null;
        _phase = _Phase.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not build your recap.';
        _detail = '$e';
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.loading:
        return const Scaffold(
          backgroundColor: Color(0xFF121318),
          body: Center(child: CircularProgressIndicator()),
        );
      case _Phase.error:
        return Scaffold(
          backgroundColor: Color(0xFF121318),
          appBar: AppBar(
            backgroundColor: Color(0xFF121318),
            foregroundColor: Colors.white,
          ),
          body: StatusView.error(
            title: _errorMessage ?? 'Something went wrong',
            message: 'Your recap could not be generated. Nothing left this machine.',
            detail: _detail,
            actionLabel: 'Try again',
            onAction: _load,
          ),
        );
      case _Phase.ready:
        return WrappedSlideshow(
          summary: _summary!,
          api: widget.api,
          onYearChanged: (year) => _load(year),
          onFinished: () => Navigator.of(context).pop(),
        );
    }
  }
}
