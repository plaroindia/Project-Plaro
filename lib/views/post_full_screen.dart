import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/post.dart';
import '../Viewmodels/user_feed_provider.dart';
import '../Viewmodels/post_feed_provider.dart';
import '../Viewmodels/user_provider.dart';
import '../Viewmodels/auth_provider.dart';
import '../Viewmodels/content_event_tracker.dart' hide ContentType;
import 'widgets/double_tap_like.dart';
import 'widgets/content_actions.dart';
import 'widgets/unified_comments_bottom_sheet.dart';
import 'post_page.dart';

// ─────────────────────────────────────────────────────────────────────────────

bool _isVideoUrl(String url) {
  const exts = ['.mp4', '.mov', '.avi', '.mkv', '.m4v', '.webm'];
  final lower = url.toLowerCase();
  return exts.any(lower.contains);
}

String _timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final d = DateTime.now().difference(dt);
  if (d.inDays > 7) return '${dt.day}/${dt.month}/${dt.year}';
  if (d.inDays > 0) return '${d.inDays}d ago';
  if (d.inHours > 0) return '${d.inHours}h ago';
  if (d.inMinutes > 0) return '${d.inMinutes}m ago';
  return 'Just now';
}

// ─────────────────────────────────────────────────────────────────────────────
// PostFullScreen v2
// ─────────────────────────────────────────────────────────────────────────────

class PostFullScreen extends ConsumerStatefulWidget {
  final Post_feed post;

  /// [fromProfileFeed] routes likes/comments through [profileFeedProvider]
  /// when true, otherwise through [postFeedProvider].
  final bool fromProfileFeed;

  const PostFullScreen({
    super.key,
    required this.post,
    this.fromProfileFeed = false,
  });

  @override
  ConsumerState<PostFullScreen> createState() => _PostFullScreenState();
}

class _PostFullScreenState extends ConsumerState<PostFullScreen> {
  final _scrollCtrl = ScrollController();
  int _mediaIndex = 0;
  final Map<int, VideoPlayerController> _videos = {};
  final DateTime _openedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initVideos();
    WidgetsBinding.instance.addPostFrameCallback((_) => _trackView());
  }

  @override
  void dispose() {
    _trackDwell();
    _scrollCtrl.dispose();
    for (final c in _videos.values) {
      c.dispose();
    }
    _videos.clear();
    super.dispose();
  }

  // ── Analytics ──────────────────────────────────────────────────────────────

  String? get _userId =>
      ref.read(authStateProvider).valueOrNull?.user.id;

  void _trackView() {
    final uid = _userId;
    if (uid == null) return;
    ref.read(contentEventTrackerProvider).trackView(
      userId: uid,
      contentType: 'post',
      contentIdInt: int.tryParse(widget.post.post_id ?? ''),
      source: 'profile',
    );
  }

  void _trackDwell() {
    final secs = DateTime.now().difference(_openedAt).inSeconds;
    if (secs < 2) return;
    final uid = _userId;
    if (uid == null) return;
    ref.read(contentEventTrackerProvider).trackDwell(
      userId: uid,
      contentType: 'post',
      contentIdInt: int.tryParse(widget.post.post_id ?? ''),
      dwellTimeSeconds: secs,
    );
  }

  void _trackLike(Post_feed post) {
    if (post.isliked) return; // track only actual likes, not unlikes
    final uid = _userId;
    if (uid == null) return;
    ref.read(contentEventTrackerProvider).trackLike(
      userId: uid,
      contentType: 'post',
      contentIdInt: int.tryParse(post.post_id ?? ''),
    );
  }

  void _trackShare(Post_feed post) {
    final uid = _userId;
    if (uid == null) return;
    ref.read(contentEventTrackerProvider).trackShare(
      userId: uid,
      contentType: 'post',
      contentIdInt: int.tryParse(post.post_id ?? ''),
    );
  }

  void _trackCommentOpen(String postId) {
    final uid = _userId;
    if (uid == null) return;
    ref.read(contentEventTrackerProvider).trackComment(
      userId: uid,
      contentType: 'post',
      contentIdInt: int.tryParse(postId),
    );
  }

  // ── Feed routing ───────────────────────────────────────────────────────────

  void _toggleLike(String postId) => widget.fromProfileFeed
      ? ref.read(profileFeedProvider.notifier).togglePostLike(postId)
      : ref.read(postFeedProvider.notifier).toggleLike(postId);

  // ── Video management ───────────────────────────────────────────────────────

  void _initVideos() {
    final urls = widget.post.media_urls ?? [];
    for (int i = 0; i < urls.length; i++) {
      if (!_isVideoUrl(urls[i])) continue;
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(urls[i]));
      _videos[i] = ctrl; // store before initialize so the callback can safely reference it
      ctrl.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        if (i == 0) {
          ctrl
            ..play()
            ..setLooping(true);
        }
      }).catchError((_) {});
    }
  }

  void _onPageChanged(int i) {
    for (final c in _videos.values) {
      c.pause();
    }
    setState(() => _mediaIndex = i);
    _videos[i]?.play();
  }

  void _tapVideo(int i) {
    final ctrl = _videos[i];
    if (ctrl == null || !ctrl.value.isInitialized) return;
    setState(() =>
    ctrl.value.isPlaying ? ctrl.pause() : ctrl.play());
  }

  // ── Handlers ───────────────────────────────────────────────────────────────

  void _openComments(BuildContext context, String postId) {
    _trackCommentOpen(postId);
    final state = ref.read(postFeedProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => UnifiedCommentsBottomSheet(
        contentId: postId,
        title: 'Comments',
        commentCount: null,
        likingComments: state.likingComments,
        callbacks: CommentSheetCallbacks(
          loadComments: () =>
              ref.read(postFeedProvider.notifier).loadComments(postId),
          loadReplies: (id) => ref
              .read(postFeedProvider.notifier)
              .loadReplies(postId, int.parse(id)),
          getRepliesCount: (id) =>
              ref.read(postFeedProvider.notifier).getRepliesCount(int.parse(id)),
          addComment: (c) async {
            await ref.read(postFeedProvider.notifier).addComment(postId, c);
            _bumpCommentCount(postId);
            return true;
          },
          addReply: (id, c) =>
              ref.read(postFeedProvider.notifier).addReply(postId, int.parse(id), c),
          toggleCommentLike: (id) =>
              ref.read(postFeedProvider.notifier).toggleCommentLike(int.parse(id)),
          getCurrentUserId: () => Supabase.instance.client.auth.currentUser?.id,
          getUserProfile: () async {
            final user = Supabase.instance.client.auth.currentUser;
            if (user == null) return null;
            try {
              return await Supabase.instance.client
                  .from('user_profiles')
                  .select('profile_pic')
                  .eq('user_id', user.id)
                  .maybeSingle();
            } catch (_) {
              return null;
            }
          },
        ),
      ),
    );
  }

  void _bumpCommentCount(String postId) {
    if (!widget.fromProfileFeed) return;
    ref.read(profileFeedProvider.notifier).bumpCommentCount(postId);
  }

  void _handleEdit(BuildContext ctx) => Navigator.push(
      ctx, MaterialPageRoute(builder: (_) => PostCreateScreen()));

  Future<void> _handleDelete(BuildContext ctx) async {
    final post = ref
        .read(profileFeedProvider)
        .posts
        .firstWhere((p) => p.post_id == widget.post.post_id,
        orElse: () => widget.post);
    if (post.post_id == null) return;

    final ok = await ref
        .read(profileFeedProvider.notifier)
        .deletePost(post.post_id!);

    if (ctx.mounted) {
      Navigator.pop(ctx);
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text(ok ? 'Post deleted' : 'Failed to delete post'),
        backgroundColor: ok ? Colors.green : Colors.red,
      ));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Post_feed post;
    final bool isLiking;

    if (widget.fromProfileFeed) {
      final s = ref.watch(profileFeedProvider);
      post = s.posts.firstWhere(
              (p) => p.post_id == widget.post.post_id,
          orElse: () => widget.post);
      isLiking = s.likingPosts.contains(post.post_id);
    } else {
      final s = ref.watch(postFeedProvider);
      post = s.posts.firstWhere(
              (p) => p.post_id == widget.post.post_id,
          orElse: () => widget.post);
      isLiking = s.likingPosts.contains(post.post_id);
    }

    final currentUserId = ref.watch(currentUserIdProvider);
    final isOwner = currentUserId != null && currentUserId == post.user_id;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context, post, currentUserId, isOwner),
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: kToolbarHeight + 16)),
          if (post.media_urls?.isNotEmpty == true)
            SliverToBoxAdapter(
              child: _MediaArea(
                post: post,
                mediaIndex: _mediaIndex,
                videos: _videos,
                isLiking: isLiking,
                onPageChanged: _onPageChanged,
                onVideoTap: _tapVideo,
                onLike: () {
                  _trackLike(post);
                  _toggleLike(post.post_id!);
                },
              ),
            ),
          SliverToBoxAdapter(
            child: _InfoSection(
              post: post,
              isLiking: isLiking,
              onLike: () {
                _trackLike(post);
                _toggleLike(post.post_id!);
              },
              onComment: () =>
                  _openComments(context, post.post_id!),
              onShare: () {
                _trackShare(post);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Share coming soon'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context, Post_feed post,
      String? currentUserId, bool isOwner) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
        splashRadius: 20,
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundImage: post.profile_pic != null
                ? NetworkImage(post.profile_pic!)
                : const AssetImage('assets/plaro_logo.png') as ImageProvider,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              post.username ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        if (currentUserId != null)
          ContentActionMenu(
            data: ContentActionData(
              contentId: post.post_id ?? '',
              userId: post.user_id ?? '',
              contentType: ContentType.post,
              isHidden: false,
              shareText: post.content,
              shareUrl: 'https://yourapp.com/post/${post.post_id}',
            ),
            callbacks: ContentActionCallbacks(
              onEdit: isOwner ? () => _handleEdit(context) : null,
              onDelete: isOwner ? () => _handleDelete(context) : null,
              onToggleHide: isOwner
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hide coming soon')),
              )
                  : null,
              onShare: () => _trackShare(post),
            ),
            currentUserId: currentUserId,
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Media area
// ─────────────────────────────────────────────────────────────────────────────

class _MediaArea extends StatelessWidget {
  final Post_feed post;
  final int mediaIndex;
  final Map<int, VideoPlayerController> videos;
  final bool isLiking;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onVideoTap;
  final VoidCallback onLike;

  const _MediaArea({
    required this.post,
    required this.mediaIndex,
    required this.videos,
    required this.isLiking,
    required this.onPageChanged,
    required this.onVideoTap,
    required this.onLike,
  });

  @override
  Widget build(BuildContext context) {
    final urls = post.media_urls!;

    return SizedBox(
      height: MediaQuery.of(context).size.width * 1.15, // ~portrait aspect
      child: Stack(
        children: [
          DoubleTapLike(
            onDoubleTap: onLike,
            isliked: post.isliked,
            isLoading: isLiking,
            child: PageView.builder(
              itemCount: urls.length,
              onPageChanged: onPageChanged,
              itemBuilder: (ctx, i) {
                final url = urls[i];
                if (_isVideoUrl(url)) return _VideoItem(index: i, videos: videos, onTap: onVideoTap);
                return _ImageItem(url: url);
              },
            ),
          ),

          // Multi-page dots
          if (urls.length > 1)
            Positioned(
              bottom: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  urls.length,
                      (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == mediaIndex ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == mediaIndex ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(3),
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

class _VideoItem extends StatelessWidget {
  final int index;
  final Map<int, VideoPlayerController> videos;
  final ValueChanged<int> onTap;

  const _VideoItem(
      {required this.index, required this.videos, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ctrl = videos[index];
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: Colors.blue),
      );
    }
    return GestureDetector(
      onTap: () => onTap(index),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: ctrl.value.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),
          if (!ctrl.value.isPlaying)
            const Center(
              child: _PlayIcon(),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: VideoProgressIndicator(
              ctrl,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.blue,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
              ),
              padding: const EdgeInsets.all(10),
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageItem extends StatelessWidget {
  final String url;
  const _ImageItem({required this.url});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      memCacheWidth: 1080,
      placeholder: (_, __) => const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
      ),
      errorWidget: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white30, size: 48),
      ),
    );
  }
}

class _PlayIcon extends StatelessWidget {
  const _PlayIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration:
      const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
      child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info section (below media)
// ─────────────────────────────────────────────────────────────────────────────

class _InfoSection extends StatelessWidget {
  final Post_feed post;
  final bool isLiking;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  const _InfoSection({
    required this.post,
    required this.isLiking,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Action row
          Row(
            children: [
              _LikeButton(
                isLiked: post.isliked,
                likeCount: post.like_count,
                isLoading: isLiking,
                onTap: onLike,
              ),
              const SizedBox(width: 20),
              _CommentButton(
                count: post.comment_count,
                onTap: onComment,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.share_outlined,
                    color: Colors.white, size: 22),
                onPressed: onShare,
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Title
          if (post.title?.isNotEmpty == true) ...[
            Text(
              post.title!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Content
          if (post.content?.isNotEmpty == true) ...[
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${post.username ?? ''} ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  TextSpan(
                    text: post.content!,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13.5,
                        height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Tags
          if (post.tags?.isNotEmpty == true) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: post.tags!
                  .map((t) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.2)),
                ),
                child: Text('#$t',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],

          // Timestamp
          Text(
            _timeAgo(post.created_at),
            style:
            TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

// ─── Like / Comment buttons ───────────────────────────────────────────────────

class _LikeButton extends StatelessWidget {
  final bool isLiked;
  final int likeCount;
  final bool isLoading;
  final VoidCallback onTap;

  const _LikeButton({
    required this.isLiked,
    required this.likeCount,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 1.8, color: Colors.white),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.elasticOut,
              transitionBuilder: (child, anim) =>
                  ScaleTransition(scale: anim, child: child),
              child: Icon(
                isLiked ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                key: ValueKey(isLiked),
                color: isLiked ? Colors.redAccent : Colors.white,
                size: 24,
              ),
            ),
          const SizedBox(width: 5),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              '$likeCount',
              key: ValueKey(likeCount),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _CommentButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mode_comment_outlined,
              color: Colors.white, size: 22),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}