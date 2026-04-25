import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../../models/post.dart';
import '../../Viewmodels/post_feed_provider.dart';
import '../../Viewmodels/theme_provider.dart';
import '../../Viewmodels/auth_provider.dart';
import 'unified_comments_bottom_sheet.dart';
import 'zoomable_image.dart';
import 'double_tap_like.dart';
import 'full_screen_image_viewer.dart';
import '../ratings_dialogs.dart';
import 'follow_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

bool _isVideoUrl(String url) {
  const exts = ['.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v'];
  final lower = url.toLowerCase();
  return exts.any(lower.contains);
}

bool _isVideoFile(String path) {
  const exts = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
  final lower = path.toLowerCase();
  return exts.any(lower.endsWith);
}

String _timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final d = DateTime.now().difference(dt);
  if (d.inDays > 0) return '${d.inDays}d';
  if (d.inHours > 0) return '${d.inHours}h';
  if (d.inMinutes > 0) return '${d.inMinutes}m';
  return 'now';
}

// ─────────────────────────────────────────────────────────────────────────────
// Local video (preview only)
// ─────────────────────────────────────────────────────────────────────────────

class _LocalVideoPlayer extends StatefulWidget {
  final File file;
  const _LocalVideoPlayer({required this.file});

  @override
  State<_LocalVideoPlayer> createState() => _LocalVideoPlayerState();
}

class _LocalVideoPlayerState extends State<_LocalVideoPlayer> {
  late final VideoPlayerController _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _ctrl.value.size.width,
          height: _ctrl.value.size.height,
          child: VideoPlayer(_ctrl),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VideoPlayerWidget (network)
// ─────────────────────────────────────────────────────────────────────────────

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  const VideoPlayerWidget({super.key, required this.videoUrl});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with AutomaticKeepAliveClientMixin {
  late final VideoPlayerController _ctrl;
  bool _ready = false;
  bool _playing = false;
  bool _showOverlay = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      videoPlayerOptions:
      VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
    )..initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _ctrl.addListener(_onVideoUpdate);
    }).catchError((_) {});
  }

  void _onVideoUpdate() {
    if (mounted) setState(() => _playing = _ctrl.value.isPlaying);
  }

  void _tap() {
    _playing ? _ctrl.pause() : _ctrl.play();
    setState(() => _showOverlay = true);
    Future.delayed(const Duration(seconds: 2),
            () => mounted ? setState(() => _showOverlay = false) : null);
  }

  @override
  void dispose() {
    _ctrl
      ..pause()
      ..removeListener(_onVideoUpdate)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_ready) {
      return Container(
        color: Colors.black12,
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: _tap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _ctrl.value.size.width,
              height: _ctrl.value.size.height,
              child: VideoPlayer(_ctrl),
            ),
          ),
          AnimatedOpacity(
            opacity: _showOverlay || !_playing ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                    color: Colors.black45, shape: BoxShape.circle),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CommentSheet
// ─────────────────────────────────────────────────────────────────────────────

class CommentSheet extends ConsumerWidget {
  final String postId;
  const CommentSheet({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.read(postFeedProvider);
    return UnifiedCommentsBottomSheet(
      contentId: postId,
      title: 'Comments',
      commentCount: null,
      likingComments: state.likingComments,
      callbacks: CommentSheetCallbacks(
        loadComments: () =>
            ref.read(postFeedProvider.notifier).loadComments(postId),
        loadReplies: (id) =>
            ref.read(postFeedProvider.notifier).loadReplies(postId, int.parse(id)),
        getRepliesCount: (id) =>
            ref.read(postFeedProvider.notifier).getRepliesCount(int.parse(id)),
        addComment: (c) =>
            ref.read(postFeedProvider.notifier).addComment(postId, c),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PostCard v2
// ─────────────────────────────────────────────────────────────────────────────

class PostCard extends ConsumerStatefulWidget {
  final Post_feed post;
  final VoidCallback? onTap;
  final VoidCallback? onUserInfo;
  final bool isPreview;

  const PostCard({
    super.key,
    required this.post,
    this.onTap,
    this.onUserInfo,
    this.isPreview = false,
  });

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  bool _bookmarked = false;
  bool _expanded = false;

  // ── Media page controller lives here so it isn't recreated on rebuild
  late final PageController _pageCtrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    ref.watch(themeNotifierProvider);

    final post = widget.isPreview
        ? widget.post
        : ref
        .watch(postFeedProvider)
        .posts
        .firstWhere((p) => p.post_id == widget.post.post_id,
        orElse: () => widget.post);

    final isLiking = widget.isPreview
        ? false
        : ref.watch(postFeedProvider).likingPosts.contains(post.post_id);

    // Surface feed errors once, non-blocking
    if (!widget.isPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final err = ref.read(postFeedProvider).error;
        if (err != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(err),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () => ref.read(postFeedProvider.notifier).clearError(),
            ),
          ));
        }
      });
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                post: post,
                isPreview: widget.isPreview,
                onUserInfo: widget.onUserInfo,
                onMore: widget.isPreview
                    ? null
                    : () => _showMoreOptions(context, post),
              ),
              if (post.title?.isNotEmpty == true) _Title(post: post),
              _MediaSection(
                post: post,
                pageCtrl: _pageCtrl,
                currentPage: _page,
                onPageChanged: (i) => setState(() => _page = i),
                isPreview: widget.isPreview,
              ),
              if (post.content?.isNotEmpty == true)
                _ContentText(
                  content: post.content!,
                  expanded: _expanded,
                  onTap: widget.isPreview
                      ? null
                      : () => setState(() => _expanded = !_expanded),
                ),
              if (post.tags?.isNotEmpty == true) _Tags(tags: post.tags!),
              _ActionBar(
                post: post,
                isPreview: widget.isPreview,
                isLiking: isLiking,
                bookmarked: _bookmarked,
                onLike: (widget.isPreview || post.post_id == null)
                    ? null
                    : () => ref
                    .read(postFeedProvider.notifier)
                    .toggleLike(post.post_id!),
                onComment: (widget.isPreview || post.post_id == null)
                    ? null
                    : () => _openComments(context, post.post_id!),
                onShare: widget.isPreview ? null : () => _share(context, post),
                onBookmark: widget.isPreview
                    ? null
                    : () => setState(() {
                  _bookmarked = !_bookmarked;
                  _showBookmarkSnack(context);
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openComments(BuildContext context, String postId) =>
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => CommentSheet(postId: postId),
      );

  void _share(BuildContext context, Post_feed post) {
    final text =
    '${post.title ?? ''}\n${post.content ?? ''}\n${post.caption ?? ''}\n\nShared via Plaro'
        .trim();
    Share.share(text);
  }

  void _showBookmarkSnack(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_bookmarked ? 'Bookmarked' : 'Removed from bookmarks'),
        duration: const Duration(seconds: 1),
      ));

  void _showMoreOptions(BuildContext context, Post_feed post) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.cardTheme.color,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetHandle(),
            _OptionTile(
              icon: Icons.report_outlined,
              label: 'Report Post',
              color: Colors.red,
              onTap: () {
                Navigator.pop(context);
                _confirmAction(context, 'Report Post',
                    'Report this post for review?', 'Report', Colors.red, () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Post reported')),
                      );
                    });
              },
            ),
            _OptionTile(
              icon: Icons.block_outlined,
              label: 'Block User',
              color: Colors.orange,
              onTap: () {
                Navigator.pop(context);
                _confirmAction(
                    context,
                    'Block User',
                    'Block ${post.username ?? 'this user'}?',
                    'Block',
                    Colors.red, () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User blocked')),
                  );
                });
              },
            ),
            _OptionTile(
              icon: Icons.link_outlined,
              label: 'Copy Link',
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link copied')),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmAction(BuildContext context, String title, String body,
      String confirmLabel, Color confirmColor, VoidCallback onConfirm) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: theme.cardTheme.color,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: Text(confirmLabel, style: TextStyle(color: confirmColor)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (all private, stateless where possible)
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final Post_feed post;
  final bool isPreview;
  final VoidCallback? onUserInfo;
  final VoidCallback? onMore;

  const _Header({
    required this.post,
    required this.isPreview,
    this.onUserInfo,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onUserInfo,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
        child: Row(
          children: [
            // Avatar with gradient ring
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(1.5),
              child: CircleAvatar(
                radius: 18,
                backgroundImage: post.profile_pic != null
                    ? CachedNetworkImageProvider(post.profile_pic!)
                    : const AssetImage('assets/plaro_logo.png') as ImageProvider,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.username ?? 'Unknown',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _timeAgo(post.created_at),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withOpacity(0.38),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (!isPreview && post.post_id != null) ...[
              PostRankedByIcon(postId: post.post_id!),
              PostStarRatingIcon(postId: post.post_id!),
            ],
            if (!isPreview &&
                post.user_id != null &&
                post.user_id!.isNotEmpty)
              FollowButton(
                key: ValueKey('follow_${post.user_id}'),
                targetUserId: post.user_id!,
                compact: true,
              ),
            IconButton(
              icon: Icon(Icons.more_horiz,
                  color: theme.colorScheme.onSurface.withOpacity(0.3),
                  size: 20),
              onPressed: onMore,
              splashRadius: 18,
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final Post_feed post;
  const _Title({required this.post});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Text(
        post.title!,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          height: 1.3,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _ContentText extends StatelessWidget {
  final String content;
  final bool expanded;
  final VoidCallback? onTap;

  const _ContentText(
      {required this.content, required this.expanded, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 4),
        child: Text(
          content,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withOpacity(0.75),
            fontSize: 13.5,
            height: 1.5,
          ),
          maxLines: expanded ? null : 3,
          overflow: expanded ? null : TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _Tags extends StatelessWidget {
  final List<String> tags;
  const _Tags({required this.tags});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: tags
            .map((tag) => Container(
          padding:
          const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.25)),
          ),
          child: Text(
            '#$tag',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ))
            .toList(),
      ),
    );
  }
}

// ─── Media section ────────────────────────────────────────────────────────────

class _MediaSection extends StatelessWidget {
  final Post_feed post;
  final PageController pageCtrl;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final bool isPreview;

  const _MediaSection({
    required this.post,
    required this.pageCtrl,
    required this.currentPage,
    required this.onPageChanged,
    required this.isPreview,
  });

  @override
  Widget build(BuildContext context) {
    final localFiles = post.localMediaFiles;
    final urls = post.media_urls ?? [];

    if (localFiles != null && localFiles.isNotEmpty) {
      return _buildLocal(context, localFiles);
    }
    if (urls.isEmpty) return const SizedBox.shrink();
    return _buildNetwork(context, urls);
  }

  Widget _buildLocal(BuildContext context, List<XFile> files) {
    return AspectRatio(
      aspectRatio: 5 / 6,
      child: PageView.builder(
        itemCount: files.length,
        controller: pageCtrl,
        itemBuilder: (_, i) {
          final f = files[i];
          return _isVideoFile(f.path)
              ? _LocalVideoPlayer(file: File(f.path))
              : ZoomableImage(
            minScale: 1,
            maxScale: 4,
            child: Image.file(File(f.path), fit: BoxFit.cover),
          );
        },
      ),
    );
  }

  Widget _buildNetwork(BuildContext context, List<String> urls) {
    final single = urls.length == 1;
    return AspectRatio(
      aspectRatio: 5 / 6,
      child: Stack(
        children: [
          PageView.builder(
            controller: pageCtrl,
            itemCount: urls.length,
            onPageChanged: onPageChanged,
            itemBuilder: (ctx, i) {
              final url = urls[i];
              return ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: PostDoubleTapLike(
                  postId: post.post_id ?? '',
                  isliked: post.isliked,
                  child: _isVideoUrl(url)
                      ? VideoPlayerWidget(videoUrl: url)
                      : GestureDetector(
                    onTap: isPreview
                        ? null
                        : () {
                      final imgs =
                      urls.where((u) => !_isVideoUrl(u)).toList();
                      final idx = imgs.indexOf(url);
                      FullScreenImageViewer.show(
                        ctx,
                        imageUrls: imgs,
                        initialIndex: idx < 0 ? 0 : idx,
                      );
                    },
                    child: ZoomableImage(
                      minScale: 1,
                      maxScale: 4,
                      child: CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        memCacheWidth: 800,
                        maxWidthDiskCache: 1000,
                        placeholder: (_, __) => Container(
                          color: Colors.black12,
                          child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.black12,
                          child: const Icon(Icons.broken_image_outlined,
                              size: 36, color: Colors.white30),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          // Page indicator — only when multiple media
          if (!single)
            Positioned(
              top: 10,
              right: 12,
              child: _MediaCounter(
                current: currentPage + 1,
                total: urls.length,
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaCounter extends StatelessWidget {
  final int current;
  final int total;
  const _MediaCounter({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$current / $total',
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─── Action bar ───────────────────────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  final Post_feed post;
  final bool isPreview;
  final bool isLiking;
  final bool bookmarked;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onBookmark;

  const _ActionBar({
    required this.post,
    required this.isPreview,
    required this.isLiking,
    required this.bookmarked,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onBookmark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = theme.colorScheme.onSurface.withOpacity(0.45);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Btn(
              icon: post.isliked
                  ? Icons.favorite_rounded
                  : Icons.favorite_outline_rounded,
              label: '${post.like_count}',
              color: post.isliked ? Colors.redAccent : dim,
              isLoading: isLiking,
              onTap: onLike,
            ),
            _Divider(),
            _Btn(
              icon: Icons.mode_comment_outlined,
              label: '${post.comment_count}',
              color: dim,
              onTap: onComment,
            ),
            _Divider(),
            _Btn(
              icon: Icons.reply_rounded,
              label: '${post.share_count ?? 0}',
              color: dim,
              onTap: onShare,
            ),
            _Divider(),
            _Btn(
              icon: bookmarked
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_outline_rounded,
              label: '',
              color: bookmarked ? theme.colorScheme.primary : dim,
              onTap: onBookmark,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 18,
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.07),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback? onTap;

  const _Btn({
    required this.icon,
    required this.label,
    required this.color,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 1.8, color: color),
              )
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.elasticOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(icon, color: color, size: 19,
                    key: ValueKey(icon)),
              ),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 5),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  label,
                  key: ValueKey(label),
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Misc ─────────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OptionTile(
      {required this.icon,
        required this.label,
        required this.color,
        required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: color, size: 22),
      title: Text(label,
          style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      onTap: onTap,
      dense: true,
    );
  }
}