import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../models/wrapped.dart';
import 'wrapped_slide_1.dart';
import 'wrapped_slide_2.dart';
import 'wrapped_slide_3.dart';
import 'wrapped_slide_4.dart';
import 'wrapped_slide_5.dart';
import 'wrapped_slide_6.dart';
import 'wrapped_slide_7.dart';
import 'wrapped_slide_8.dart';
import 'wrapped_slide_9.dart';
import 'wrapped_slide_10.dart';
import 'wrapped_slide_11.dart';

class WrappedSlideshow extends StatefulWidget {
  const WrappedSlideshow({
    super.key,
    required this.summary,
    required this.api,
    required this.onFinished,
  });

  final WrappedSummary summary;
  final ApiClient api;
  final VoidCallback onFinished;

  @override
  State<WrappedSlideshow> createState() => _WrappedSlideshowState();
}

class _WrappedSlideshowState extends State<WrappedSlideshow> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  static const int _totalSlides = 11;

  void _nextPage() {
    if (_currentIndex < _totalSlides - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onFinished();
    }
  }

  void _previousPage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const totalPhotos = 986;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.space ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            _nextPage();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _previousPage();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121318),
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              children: [
                WrappedSlide1(onNext: _nextPage),
                WrappedSlide2(onNext: _nextPage),
                WrappedSlide3(onNext: _nextPage),
                WrappedSlide4(
                  onNext: _nextPage,
                  totalPhotos: totalPhotos,
                ),
                WrappedSlide5(onNext: _nextPage),
                WrappedSlide6(onNext: _nextPage),
                WrappedSlide7(onNext: _nextPage),
                WrappedSlide8(onNext: _nextPage),
                WrappedSlide9(onNext: _nextPage),
                WrappedSlide10(
                  onNext: _nextPage,
                  totalPhotos: totalPhotos,
                ),
                WrappedSlide11(onFinish: widget.onFinished),
              ],
            ),
            // Top progress indicators (11 bars)
            Positioned(
              top: 16,
              left: 24,
              right: 24,
              child: SafeArea(
                child: Row(
                  children: [
                    for (int i = 0; i < _totalSlides; i++)
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: i <= _currentIndex
                                ? Colors.white
                                : Colors.white24,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Previous button top left (only if not on first slide)
            if (_currentIndex > 0)
              Positioned(
                top: 28,
                left: 24,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                    onPressed: _previousPage,
                  ),
                ),
              ),
            // Close button top right
            Positioned(
              top: 28,
              right: 24,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  onPressed: widget.onFinished,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
