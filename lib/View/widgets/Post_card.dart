import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../Model/post.dart';
import '../../ViewModel/post_feed_provider.dart';
import '../../ViewModel/theme_provider.dart'; // Add this import
import 'unified_comments_bottom_sheet.dart';
import 'dart:io';
// import '../profile.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'zoomable_image.dart';
import 'double_tap_like.dart';
import 'full_screen_image_viewer.dart';
import '../ratings_dialogs.dart';

class _LocalVideoPlayer extends StatefulWidget {
  final File file;

  const _LocalVideoPlayer({required this.file});

  @override
  __LocalVideoPlayerState createState() => __LocalVideoPlayerState();
}

class __LocalVideoPlayerState extends State<_LocalVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Center(child: CircularProgressIndicator());
    }
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: VideoPlayer(_controller),
    );
  }
}

bool _isVideoFile(String path) {
  final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
  return videoExtensions.any((ext) => path.toLowerCase().endsWith(ext));
}

class PostCard extends ConsumerStatefulWidget {
  final Post_feed post;
  final VoidCallback? onTap;
  final VoidCallback? onUserInfo;
  final bool isPreview;

  const PostCard({
    Key? key,
    required this.post,
    this.onTap,
    this.onUserInfo,
    this.isPreview = false,
  }) : super(key: key);

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _isBookmarked = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(themeNotifierProvider);

    // For preview posts, use the widget.post directly and don't access postFeedState
    if (widget.isPreview) {
      return Card(
        color: theme.cardTheme.color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Info Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0,8.0,8.0,0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: widget.post.profile_pic != null
                          ? NetworkImage(widget.post.profile_pic!)
                          : const AssetImage('assets/plaro_logo.png') as ImageProvider,
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.post.username ?? 'Unknown User',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatTimeAgo(widget.post.created_at),
                            style: TextStyle(
                              color: theme.dividerColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Disable more options for preview
                    IconButton(
                      icon: Icon(Icons.more_vert, color: theme.dividerColor),
                      onPressed: null, // Disabled for preview
                    ),
                  ],
                ),
              ),

              // Title
              if (widget.post.title != null && widget.post.title!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8.0,0.0,8.0,2.0),
                  child: Text(
                    widget.post.title!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              // Media Section
              if ((widget.post.media_urls != null && widget.post.media_urls!.isNotEmpty) ||
                  (widget.post.localMediaFiles != null && widget.post.localMediaFiles!.isNotEmpty))
                _buildMediaSection(widget.post.media_urls ?? [], widget.post.localMediaFiles),

              // Content
              if (widget.post.content != null && widget.post.content!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    widget.post.content!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.8),
                      fontSize: 14,
                      height: 1.4,
                    ),
                    maxLines: 10,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              // Tags
              if (widget.post.tags != null && widget.post.tags!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: widget.post.tags!.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

              // Action Buttons - All disabled for preview
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Like Button - disabled
                  _ActionButton(
                    icon: Icons.favorite_border,
                    label: '0',
                    color: theme.dividerColor,
                    onPressed: null, // Disabled for preview
                  ),

                  // Comment Button - disabled
                  _ActionButton(
                    icon: Icons.comment_outlined,
                    label: '0',
                    color: theme.dividerColor,
                    onPressed: null, // Disabled for preview
                  ),

                  // Share Button - disabled
                  _ActionButton(
                    icon: Icons.share_outlined,
                    label: '0',
                    color: theme.dividerColor,
                    onPressed: null, // Disabled for preview
                  ),

                  // Bookmark Button - disabled
                  _ActionButton(
                    icon: Icons.bookmark_border,
                    label: '',
                    color: theme.dividerColor,
                    onPressed: null, // Disabled for preview
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // Original code for non-preview posts
    final postFeedState = ref.watch(postFeedProvider);
    final currentPost = postFeedState.posts.firstWhere(
            (p) => p.post_id == widget.post.post_id,
        orElse: () => widget.post
    );

    final isLiking = postFeedState.likingPosts.contains(widget.post.post_id);

    // Show error if there's one
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (postFeedState.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(postFeedState.error!),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () => ref.read(postFeedProvider.notifier).clearError(),
            ),
          ),
        );
      }
    });

    return Card(
      color: theme.cardTheme.color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User Info Header
            GestureDetector(
              onTap: widget.onUserInfo,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8.0,8.0,8.0,0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: currentPost.profile_pic != null
                          ? CachedNetworkImageProvider(currentPost.profile_pic!)
                          : const AssetImage('assets/plaro_logo.png') as ImageProvider,
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentPost.username ?? 'Unknown User',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatTimeAgo(currentPost.created_at),
                            style: TextStyle(
                              color: theme.dividerColor,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Rating icons (Ranked-By then Star, right-to-left) ──
                    if (currentPost.post_id != null) ...[
                      PostRankedByIcon(postId: currentPost.post_id!),
                      PostStarRatingIcon(postId: currentPost.post_id!),
                    ],
                    IconButton(
                      icon: Icon(Icons.more_vert, color: theme.dividerColor),
                      onPressed: () {
                        _showMoreOptions(context, currentPost);
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Title
            if (currentPost.title != null && currentPost.title!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0,0.0,8.0,2.0),
                child: Text(
                  currentPost.title!,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            // Media Section
            if ((currentPost.media_urls != null && currentPost.media_urls!.isNotEmpty) ||
                (currentPost.localMediaFiles != null && currentPost.localMediaFiles!.isNotEmpty))
              _buildMediaSection(currentPost.media_urls ?? [], currentPost.localMediaFiles),

            // Content
            if (currentPost.content != null && currentPost.content!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  currentPost.content!,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.8),
                    fontSize: 14,
                    height: 1.4,
                  ),
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // Tags
            if (currentPost.tags != null && currentPost.tags!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: currentPost.tags!.map((tag) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.5)),
                      ),
                      child: Text(
                        '#$tag',
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Like Button
                _ActionButton(
                  icon: currentPost.isliked ? Icons.favorite : Icons.favorite_border,
                  label: '${currentPost.like_count}',
                  color: currentPost.isliked ? Colors.red : theme.dividerColor,
                  isLoading: isLiking,
                  onPressed: isLiking ? null : () {
                    if (currentPost.post_id != null) {
                      ref.read(postFeedProvider.notifier).toggleLike(currentPost.post_id!);
                    }
                  },
                ),

                // Comment Button
                _ActionButton(
                  icon: Icons.comment_outlined,
                  label: '${currentPost.comment_count}',
                  color: theme.dividerColor,
                  onPressed: () {
                    _showCommentsSheet(context, currentPost.post_id!);
                  },
                ),

                // Share Button
                _ActionButton(
                  icon: Icons.share_outlined,
                  label: '${currentPost.share_count ?? 0}',
                  color: theme.dividerColor,
                  onPressed: () {
                    _sharePost(context, currentPost);
                  },
                ),

                // Bookmark Button
                _ActionButton(
                  icon: _isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                  label: '',
                  color: _isBookmarked ? theme.colorScheme.primary : theme.dividerColor,
                  onPressed: () {
                    _toggleBookmark();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Media Section Builder
  Widget _buildMediaSection(List<String> mediaUrls, List<XFile>? localFiles) {
    if (localFiles != null && localFiles.isNotEmpty) {
      return _buildLocalMediaSection(localFiles);
    } else if (mediaUrls.isNotEmpty) {
      return mediaUrls.length == 1
          ? _buildSingleMedia(mediaUrls[0])
          : _buildMultipleMedia(mediaUrls);
    }
    return const SizedBox.shrink();
  }

  Widget _buildLocalMediaSection(List<XFile> files) {
    return AspectRatio(
      aspectRatio: 5/6,
      child: PageView.builder(
        itemCount: files.length,
        itemBuilder: (context, index) {
          final file = files[index];
          return _isVideoFile(file.path)
              ? _LocalVideoPlayer(file: File(file.path))
              : GestureDetector(
            onTap: () {
              // For local files, extract image URLs from all non-video files
              final imageFiles = files
                  .where((f) => !_isVideoFile(f.path))
                  .map((f) => f.path)
                  .toList();
              final currentImageIndex = imageFiles.indexOf(file.path);

              // Note: FullScreenImageViewer expects URLs, not local paths
              // You might want to upload these first or create a local variant
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
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSingleMedia(String mediaUrl) {
    final theme = Theme.of(context);

    return AspectRatio(
      aspectRatio: 5/6 ,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: PostDoubleTapLike(
          postId: widget.post.post_id ?? '',
          isliked: widget.post.isliked,
          child: _isVideoUrl(mediaUrl)
              ? VideoPlayerWidget(videoUrl: mediaUrl)
              : GestureDetector(
            onTap: () {
              // Open full-screen viewer on single tap
              FullScreenImageViewer.show(
                context,
                imageUrls: [mediaUrl],
                initialIndex: 0,
              );
            },
            child: ZoomableImage(
              minScale: 1.0,
              maxScale: 4.0,
              child: CachedNetworkImage(
                imageUrl: mediaUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                memCacheWidth: 800, // Optimize memory usage
                maxWidthDiskCache: 1000, // Disk cache size
                placeholder: (context, url) => Container(
                  color: theme.cardTheme.color,
                  child: Center(
                    child: CircularProgressIndicator(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: theme.cardTheme.color,
                  child: Icon(
                    Icons.image_not_supported,
                    color: theme.dividerColor,
                    size: 50,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMultipleMedia(List<String> mediaUrls) {
    final PageController pageController = PageController();
    int currentPage = 0;

    return AspectRatio(
      aspectRatio: 5/6,
      child: StatefulBuilder(
        builder: (context, setState) {
          return Stack(
            children: [
              PageView.builder(
                controller: pageController,
                itemCount: mediaUrls.length,
                onPageChanged: (index) {
                  setState(() {
                    currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final mediaUrl = mediaUrls[index];
                  final theme = Theme.of(context);

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: PostDoubleTapLike(
                      postId: widget.post.post_id ?? '',
                      isliked: widget.post.isliked,
                      child: _isVideoUrl(mediaUrl)
                          ? VideoPlayerWidget(videoUrl: mediaUrl)
                          : GestureDetector(
                        onTap: () {
                          // Open full-screen viewer with all images, starting at current index
                          final imageUrls = mediaUrls.where((url) => !_isVideoUrl(url)).toList();
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
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: theme.cardTheme.color,
                                child: Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    color: theme.dividerColor,
                                    size: 50,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),),
                    ),
                  );
                },
              ),
              // Media counter indicator
              Positioned(
                top: 8,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${currentPage + 1}/${mediaUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isVideoUrl(String url) {
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    return videoExtensions.any((ext) => url.toLowerCase().contains(ext));
  }

  String _formatTimeAgo(DateTime? dateTime) {
    if (dateTime == null) return 'Unknown';

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  void _showMoreOptions(BuildContext context, Post_feed post) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.report_outlined, color: Colors.red),
                title: Text('Report Post', style: TextStyle(color: theme.colorScheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _reportPost(context, post);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined, color: Colors.orange),
                title: Text('Block User', style: TextStyle(color: theme.colorScheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _blockUser(context, post);
                },
              ),
              ListTile(
                leading: Icon(Icons.copy_outlined, color: theme.dividerColor),
                title: Text('Copy Link', style: TextStyle(color: theme.colorScheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _copyPostLink(context, post);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showCommentsSheet(BuildContext context, String postId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return CommentSheet(postId: postId);
      },
    );
  }

  void _sharePost(BuildContext context, Post_feed post) {
    final shareText = '''
${post.title ?? ''}
${post.content ?? ''}
${post.caption ?? ''}

Shared from MyApp
''';

    Share.share(shareText.trim());
  }

  void _toggleBookmark() {
    setState(() {
      _isBookmarked = !_isBookmarked;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isBookmarked ? 'Post bookmarked' : 'Post removed from bookmarks'),
        backgroundColor: _isBookmarked ? Theme.of(context).colorScheme.primary : Theme.of(context).dividerColor,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _reportPost(BuildContext context, Post_feed post) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardTheme.color,
        title: Text('Report Post', style: TextStyle(color: theme.colorScheme.onSurface)),
        content: Text(
          'Are you sure you want to report this post? We will review it and take appropriate action.',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Post reported successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Report', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _blockUser(BuildContext context, Post_feed post) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.cardTheme.color,
        title: Text('Block User', style: TextStyle(color: theme.colorScheme.onSurface)),
        content: Text(
          'Are you sure you want to block ${post.username ?? 'this user'}? You won\'t see their posts anymore.',
          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('User blocked successfully'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _copyPostLink(BuildContext context, Post_feed post) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            else
              Icon(icon, color: color, size: 20),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Video Player Widget with better performance
class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;

  const VideoPlayerWidget({Key? key, required this.videoUrl}) : super(key: key);

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> with AutomaticKeepAliveClientMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = false;

  @override
  bool get wantKeepAlive => true; // Keep video state when scrolled away

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
      );

      await _controller.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      // Add listener for play/pause state
      _controller.addListener(() {
        if (mounted) {
          setState(() {
            _isPlaying = _controller.value.isPlaying;
          });
        }
      });
    } catch (error) {
      debugPrint('Error initializing video: $error');
      if (mounted) {
        setState(() {
          _isInitialized = false;
        });
      }
    }
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {
      _showControls = true;
    });

    // Hide controls after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);

    if (!_isInitialized) {
      return Container(
        color: theme.cardTheme.color,
        child: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller.value.aspectRatio,
            child: VideoPlayer(_controller),
          ),

          // Play/Pause overlay
          if (_showControls || !_isPlaying)
            AnimatedOpacity(
              opacity: _showControls || !_isPlaying ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(16),
                child: Icon(
                  _isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Comment Sheet Widget - Now uses unified bottom sheet
class CommentSheet extends ConsumerWidget {
  final String postId;

  const CommentSheet({
    Key? key,
    required this.postId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postFeedState = ref.read(postFeedProvider);

    return UnifiedCommentsBottomSheet(
      contentId: postId,
      title: 'Comments',
      commentCount: null,
      likingComments: postFeedState.likingComments,
      callbacks: CommentSheetCallbacks(
        loadComments: () => ref.read(postFeedProvider.notifier).loadComments(postId),
        loadReplies: (parentCommentId) => ref.read(postFeedProvider.notifier).loadReplies(postId, int.parse(parentCommentId)),
        getRepliesCount: (parentCommentId) => ref.read(postFeedProvider.notifier).getRepliesCount(int.parse(parentCommentId)),
        addComment: (content) => ref.read(postFeedProvider.notifier).addComment(postId, content),
        addReply: (parentCommentId, content) => ref.read(postFeedProvider.notifier).addReply(postId, int.parse(parentCommentId), content),
        toggleCommentLike: (commentId) => ref.read(postFeedProvider.notifier).toggleCommentLike(int.parse(commentId)),
        getCurrentUserId: () => Supabase.instance.client.auth.currentUser?.id,
        getUserProfile: () async {
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null) return null;
          try {
            final response = await Supabase.instance.client
                .from('user_profiles')
                .select('profile_pic')
                .eq('user_id', user.id)
                .maybeSingle();
            return response;
          } catch (e) {
            debugPrint('Error fetching user profile: $e');
            return null;
          }
        },
      ),
    );
  }
}