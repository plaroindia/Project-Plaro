import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Model/post.dart';
import '../ViewModel/user_feed_provider.dart';
import '../ViewModel/post_feed_provider.dart';
import '../ViewModel/user_provider.dart';
import '../ViewModel/auth_provider.dart';
import '../ViewModel/content_event_tracker.dart' hide ContentType; // ✅ ADDED
import 'widgets/double_tap_like.dart';
import 'widgets/content_actions.dart';
import 'widgets/unified_comments_bottom_sheet.dart';
import 'post_page.dart';

class PostFullScreen extends ConsumerStatefulWidget {
  final Post_feed post;

  const PostFullScreen({Key? key, required this.post}) : super(key: key);

  @override
  ConsumerState<PostFullScreen> createState() => _PostFullScreenState();
}

class _PostFullScreenState extends ConsumerState<PostFullScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentMediaIndex = 0;
  final Map<int, VideoPlayerController> _videoControllers = {};

  // ── Dwell tracking ───────────────────────────────────────
  final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeVideos();

    // ── Track view immediately on open ───────────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackView();
    });
  }

  @override
  void dispose() {
    _trackDwell(); // ✅ flush dwell on close
    _scrollController.dispose();
    _disposeVideoControllers();
    super.dispose();
  }

  // ── Event helpers ─────────────────────────────────────────

  void _trackView() {
    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId == null) return;
    ref.read(contentEventTrackerProvider).trackView(
      userId: userId,
      contentType: 'post',
      contentIdInt:
      int.tryParse(widget.post.post_id ?? ''),
      source: 'profile',
    );
  }

  void _trackDwell() {
    final dwellSeconds =
        DateTime.now().difference(_openedAt).inSeconds;
    if (dwellSeconds < 2) return;
    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId == null) return;
    ref.read(contentEventTrackerProvider).trackDwell(
      userId: userId,
      contentType: 'post',
      contentIdInt:
      int.tryParse(widget.post.post_id ?? ''),
      dwellTimeSeconds: dwellSeconds,
    );
  }

  void _trackLike(Post_feed post) {
    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId == null) return;
    // Track only when the action is a "like" (not an unlike)
    if (!post.isliked) {
      ref.read(contentEventTrackerProvider).trackLike(
        userId: userId,
        contentType: 'post',
        contentIdInt: int.tryParse(post.post_id ?? ''),
      );
    }
  }

  void _trackShare(Post_feed post) {
    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId == null) return;
    ref.read(contentEventTrackerProvider).trackShare(
      userId: userId,
      contentType: 'post',
      contentIdInt: int.tryParse(post.post_id ?? ''),
    );
  }

  // ── Video management ─────────────────────────────────────

  void _initializeVideos() {
    if (widget.post.media_urls == null) return;

    for (int i = 0; i < widget.post.media_urls!.length; i++) {
      final url = widget.post.media_urls![i];

      if (_isVideoUrl(url)) {
        final controller =
        VideoPlayerController.networkUrl(Uri.parse(url));

        controller.initialize().then((_) {
          if (!mounted) return;

          setState(() {});

          if (i == 0) {
            controller.play();
            controller.setLooping(true);
          }
        }).catchError((e) {
          debugPrint('init video error: $e');
          return null;
        });

        _videoControllers[i] = controller;
      }
    }
  }

  void _disposeVideoControllers() {
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
  }

  bool _isVideoUrl(String url) {
    final videoExtensions = [
      '.mp4',
      '.mov',
      '.avi',
      '.mkv',
      '.m4v',
      '.webm'
    ];
    return videoExtensions
        .any((ext) => url.toLowerCase().contains(ext));
  }

  void _onMediaPageChanged(int index) {
    for (var entry in _videoControllers.entries) {
      entry.value.pause();
    }

    setState(() {
      _currentMediaIndex = index;
    });

    if (_videoControllers.containsKey(index)) {
      _videoControllers[index]!.play();
    }
  }

  void _toggleVideoPlayPause(int index) {
    if (!_videoControllers.containsKey(index)) return;

    final controller = _videoControllers[index]!;
    if (!controller.value.isInitialized) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(profileFeedProvider);
    final currentUserId = ref.watch(currentUserIdProvider);

    final currentPost = feedState.posts.firstWhere(
          (p) => p.post_id == widget.post.post_id,
      orElse: () => widget.post,
    );

    final isLiking =
    feedState.likingPosts.contains(currentPost.post_id);
    final isOwner = currentUserId != null &&
        currentUserId == currentPost.user_id;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: currentPost.profile_pic != null
                  ? NetworkImage(currentPost.profile_pic!)
                  : const AssetImage('assets/plaro_logo.png')
              as ImageProvider,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                currentPost.username!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          if (currentUserId != null)
            ContentActionMenu(
              data: ContentActionData(
                contentId: currentPost.post_id ?? '',
                userId: currentPost.user_id ?? '',
                contentType: ContentType.post,
                isHidden: false,
                shareText: currentPost.content,
                shareUrl:
                'https://yourapp.com/post/${currentPost.post_id}',
              ),
              callbacks: ContentActionCallbacks(
                onEdit: isOwner
                    ? () => _handleEdit(context, ref)
                    : null,
                onDelete: isOwner
                    ? () => _handleDelete(context, ref)
                    : null,
                onToggleHide: isOwner
                    ? () => _handleToggleHide(context, ref)
                    : null,
                onShare: () {
                  _trackShare(currentPost); // ✅ ADDED
                  _handleShare(context);
                },
              ),
              currentUserId: currentUserId,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                if (currentPost.media_urls != null &&
                    currentPost.media_urls!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildMediaSection(
                        currentPost, isLiking),
                  ),

                SliverToBoxAdapter(
                  child:
                  _buildPostInfoSection(currentPost),
                ),

                const SliverToBoxAdapter(
                    child: SizedBox(height: 16)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaSection(Post_feed post, bool isLiking) {
    return Container(
      height: 400,
      color: Colors.grey[900],
      child: Stack(
        children: [
          DoubleTapLike(
            onDoubleTap: () {
              _trackLike(post); // ✅ ADDED (fires before toggle)
              ref
                  .read(profileFeedProvider.notifier)
                  .togglePostLike(post.post_id!);
            },
            isliked: post.isliked,
            isLoading: isLiking,
            child: PageView.builder(
              itemCount: post.media_urls!.length,
              onPageChanged: _onMediaPageChanged,
              itemBuilder: (context, index) {
                final url = post.media_urls![index];
                final isVideo = _isVideoUrl(url);

                if (isVideo &&
                    _videoControllers.containsKey(index)) {
                  final controller =
                  _videoControllers[index]!;

                  return GestureDetector(
                    onTap: () =>
                        _toggleVideoPlayPause(index),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child:
                          controller.value.isInitialized
                              ? AspectRatio(
                            aspectRatio: controller
                                .value.aspectRatio,
                            child: VideoPlayer(
                                controller),
                          )
                              : const CircularProgressIndicator(
                            valueColor:
                            AlwaysStoppedAnimation<
                                Color>(Colors.blue),
                          ),
                        ),
                        if (controller.value.isInitialized &&
                            !controller.value.isPlaying)
                          IgnorePointer(
                            child: Center(
                              child: Container(
                                padding:
                                const EdgeInsets.all(16),
                                decoration:
                                const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            ),
                          ),
                        if (controller.value.isInitialized)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: VideoProgressIndicator(
                              controller,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.blue,
                                bufferedColor: Colors.grey,
                                backgroundColor:
                                Colors.white24,
                              ),
                              padding: const EdgeInsets.all(8),
                            ),
                          ),
                      ],
                    ),
                  );
                } else {
                  return Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder:
                        (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress
                              .expectedTotalBytes !=
                              null
                              ? loadingProgress
                              .cumulativeBytesLoaded /
                              loadingProgress
                                  .expectedTotalBytes!
                              : null,
                          valueColor:
                          const AlwaysStoppedAnimation<
                              Color>(Colors.blue),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                      );
                    },
                  );
                }
              },
            ),
          ),

          if (post.media_urls!.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  post.media_urls!.length,
                      (index) => Container(
                    margin:
                    const EdgeInsets.symmetric(horizontal: 4),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _currentMediaIndex == index
                          ? Colors.blue
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            top: 16,
            right: 16,
            child:
            _isVideoUrl(post.media_urls![_currentMediaIndex])
                ? Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline,
                      color: Colors.white, size: 20),
                  SizedBox(width: 4),
                  Text(
                    'Video',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12),
                  ),
                ],
              ),
            )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildPostInfoSection(Post_feed post) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  post.isliked
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: post.isliked ? Colors.red : Colors.white,
                  size: 28,
                ),
                onPressed: () {
                  _trackLike(post); // ✅ ADDED
                  ref
                      .read(profileFeedProvider.notifier)
                      .togglePostLike(post.post_id!);
                },
              ),
              const SizedBox(width: 4),
              Text(
                '${post.like_count}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: () => _showCommentsBottomSheet(
                    context, ref, post.post_id!),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.comment_outlined,
                        color: Colors.white, size: 26),
                    const SizedBox(width: 4),
                    Text(
                      '${post.comment_count}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.share_outlined,
                    color: Colors.white, size: 26),
                onPressed: () {
                  _trackShare(post); // ✅ ADDED
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Share feature coming soon!'),
                      backgroundColor: Colors.blue,
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (post.content != null && post.content!.isNotEmpty)
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${post.username} ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  TextSpan(
                    text: post.content!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          Text(
            _formatTimestamp(post.created_at),
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showCommentsBottomSheet(
      BuildContext context, WidgetRef ref, String postId) {
    // ✅ Track comment panel open as a comment signal
    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId != null) {
      ref.read(contentEventTrackerProvider).trackComment(
        userId: userId,
        contentType: 'post',
        contentIdInt: int.tryParse(postId),
      );
    }

    final postFeedState = ref.read(postFeedProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => UnifiedCommentsBottomSheet(
        contentId: postId,
        title: 'Comments',
        commentCount: null,
        likingComments: postFeedState.likingComments,
        callbacks: CommentSheetCallbacks(
          loadComments: () =>
              ref.read(postFeedProvider.notifier).loadComments(postId),
          loadReplies: (parentCommentId) => ref
              .read(postFeedProvider.notifier)
              .loadReplies(postId, int.parse(parentCommentId)),
          getRepliesCount: (parentCommentId) => ref
              .read(postFeedProvider.notifier)
              .getRepliesCount(int.parse(parentCommentId)),
          addComment: (content) => ref
              .read(postFeedProvider.notifier)
              .addComment(postId, content),
          addReply: (parentCommentId, content) => ref
              .read(postFeedProvider.notifier)
              .addReply(postId, int.parse(parentCommentId), content),
          toggleCommentLike: (commentId) => ref
              .read(postFeedProvider.notifier)
              .toggleCommentLike(int.parse(commentId)),
          getCurrentUserId: () =>
          Supabase.instance.client.auth.currentUser?.id,
          getUserProfile: () async {
            final user =
                Supabase.instance.client.auth.currentUser;
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
      ),
    );
  }

  void _handleEdit(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostCreateScreen(),
      ),
    );
  }

  void _handleDelete(BuildContext context, WidgetRef ref) async {
    final feedState = ref.read(profileFeedProvider);
    final post = feedState.posts.firstWhere(
          (p) => p.post_id == widget.post.post_id,
      orElse: () => widget.post,
    );

    if (post.post_id == null) return;

    final success = await ref
        .read(profileFeedProvider.notifier)
        .deletePost(post.post_id!);
    if (context.mounted) {
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete post'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleToggleHide(BuildContext context, WidgetRef ref) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hide functionality coming soon'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _handleShare(BuildContext context) {
    // platform share — copy link via ContentActionMenu
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return '';

    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 7) {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}