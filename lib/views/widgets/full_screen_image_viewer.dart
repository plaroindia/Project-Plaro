import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Instagram-style full-screen image viewer with pinch-to-zoom
class FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final bool showPageIndicator;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.showPageIndicator = true,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();

  /// Static method to open the viewer (like Instagram)
  static void show(
      BuildContext context, {
        required List<String> imageUrls,
        int initialIndex = 0,
        bool showPageIndicator = true,
      }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: FullScreenImageViewer(
              imageUrls: imageUrls,
              initialIndex: initialIndex,
              showPageIndicator: showPageIndicator,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 250),
      ),
    );
  }
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);

    // UI fade animation controller
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Show UI initially
    _fadeController.forward();

    // Hide system UI for immersive experience
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _toggleUI() {
    setState(() {
      _showUI = !_showUI;
      if (_showUI) {
        _fadeController.forward();
      } else {
        _fadeController.reverse();
      }
    });
  }

  void _onZoomChanged(bool isZoomed) {
    setState(() {
      _isZoomed = isZoomed;
    });
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main PageView with images
          PageView.builder(
            controller: _pageController,
            itemCount: widget.imageUrls.length,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics() // Disable swipe when zoomed
                : const PageScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return _FullScreenImagePage(
                imageUrl: widget.imageUrls[index],
                onZoomChanged: _onZoomChanged,
                onTap: _toggleUI,
              );
            },
          ),

          // Top bar with close button
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 8,
                  right: 8,
                  bottom: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    // Close button
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: _close,
                      padding: EdgeInsets.all(8),
                      splashRadius: 24,
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // Page indicator (if multiple images)
          if (widget.showPageIndicator && widget.imageUrls.length > 1)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.imageUrls.length}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Individual full-screen image page with zoom capability
class _FullScreenImagePage extends StatefulWidget {
  final String imageUrl;
  final ValueChanged<bool>? onZoomChanged;
  final VoidCallback? onTap;

  const _FullScreenImagePage({
    required this.imageUrl,
    this.onZoomChanged,
    this.onTap,
  });

  @override
  State<_FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<_FullScreenImagePage>
    with SingleTickerProviderStateMixin {
  late final TransformationController _transformationController;
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _animationController.addListener(() {
      if (_animation != null) {
        _transformationController.value = _animation!.value;
      }
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  double get _currentScale {
    return _transformationController.value.getMaxScaleOnAxis();
  }

  void _animateResetZoom() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutCubic,
      ),
    );

    _animationController
      ..reset()
      ..forward();
  }

  void _handleInteractionStart(ScaleStartDetails details) {
    if (!_isZoomed && _currentScale > 1.01) {
      setState(() {
        _isZoomed = true;
      });
      widget.onZoomChanged?.call(true);
    }
  }

  void _handleInteractionEnd(ScaleEndDetails details) {
    // Auto-reset if zoomed out below threshold
    if (_currentScale < 0.9) {
      _animateResetZoom();
      setState(() {
        _isZoomed = false;
      });
      widget.onZoomChanged?.call(false);
    } else if (_currentScale <= 1.01) {
      if (_isZoomed) {
        setState(() {
          _isZoomed = false;
        });
        widget.onZoomChanged?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.8,
        maxScale: 4.0,
        panEnabled: true,
        scaleEnabled: true,
        onInteractionStart: _handleInteractionStart,
        onInteractionEnd: _handleInteractionEnd,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: widget.imageUrl,
              fit: BoxFit.contain,
              placeholder: (context, url) => Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              errorWidget: (context, url, error) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.white54,
                      size: 48,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Failed to load image',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
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