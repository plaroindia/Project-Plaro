import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../models/byte.dart';
import '../../views/widgets/double_tap_like.dart';

/// Shared video player widget for Byte videos
/// Used across ByteViewerPage, BytesFullScreen, and LightboxOverlay
class ByteVideoPlayerWidget extends StatelessWidget {
  final Byte byte;
  final VideoPlayerController controller;
  final bool isCurrentVideo;
  final VoidCallback onTogglePlayPause;
  final VoidCallback? onLike;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onShare;
  final bool showControls;

  const ByteVideoPlayerWidget({
    super.key,
    required this.byte,
    required this.controller,
    required this.isCurrentVideo,
    required this.onTogglePlayPause,
    this.onLike,
    this.onSwipeLeft,
    this.onShare,
    this.showControls = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        // Swipe left to show comments
        if (details.primaryVelocity != null &&
            details.primaryVelocity! < -500 &&
            onSwipeLeft != null) {
          onSwipeLeft!();
        }
      },
      onTap: onTogglePlayPause,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video player with double tap like functionality
          if (onLike != null)
            ByteDoubleTapLike(
              byteId: byte.byteId,
              isliked: byte.isliked ?? false,
              onSingleTap: onTogglePlayPause,
              onDoubleTapLike: onLike!,
              child: _buildVideoContent(),
            )
          else
            _buildVideoContent(),

          // Play/pause overlay
          if (controller.value.isInitialized &&
              !controller.value.isPlaying &&
              showControls)
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

          // Video info overlay (bottom)
          if (showControls && isCurrentVideo) _buildInfoOverlay(context),
        ],
      ),
    );
  }

  Widget _buildVideoContent() {
    return Container(
      color: Colors.black,
      child: controller.value.isInitialized
          ? Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
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
    );
  }

  Widget _buildInfoOverlay(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withOpacity(0.7),
            ],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // User info
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: byte.profilePic != null
                      ? NetworkImage(byte.profilePic!)
                      : null,
                  child: byte.profilePic == null
                      ? Icon(Icons.person, color: Colors.white)
                      : null,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        byte.username ?? 'Unknown',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (byte.caption != null && byte.caption!.isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          byte.caption!,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.favorite,
                  label: _formatCount(byte.likeCount),
                  isActive: byte.isliked ?? false,
                  onTap: onLike,
                ),
                _buildActionButton(
                  icon: Icons.comment,
                  label: _formatCount(byte.commentCount),
                  onTap: onSwipeLeft,
                ),
                _buildActionButton(
                  icon: Icons.share,
                  label: _formatCount(byte.shareCount),
                  onTap: onShare,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(
            icon,
            color: isActive ? Colors.red : Colors.white,
            size: 28,
          ),
          SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? Colors.red : Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
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

