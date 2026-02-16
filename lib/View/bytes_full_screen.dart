import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../Model/byte.dart';
import '../ViewModel/user_feed_provider.dart';
import '../ViewModel/auth_provider.dart';
import '../ViewModel/byte_provider.dart';
import 'widgets/double_tap_like.dart';
import 'widgets/byte_comments.dart';
import 'widgets/content_actions.dart';
import 'byte_page.dart';
import 'widgets/follow_button.dart';
import 'byte_rating_dialogs.dart';

class BytesFullScreen extends ConsumerStatefulWidget {
  final List<Byte> bytes;
  final int initialIndex;

  const BytesFullScreen({
    Key? key,
    required this.bytes,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  ConsumerState<BytesFullScreen> createState() => _BytesFullScreenState();
}

class _BytesFullScreenState extends ConsumerState<BytesFullScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
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
      debugPrint('🎥 Creating controller for index $index: $videoUrl');

      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));

      _controllers[index] = controller;

      controller.initialize().then((_) {
        if (!mounted) return;

        debugPrint('✅ Video initialized for index $index');
        setState(() {});

        if (index == _currentIndex) {
          controller.play();
          controller.setLooping(true);
        }
      }).catchError((error) {
        debugPrint('❌ Error initializing video: $error');
      });
    }
    return _controllers[index]!;
  }

  void _onPageChanged(int index) {
    debugPrint('🔄 Page changed from $_currentIndex to $index');

    // Pause and reset previous video
    if (_controllers.containsKey(_currentIndex)) {
      final prevController = _controllers[_currentIndex]!;
      if (prevController.value.isInitialized) {
        prevController.pause();
        prevController.seekTo(Duration.zero);
        debugPrint('⏸️ Paused video at index $_currentIndex');
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
        debugPrint('▶️ Playing video at index $index');
      } else {
        debugPrint('⏳ Video at index $index not yet initialized');
      }
    } else {
      debugPrint('❓ No controller found for index $index');
    }
  }

  void _togglePlayPause(int index) {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      setState(() {
        if (controller.value.isPlaying) {
          controller.pause();
          debugPrint('⏸️ Manually paused video at index $index');
        } else {
          controller.play();
          debugPrint('▶️ Manually playing video at index $index');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: widget.bytes.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              color: Colors.grey[600],
              size: 80,
            ),
            const SizedBox(height: 24),
            Text(
              'No bytes yet',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      )
          : Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: widget.bytes.length,
            itemBuilder: (context, index) {
              final byte = widget.bytes[index];
              debugPrint('🏗️ Building page for index $index: ${byte.byteId}');

              return ByteVideoPlayer(
                byte: byte,
                controller: _getController(index, byte.videoUrl),
                isCurrentVideo: index == _currentIndex,
                onTogglePlayPause: () => _togglePlayPause(index),
                onLike: () async {
                  await ref.read(profileFeedProvider.notifier).toggleByteLike(byte.byteId);
                },
                onSwipeLeft: () => _showCommentsModal(byte),
                onShare: () => _showShareModal(byte),
                showSwipeIndicator: true,
              );
            },
          ),
          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentsModal(Byte byte) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ByteCommentsBottomSheet(byteId: byte.byteId),
    );
  }

  void _showShareModal(Byte byte) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ShareModal(byte: byte),
    );
  }
}

class ByteVideoPlayer extends ConsumerStatefulWidget {
  final Byte byte;
  final VideoPlayerController controller;
  final bool isCurrentVideo;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onLike;
  final VoidCallback onSwipeLeft;
  final VoidCallback onShare;
  final bool showSwipeIndicator;

  const ByteVideoPlayer({
    Key? key,
    required this.byte,
    required this.controller,
    required this.isCurrentVideo,
    required this.onTogglePlayPause,
    required this.onLike,
    required this.onSwipeLeft,
    required this.onShare,
    this.showSwipeIndicator = true,
  }) : super(key: key);

  @override
  ConsumerState<ByteVideoPlayer> createState() => _ByteVideoPlayerState();
}


class _ByteVideoPlayerState extends ConsumerState<ByteVideoPlayer> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final feedState = ref.watch(profileFeedProvider);

    final currentByte = feedState.bytes.firstWhere(
          (b) => b.byteId == widget.byte.byteId,
      orElse: () => widget.byte,
    );

    debugPrint('🎬 Building ByteVideoPlayer for ${currentByte.byteId} - '
        'Initialized: ${widget.controller.value.isInitialized}, '
        'Playing: ${widget.controller.value.isPlaying}');

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
          widget.onSwipeLeft();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video + double-tap like (fully preserved) ──────────────────────
          ByteDoubleTapLike(
            byteId: currentByte.byteId,
            isliked: currentByte.isliked ?? false,
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
                  : const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Loading video…',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),

          // ── Play/pause overlay ─────────────────────────────────────────────
          if (widget.controller.value.isInitialized &&
              !widget.controller.value.isPlaying)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withOpacity(0.3), width: 1.5),
                  ),
                  child: const Icon(Icons.play_arrow_rounded,
                      color: Colors.white, size: 44),
                ),
              ),
            ),

          // ── Deep bottom gradient ───────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 280,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x44000000),
                      Color(0xCC000000),
                      Colors.black,
                    ],
                    stops: [0.0, 0.35, 0.72, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Right-side vertical action column ─────────────────────────────
          Positioned(
            right: 12,
            bottom: 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Like (tap shortcut — double-tap on video still works)
                GestureDetector(
                  onTap: widget.onLike,
                  child: _SideActionItem(
                    icon: currentByte.isliked == true
                        ? Icons.favorite_rounded
                        : Icons.favorite_outline_rounded,
                    iconColor: currentByte.isliked == true
                        ? Colors.redAccent
                        : Colors.white,
                    label: _formatCount(currentByte.likeCount),
                  ),
                ),
                const SizedBox(height: 20),

                // Star rating → insights dialog
                ByteStarRatingIcon(byteId: currentByte.byteId),
                const SizedBox(height: 20),

                // People → ranked-by dialog
                ByteRankedByIcon(byteId: currentByte.byteId),
                const SizedBox(height: 20),

                // Share
                GestureDetector(
                  onTap: widget.onShare,
                  child: const _SideActionItem(
                    icon: Icons.reply_rounded,
                    iconColor: Colors.white70,
                    label: '',
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom info row ────────────────────────────────────────────────
          Positioned(
            bottom: 12,
            left: 12,
            right: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Avatar with gradient ring
                    Container(
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.all(2),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.grey.shade800,
                        backgroundImage: currentByte.profilePic != null
                            ? CachedNetworkImageProvider(currentByte.profilePic!)
                            : null,
                        child: currentByte.profilePic == null
                            ? Text(
                          (currentByte.username?.isNotEmpty ?? false)
                              ? currentByte.username!
                              .substring(0, 1)
                              .toUpperCase()
                              : 'U',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '@${currentByte.username ?? "unknown"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (authState.value?.user != null &&
                        authState.value!.user.id != currentByte.userId)
                      FollowButton(targetUserId: currentByte.userId, compact: true),
                    const SizedBox(width: 4),
                    if (authState.value?.user != null)
                      ContentActionMenu(
                        data: ContentActionData(
                          contentId: currentByte.byteId,
                          userId: currentByte.userId,
                          contentType: ContentType.byte,
                          isHidden: false,
                          shareText: currentByte.caption,
                          shareUrl: 'https://yourapp.com/byte/${currentByte.byteId}',
                        ),
                        callbacks: ContentActionCallbacks(
                          onEdit: authState.value!.user.id == currentByte.userId
                              ? () => _handleEdit(context, ref, currentByte) : null,
                          onDelete: authState.value!.user.id == currentByte.userId
                              ? () => _handleDelete(context, ref, currentByte) : null,
                          onToggleHide: authState.value!.user.id == currentByte.userId
                              ? () => _handleToggleHide(context, ref, currentByte) : null,
                          onShare: () => _handleShare(context, currentByte),
                        ),
                        currentUserId: authState.value!.user.id,
                      ),
                  ],
                ),

                // Caption
                if (currentByte.caption != null && currentByte.caption!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      currentByte.caption!,
                      style: const TextStyle(
                        color: Colors.white, fontSize: 13, height: 1.4,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                // Progress bar
                if (widget.controller.value.isInitialized)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: VideoProgressIndicator(
                        widget.controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white30,
                          backgroundColor: Colors.white12,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Swipe-left comment hint (refined) ─────────────────────────────
          if (widget.showSwipeIndicator)
            Positioned(
              left: 12,
              bottom: MediaQuery.of(context).size.height * 0.42,
              child: Opacity(
                opacity: 0.75,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 18),
                    const SizedBox(width: 2),
                    const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      _formatCount(currentByte.commentCount),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleEdit(BuildContext context, WidgetRef ref, Byte byte) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ByteCreateScreen(),
        // TODO: Pass byte data to edit mode when edit functionality is implemented
      ),
    );
  }

  void _handleDelete(BuildContext context, WidgetRef ref, Byte byte) async {
    final success = await ref.read(byteCreateProvider.notifier).deleteByte(byte.byteId);
    if (context.mounted) {
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Byte deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh feed
        ref.read(bytesFeedProvider.notifier).refreshBytes();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete byte'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleToggleHide(BuildContext context, WidgetRef ref, Byte byte) {
    // TODO: Implement hide/unhide functionality
    // This requires adding is_hidden field to bytes table and updating providers
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hide functionality coming soon'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _handleShare(BuildContext context, Byte byte) {
    // Share functionality - uses default from ContentActionMenu (copy link)
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


// ── Reusable right-side action column item ────────────────────────────────────
class _SideActionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _SideActionItem({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          )),
        ],
      ],
    );
  }
}

class ShareModal extends StatelessWidget {
  final Byte byte;

  const ShareModal({Key? key, required this.byte}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'Share',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: const Icon(Icons.link, color: Colors.white),
            title: const Text('Copy Link', style: TextStyle(color: Colors.white)),
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
            leading: const Icon(Icons.message, color: Colors.white),
            title: const Text('Share via Message', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.more_horiz, color: Colors.white),
            title: const Text('More Options', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class MoreOptionsModal extends StatelessWidget {
  final Byte byte;

  const MoreOptionsModal({Key? key, required this.byte}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text(
            'More Options',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.bookmark_outline, color: Colors.white),
            title: const Text('Save', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.report_outlined, color: Colors.red),
            title: const Text('Report', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.orange),
            title: const Text('Block User', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}