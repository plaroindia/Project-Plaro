import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import 'dart:io';
import '../../Viewmodels/user_feed_provider.dart';
import '../../Viewmodels/user_provider.dart';
import 'zoomable_image.dart';
import 'full_screen_image_viewer.dart';

class PostProfileCard extends ConsumerWidget {
  final Post_feed post;
  final VoidCallback? onTap;

  const PostProfileCard({
    super.key,
    required this.post,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.3), width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media Section (if exists)
            if (_hasMedia())
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: _buildMediaPreview(context),  // Pass context
                ),
              ),

            // Content Section
            Expanded(
              flex: _hasMedia() ? 2 : 3,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    if (post.title != null && post.title!.isNotEmpty)
                      Text(
                        post.title!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                    if (post.title != null && post.title!.isNotEmpty)
                      SizedBox(height: 6),

                    // Content
                    if (post.content != null && post.content!.isNotEmpty)
                      Expanded(
                        child: Text(
                          post.content!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 12,
                            height: 1.3,
                          ),
                          maxLines: _hasMedia() ? 3 : 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),

                    const Spacer(),

                    // Bottom Stats Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Time
                        Text(
                          _formatTimeAgo(post.created_at),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            fontSize: 10,
                          ),
                        ),

                        // Stats
                        Row(
                          children: [
                            _StatIcon(
                              icon: post.isliked ? Icons.favorite : Icons.favorite_border,
                              count: post.like_count,
                              color: post.isliked ? Colors.red : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            ),
                            SizedBox(width: 8),
                            _StatIcon(
                              icon: Icons.comment_outlined,
                              count: post.comment_count,
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            ),
                          ],
                        ),
                        IconButton(
                          icon:Icon(Icons.more_vert),
                          onPressed: (){
                            _showMoreOptions(context,post);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _hasMedia() {
    return (post.media_urls != null && post.media_urls!.isNotEmpty) ||
        (post.localMediaFiles != null && post.localMediaFiles!.isNotEmpty);
  }

  Widget _buildMediaPreview(BuildContext context) {  // ✅ Add BuildContext parameter
    if (post.localMediaFiles != null && post.localMediaFiles!.isNotEmpty) {
      final file = post.localMediaFiles!.first;
      return _isVideoFile(file.path)
          ? _buildVideoThumbnail(context, File(file.path))
          : GestureDetector(
        onTap: () {
          // For local files - show message or handle differently
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload images to view in full screen'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: ZoomableImage(
          minScale: 1.0,
          maxScale: 4.0,
          child: Image.file(
            File(file.path),
            fit: BoxFit.cover,
            width: double.infinity,
          ),
        ),
      );
    } else if (post.media_urls != null && post.media_urls!.isNotEmpty) {
      final mediaUrl = post.media_urls!.first;
      return Stack(
        children: [
          _isVideoUrl(mediaUrl)
              ? _buildNetworkVideoThumbnail(context, mediaUrl)
              : GestureDetector(
            onTap: () {
              // ✅ Open full-screen viewer with all images from post
              final imageUrls = post.media_urls!
                  .where((url) => !_isVideoUrl(url))
                  .toList();
              final imageIndex = imageUrls.indexOf(mediaUrl);

              FullScreenImageViewer.show(
                context,
                imageUrls: imageUrls,
                initialIndex: imageIndex >= 0 ? imageIndex : 0,
              );
            },
            child: ZoomableImage(
              minScale: 1.0,
              maxScale: 4.0,
              child: Image.network(
                mediaUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Theme.of(context).cardColor,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Colors.blue,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Theme.of(context).cardColor,
                    child: Center(
                      child: Icon(
                        Icons.image_not_supported,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        size: 30,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Media count indicator for multiple media
          if (post.media_urls!.length > 1)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).shadowColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${post.media_urls!.length}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildVideoThumbnail(BuildContext context, File videoFile) {
    return Container(
      color: Theme.of(context).cardColor,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.play_circle_fill,
            color: Theme.of(context).colorScheme.onSurface,
            size: 40,
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkVideoThumbnail(BuildContext context, String videoUrl) {
    return Container(
      color: Theme.of(context).cardColor,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.play_circle_fill,
            color: Theme.of(context).colorScheme.onSurface,
            size: 40,
          ),
        ],
      ),
    );
  }

  bool _isVideoFile(String path) {
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    return videoExtensions.any((ext) => path.toLowerCase().endsWith(ext));
  }

  bool _isVideoUrl(String url) {
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    return videoExtensions.any((ext) => url.toLowerCase().contains(ext));
  }

  String _formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return '';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()}w';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }
}

class _StatIcon extends StatelessWidget {
  final IconData icon;
  final int count;
  final Color color;

  const _StatIcon({
    required this.icon,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        SizedBox(width: 2),
        Text(
          _formatCount(count),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return count.toString();
    }
  }
}

void _showMoreOptions(BuildContext context, Post_feed post) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => Consumer(
      builder: (context, ref, child) {
        final currentUserId = ref.watch(currentUserIdProvider);

        // Check if toast belongs to current user
        final isOwner = currentUserId != null && currentUserId == post.user_id;

        return Consumer(
          builder: (context, ref, child) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (isOwner)
                    ListTile(
                      leading: Icon(Icons.edit_outlined, color: Colors.blue),
                      title: Text('Edit Post', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      onTap: () {
                        Navigator.pop(context);
                        // Navigate to edit post screen
                        // Navigator.pushNamed(context, '/edit-post', arguments: post);
                      },
                    ),
                  if (isOwner)
                    ListTile(
                      leading: Icon(Icons.delete_outline, color: Colors.red),
                      title: Text('Delete Post', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                      onTap: () async {
                        showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: Theme.of(context).cardColor,
                            title: Text('Delete Post', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                            content: Text('Are you sure you want to delete this post?',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                              ),
                              TextButton(
                                onPressed: () async{
                                  final success = await ref.read(profileFeedProvider.notifier).deletePost(post.post_id!);

                                  Navigator.pop(context);
                                  Navigator.pop(context);

                                  if (success) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Post deleted successfully')),
                                    );

                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Failed to delete post')),
                                    );
                                  }
                                },// => Navigator.pop(context, true),
                                child: Text('Delete', style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                        //Navigator.pop(context);
                      },
                    ),
                  ListTile(
                    leading: Icon(Icons.visibility_off_outlined, color: Colors.orange),
                    title: Text('Hide Post', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                    onTap: () {
                      Navigator.pop(context);
                      // Implement hide post functionality
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post hidden')),
                      );
                    },
                  ),
                  SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}