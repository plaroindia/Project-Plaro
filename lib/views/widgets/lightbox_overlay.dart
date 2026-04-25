import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../Viewmodels/lightbox_provider.dart';
import '../../models/post.dart';
import '../../models/byte.dart';
import 'Post_card.dart';
import '../../Viewmodels/auth_provider.dart';
import 'double_tap_like.dart';
import 'byte_comments.dart';
import 'follow_button.dart';

class LightboxOverlay extends ConsumerStatefulWidget {
  const LightboxOverlay({super.key});

  @override
  ConsumerState<LightboxOverlay> createState() => _LightboxOverlayState();
}

class _LightboxOverlayState extends ConsumerState<LightboxOverlay> {
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _controllers = {};

  @override
  void initState() {
    super.initState();
    final state = ref.read(lightboxProvider);
    _currentIndex = state.initialIndex;
    _pageController = PageController(initialPage: state.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeAllControllers();
    super.dispose();
  }

  void _disposeAllControllers() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  VideoPlayerController _getController(int index, String videoUrl) {
    if (!_controllers.containsKey(index)) {
      debugPrint('🎥 [Lightbox] Creating controller for index $index: $videoUrl');

      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));

      _controllers[index] = controller;

      controller.initialize().then((_) {
        if (!mounted) return;

        debugPrint('✅ [Lightbox] Video initialized for index $index');
        setState(() {});

        if (index == _currentIndex) {
          controller.play();
          controller.setLooping(true);
        }
      }).catchError((error) {
        debugPrint('❌ [Lightbox] Error initializing video: $error');
      });
    }
    return _controllers[index]!;
  }

  void _onPageChanged(int index) {
    debugPrint('🔄 [Lightbox] Page changed from $_currentIndex to $index');

    // Pause and reset previous video
    if (_controllers.containsKey(_currentIndex)) {
      final prevController = _controllers[_currentIndex]!;
      if (prevController.value.isInitialized) {
        prevController.pause();
        prevController.seekTo(Duration.zero);
        debugPrint('⏸️ [Lightbox] Paused video at index $_currentIndex');
      }
    }

    setState(() {
      _currentIndex = index;
    });

    // Play new video if initialized
    if (_controllers.containsKey(index)) {
      final newController = _controllers[index]!;
      if (newController.value.isInitialized) {
        newController.seekTo(Duration.zero);
        newController.play();
        newController.setLooping(true);
        debugPrint('▶️ [Lightbox] Playing video at index $index');
      } else {
        debugPrint('⏳ [Lightbox] Video at index $index not yet initialized');
      }
    } else {
      debugPrint('❓ [Lightbox] No controller found for index $index');
    }
  }

  void _togglePlayPause(int index) {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      setState(() {
        if (controller.value.isPlaying) {
          controller.pause();
          debugPrint('⏸️ [Lightbox] Manually paused video at index $index');
        } else {
          controller.play();
          debugPrint('▶️ [Lightbox] Manually playing video at index $index');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lightboxProvider);
    if (!state.isOpen) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () {
            ref.read(lightboxProvider.notifier).close();
          },
        ),
        title: Text(
          '${_currentIndex + 1}/${state.items.length}',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: state.items.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final item = state.items[index];
          debugPrint('🏗️ [Lightbox] Building page for index $index: ${item.type}');

          switch (item.type) {
            case LightboxType.post:
              final post = item.data as Post_feed;
              return SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: PostCard(post: post, onTap: () {}, onUserInfo: () {}),
                ),
              );
            case LightboxType.byte:
              final byte = item.data as Byte;
              return _LightboxBytePlayer(
                byte: byte,
                controller: _getController(index, byte.videoUrl),
                isCurrentVideo: index == _currentIndex,
                onTogglePlayPause: () => _togglePlayPause(index),
                onLike: () {
                  // Handle like action - you might want to connect this to your provider
                  debugPrint('❤️ [Lightbox] Like byte: ${byte.byteId}');
                },
                onSwipeLeft: () => _showCommentsModal(context, byte),
                onShare: () => _showShareModal(context, byte),
              );
          }
        },
      ),
    );
  }

  void _showCommentsModal(BuildContext context, Byte byte) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ByteCommentsBottomSheet(byteId: byte.byteId),
    );
  }

  void _showShareModal(BuildContext context, Byte byte) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _ShareModal(byte: byte),
    );
  }
}

class _LightboxBytePlayer extends ConsumerStatefulWidget {
  final Byte byte;
  final VideoPlayerController controller;
  final bool isCurrentVideo;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onLike;
  final VoidCallback onSwipeLeft;
  final VoidCallback onShare;

  const _LightboxBytePlayer({
    required this.byte,
    required this.controller,
    required this.isCurrentVideo,
    required this.onTogglePlayPause,
    required this.onLike,
    required this.onSwipeLeft,
    required this.onShare,
  });

  @override
  ConsumerState<_LightboxBytePlayer> createState() => _LightboxBytePlayerState();
}

class _LightboxBytePlayerState extends ConsumerState<_LightboxBytePlayer> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    debugPrint('🎬 [Lightbox] Building _LightboxBytePlayer for ${widget.byte.byteId} - '
        'Initialized: ${widget.controller.value.isInitialized}, '
        'Playing: ${widget.controller.value.isPlaying}');

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe left to show comments
        if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
          widget.onSwipeLeft();
        }
      },
      onTap: widget.onTogglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player with double tap like functionality
          ByteDoubleTapLike(
            byteId: widget.byte.byteId,
            isliked: widget.byte.isliked ?? false,
            onSingleTap: widget.onTogglePlayPause,
            onDoubleTapLike: widget.onLike,
            child: Container(
              color: Colors.black,
              child: widget.controller.value.isInitialized
                  ? Center(
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              )
                  : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Loading video...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Play/pause overlay
          if (widget.controller.value.isInitialized && !widget.controller.value.isPlaying)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
            ),

          // Bottom gradient
          IgnorePointer(
            child: Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black54,
                      Colors.black87,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom content area
          Positioned(
            bottom: 3,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profile row with follow, like, share, more buttons
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.grey[600],
                      backgroundImage: widget.byte.profilePic != null
                          ? CachedNetworkImageProvider(widget.byte.profilePic!)
                          : null,
                      child: widget.byte.profilePic == null
                          ? Text(
                        (widget.byte.username?.isNotEmpty ?? false)
                            ? widget.byte.username!.substring(0, 1).toUpperCase()
                            : 'U',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      )
                          : null,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '@${widget.byte.username ?? "unknown"}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 8),

                    // Follow button (if not own profile)
                    if (authState.value?.user != null && authState.value!.user.id != widget.byte.userId)
                      FollowButton(
                        targetUserId: widget.byte.userId,
                        compact: true,
                      ),

                    SizedBox(width: 10),

                    // Like icon with count
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.byte.isliked == true ? Icons.favorite : Icons.favorite_border,
                          color: widget.byte.isliked == true ? Colors.red : Colors.white,
                          size: 22,
                        ),
                        SizedBox(width: 4),
                        Text(
                          _formatCount(widget.byte.likeCount),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(width: 10),

                    // Share button
                    GestureDetector(
                      onTap: widget.onShare,
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.share,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),

                    SizedBox(width: 10),

                    // More options button
                    GestureDetector(
                      onTap: () => _showMoreOptions(context, widget.byte),
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.more_vert,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),

                // Caption
                if (widget.byte.caption != null && widget.byte.caption!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      widget.byte.caption!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.3,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                // Video progress indicator
                if (widget.controller.value.isInitialized)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: VideoProgressIndicator(
                      widget.controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        bufferedColor: Colors.grey,
                        backgroundColor: Colors.white24,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
          ),

          // Swipe left indicator
          Positioned(
            right: 20,
            bottom: MediaQuery.of(context).size.height / 2 - 40,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.keyboard_arrow_left,
                    color: Colors.white70,
                    size: 20,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Swipe left for comments (${widget.byte.commentCount})',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context, Byte byte) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _MoreOptionsModal(byte: byte),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

class _ShareModal extends StatelessWidget {
  final Byte byte;

  const _ShareModal({required this.byte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'Share',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 24),
          ListTile(
            leading: Icon(Icons.link, color: Colors.white),
            title: Text('Copy Link', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard!'),
                  backgroundColor: Colors.blue,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.message, color: Colors.white),
            title: Text('Share via Message', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.more_horiz, color: Colors.white),
            title: Text('More Options', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _MoreOptionsModal extends StatelessWidget {
  final Byte byte;

  const _MoreOptionsModal({required this.byte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'More Options',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.bookmark_outline, color: Colors.white),
            title: Text('Save', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.report_outlined, color: Colors.red),
            title: Text('Report', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.block, color: Colors.orange),
            title: Text('Block User', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}