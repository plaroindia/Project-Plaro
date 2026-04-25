import 'package:flutter/material.dart';

/// Instagram-style pinch-to-zoom widget (no double-tap to avoid conflicts with like feature)
class ZoomableImage extends StatefulWidget {
  final Widget child;
  final double minScale;
  final double maxScale;
  final Duration resetDuration;
  final Curve resetCurve;
  final VoidCallback? onZoomStart;
  final VoidCallback? onZoomEnd;

  const ZoomableImage({
    super.key,
    required this.child,
    this.minScale = 1.0,
    this.maxScale = 3.0,
    this.resetDuration = const Duration(milliseconds: 250),
    this.resetCurve = Curves.easeOutCubic,
    this.onZoomStart,
    this.onZoomEnd,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage>
    with SingleTickerProviderStateMixin {
  late final TransformationController _controller;
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;

  // Track zoom state
  bool _isZoomed = false;
  bool _isInteracting = false;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.resetDuration,
    );

    _animationController.addListener(() {
      if (_animation != null) {
        _controller.value = _animation!.value;
      }
    });

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _isZoomed = false;
        widget.onZoomEnd?.call();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Get current scale from transformation matrix
  double get _currentScale {
    final matrix = _controller.value;
    return matrix.getMaxScaleOnAxis();
  }

  /// Check if currently zoomed in
  bool get _isSignificantlyZoomed {
    return (_currentScale - widget.minScale).abs() > 0.01;
  }

  /// Animate to a specific transformation matrix
  void _animateToMatrix(Matrix4 targetMatrix) {
    _animation = Matrix4Tween(
      begin: _controller.value,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: widget.resetCurve,
      ),
    );

    _animationController
      ..reset()
      ..forward();
  }

  /// Reset zoom with smooth animation
  void _resetZoom() {
    if (!_isSignificantlyZoomed) return;
    _animateToMatrix(Matrix4.identity());
  }

  /// Handle interaction start (pinch/pan)
  void _handleInteractionStart(ScaleStartDetails details) {
    _isInteracting = true;
    if (!_isZoomed) {
      _isZoomed = true;
      widget.onZoomStart?.call();
    }
  }

  /// Handle interaction update
  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    // Prevent over-zooming
    final currentScale = _currentScale;
    if (currentScale >= widget.maxScale && details.scale > 1.0) {
      return;
    }
    if (currentScale <= widget.minScale && details.scale < 1.0) {
      return;
    }
  }

  /// Handle interaction end - reset if zoomed out past threshold
  void _handleInteractionEnd(ScaleEndDetails details) {
    _isInteracting = false;

    // Auto-reset if zoomed out below minimum or way above maximum
    if (_currentScale < widget.minScale * 0.9) {
      _resetZoom();
    } else if (_currentScale > widget.maxScale * 1.1) {
      // Clamp to max scale
      final currentMatrix = _controller.value;
      final clampedMatrix = Matrix4.identity()
        ..setFrom(currentMatrix)
        ..scale(widget.maxScale / _currentScale);
      _animateToMatrix(clampedMatrix);
    } else if (!_isSignificantlyZoomed) {
      // If very close to 1x, snap back
      _resetZoom();
    }

    // Check if user "flung" the zoom - if so, animate back smoothly
    final velocity = details.velocity.pixelsPerSecond.distance;
    if (velocity > 500 && _isSignificantlyZoomed) {
      // High velocity fling - reset zoom
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isInteracting) {
          _resetZoom();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: widget.minScale * 0.8, // Allow slight under-zoom for snap-back effect
      maxScale: widget.maxScale * 1.2, // Allow slight over-zoom for snap-back effect
      panEnabled: true,
      scaleEnabled: true,
      clipBehavior: Clip.none,
      boundaryMargin: EdgeInsets.all(0),

      onInteractionStart: _handleInteractionStart,
      onInteractionUpdate: _handleInteractionUpdate,
      onInteractionEnd: _handleInteractionEnd,

      child: widget.child,
    );
  }
}

/// Example usage with cached network image
class InstagramZoomableNetworkImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const InstagramZoomableNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.contain,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    return ZoomableImage(
      child: Image.network(
        imageUrl,
        fit: fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder ??
              Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                      : null,
                ),
              );
        },
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ??
              Center(
                child: Icon(Icons.error_outline, color: Colors.red, size: 48),
              );
        },
      ),
    );
  }
}