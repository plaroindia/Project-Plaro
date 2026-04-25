
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../Viewmodels/post_feed_provider.dart';
import '../../Viewmodels/byte_provider.dart';

/// A reusable widget that wraps content with double tap to like functionality
/// Provides visual feedback animation when double tapped
class DoubleTapLike extends StatefulWidget {
  final Widget child;
  final VoidCallback onDoubleTap;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool isliked;
  final Duration animationDuration;
  final double heartSize;
  final Color heartColor;

  const DoubleTapLike({
    super.key,
    required this.child,
    required this.onDoubleTap,
    this.onTap,
    this.isLoading = false,
    this.isliked = false,
    this.animationDuration = const Duration(milliseconds: 600),
    this.heartSize = 80.0,
    this.heartColor = Colors.red,
  });

  @override
  State<DoubleTapLike> createState() => _DoubleTapLikeState();
}

class _DoubleTapLikeState extends State<DoubleTapLike>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (widget.isLoading) return;

    // Only show heart animation if not already liked
    if (!widget.isliked) {
      setState(() {
        _showHeart = true;
      });

      _animationController.forward().then((_) {
        if (mounted) {
          setState(() {
            _showHeart = false;
          });
          _animationController.reset();
        }
      });
    }

    widget.onDoubleTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        children: [
          widget.child,
          if (_showHeart)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Opacity(
                          opacity: _opacityAnimation.value,
                          child: Icon(
                            Icons.favorite,
                            size: widget.heartSize,
                            color: widget.heartColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          if (widget.isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A specialized version for posts with built-in provider integration
class PostDoubleTapLike extends ConsumerWidget {
  final Widget child;
  final String postId;
  final bool isliked;
  final bool isLoading;

  const PostDoubleTapLike({
    super.key,
    required this.child,
    required this.postId,
    this.isliked = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(postFeedProvider);
    final isCurrentlyLoading = feedState.likingPosts.contains(postId);

    return DoubleTapLike(
      onTap: null,
      onDoubleTap: () {
        ref.read(postFeedProvider.notifier).toggleLike(postId);
      },
      isLoading: isCurrentlyLoading,
      isliked: isliked,
      child: child,
    );
  }
}


/// A specialized version for bytes with enhanced gesture handling
class ByteDoubleTapLike extends StatefulWidget {
  final Widget child;
  final String byteId;
  final bool isliked;
  final VoidCallback? onSingleTap;
  final VoidCallback onDoubleTapLike;

  const ByteDoubleTapLike({
    super.key,
    required this.child,
    required this.byteId,
    this.isliked = false,
    this.onSingleTap,
    required this.onDoubleTapLike,
  });

  @override
  State<ByteDoubleTapLike> createState() => _ByteDoubleTapLikeState();
}

class _ByteDoubleTapLikeState extends State<ByteDoubleTapLike>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  bool _showHeart = false;
  int _tapCount = 0;
  Timer? _tapTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
    ));
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    _tapCount++;
    _tapTimer?.cancel();

    _tapTimer = Timer(const Duration(milliseconds: 300), () {
      if (_tapCount == 1) {
        widget.onSingleTap?.call();
      } else if (_tapCount >= 2) {
        _handleDoubleTap();
      }
      _tapCount = 0;
    });
  }

  void _handleDoubleTap() {
    // Only show heart animation if not already liked
    if (!widget.isliked) {
      setState(() {
        _showHeart = true;
      });

      _animationController.forward().then((_) {
        if (mounted) {
          setState(() {
            _showHeart = false;
          });
          _animationController.reset();
        }
      });
    }

    widget.onDoubleTapLike();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _handleTap,
      child: Stack(
        children: [
          widget.child,
          if (_showHeart)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Opacity(
                          opacity: _opacityAnimation.value,
                          child: Icon(
                            Icons.favorite,
                            size: 80,
                            color: Colors.red,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reusable widget for comments on posts, toasts, or bytes
class CommentDoubleTapLike extends ConsumerWidget {
  final Widget child;
  final String commentId;
  final String parentType; // 'post', 'toast', 'byte'
  final bool isliked;
  final bool isLoading;

  const CommentDoubleTapLike({
    super.key,
    required this.child,
    required this.commentId,
    required this.parentType,
    this.isliked = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool currentlyLoading;
    switch (parentType) {
      case 'post':
        final feedState = ref.watch(postFeedProvider);
        currentlyLoading = feedState.likingComments.contains(commentId);
        break;
      case 'byte':
        final feedState = ref.watch(bytesFeedProvider);
        currentlyLoading = feedState.likingComments.contains(commentId);
        break;
      default:
        currentlyLoading = false;
    }

    return DoubleTapLike(
      onDoubleTap: () {
        switch (parentType) {
          case 'post':
            ref.read(postFeedProvider.notifier).toggleCommentLike(int.parse(commentId));
            break;
          case 'byte':
            ref.read(bytesFeedProvider.notifier).toggleCommentLike(commentId);
            break;
        }
      },
      isLoading: currentlyLoading,
      isliked: isliked,
      child: child,
    );
  }
}
