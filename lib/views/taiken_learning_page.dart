// =============================================================================
// taiken_learning_page.dart  — FIXED v2
//
// Fixes vs previous version:
//   1. _toPostFeed now passes userId, commentCount, created_at and tags from
//      LearningFeedItem so PostCard has everything it needs for like/comment/
//      ownership checks. Previously user_id was hardcoded to '' which broke
//      delete/edit guards, and created_at was null which caused PostCard
//      timestamp to crash.
//   2. injectPosts call moved to a proper provider listener with listenManual
//      (was already there) but now passes fully-populated Post_feed objects.
//   3. PostCard is rendered with isPreview: false so all action buttons
//      (like, comment, share) are visible and wired up.
//   4. BytesFullScreen receives a fresh list so index lookup always succeeds.
// =============================================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/byte.dart';
import '../models/post.dart';
import '../Viewmodels/post_feed_provider.dart';
import '../Viewmodels/taiken_learning_feed_provider.dart';
import 'bytes_full_screen.dart';
import 'widgets/post_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers — convert LearningFeedItem → real model objects
// ─────────────────────────────────────────────────────────────────────────────

/// Converts a LearningFeedItem to Post_feed with all fields populated so
/// PostCard's like/comment/ownership logic works correctly.
Post_feed _toPostFeed(LearningFeedItem item) => Post_feed(
  post_id:       item.id,
  // FIX: pass real userId (not hardcoded '') so PostCard ownership check works
  user_id:       item.userId,
  username:      item.username,
  profile_pic:   item.profilePic,
  title:         item.title,
  content:       item.body,
  media_urls:    item.mediaUrls.isNotEmpty ? item.mediaUrls : null,
  like_count:    item.likeCount,
  // FIX: pass real commentCount
  comment_count: item.commentCount,
  share_count:   0,
  isliked:       false,
  commentsList:  [],
  tags:          item.tags,
  // FIX: pass real created_at so PostCard timestamp doesn't crash
  created_at:    item.createdAt ?? DateTime.now(),
);

Byte _toByte(LearningFeedItem item) => Byte(
  byteId:       item.id,
  userId:       item.userId,
  videoUrl:     item.videoUrl ?? '',
  thumbnailUrl: item.thumbnailUrl,
  caption:      item.body,
  likeCount:    item.likeCount,
  commentCount: item.commentCount,
  shareCount:   0,
  createdAt:    item.createdAt ?? DateTime.now(),
  updatedAt:    item.createdAt ?? DateTime.now(),
  username:     item.username,
  profilePic:   item.profilePic,
  isliked:      false,
);

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class TaikenLearningPage extends ConsumerStatefulWidget {
  final String taikenId;
  final String domain;
  final VoidCallback onDone;
  /// Optional: show the question text above the feed so user knows what to study
  final String? questionPreview;

  const TaikenLearningPage({
    super.key,
    required this.taikenId,
    required this.domain,
    required this.onDone,
    this.questionPreview,
  });

  @override
  ConsumerState<TaikenLearningPage> createState() =>
      _TaikenLearningPageState();
}

class _TaikenLearningPageState extends ConsumerState<TaikenLearningPage> {
  final ScrollController _scroll = ScrollController();
  Timer? _secondsTicker;

  ({String taikenId, String domain}) get _key =>
      (taikenId: widget.taikenId, domain: widget.domain);

  @override
  void initState() {
    super.initState();

    // Tick seconds into the provider for readiness tracking
    _secondsTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      ref.read(taikenLearningFeedProvider(_key).notifier).recordSeconds(1);
    });

    _scroll.addListener(_onScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taikenLearningFeedProvider(_key).notifier).load(refresh: true);
    });

    // When feed loads, inject posts into postFeedProvider so PostCard can
    // find them for likes / comments via toggleLike / loadComments.
    ref.listenManual(taikenLearningFeedProvider(_key), (prev, next) {
      if (next.isLoading) return;
      final posts = next.items
          .where((i) => i.type == LearningItemType.post)
          .map(_toPostFeed)
          .toList();
      if (posts.isNotEmpty) {
        ref.read(postFeedProvider.notifier).injectPosts(posts);
      }
    });
  }

  @override
  void dispose() {
    _secondsTicker?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent * 0.8) {
      ref.read(taikenLearningFeedProvider(_key).notifier).load();
    }
  }

  void _handleDone() {
    widget.onDone();
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(taikenLearningFeedProvider(_key));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _DomainBanner(
            domain: widget.domain,
            questionPreview: widget.questionPreview,
          ),
          Expanded(
            child: feedState.isLoading && feedState.items.isEmpty
                ? _buildShimmer()
                : feedState.items.isEmpty
                ? _buildEmptyState()
                : _buildFeed(feedState),
          ),
          _ReadinessBar(
            bytesWatched: feedState.bytesWatched,
            postsRead:    feedState.postsRead,
            secondsSpent: feedState.secondsSpent,
            isReady:      feedState.isReadyToReturn,
            onReturn:     feedState.isReadyToReturn ? _handleDone : null,
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: const Color(0xFF0A0A0F),
    foregroundColor: Colors.white,
    elevation: 0,
    leading: IconButton(
      icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20),
      onPressed: () => Navigator.of(context).pop(),
    ),
    title: Text(
      'Study Phase',
      style: TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
    ),
    actions: [
      Container(
        margin: EdgeInsets.only(right: 12),
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_rounded, color: Colors.orange, size: 14),
            SizedBox(width: 4),
            Text('Learn',
                style: TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    ],
  );

  // ── Feed ──────────────────────────────────────────────────────────────────

  Widget _buildFeed(LearningFeedState feedState) {
    // Build the full byte list upfront so BytesFullScreen gets all bytes
    final allBytes = feedState.items
        .where((i) => i.type == LearningItemType.byte)
        .map(_toByte)
        .toList();

    return RefreshIndicator(
      onRefresh: () => ref
          .read(taikenLearningFeedProvider(_key).notifier)
          .load(refresh: true),
      color: Colors.orange,
      backgroundColor: const Color(0xFF1A1A2E),
      child: ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.only(bottom: 8),
        itemCount: feedState.items.length + (feedState.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= feedState.items.length) {
            return Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: CircularProgressIndicator(
                    color: Colors.orange, strokeWidth: 2),
              ),
            );
          }

          final item = feedState.items[index];

          if (item.type == LearningItemType.post) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: _PostReadTracker(
                item: item,
                onRead: () => ref
                    .read(taikenLearningFeedProvider(_key).notifier)
                    .recordPostRead(),
                // PostCard is rendered with isPreview: false so all action
                // buttons (like, comment, share) are active. The post was
                // injected into postFeedProvider above, so toggleLike and
                // loadComments operate on the real DB row.
                child: PostCard(
                  post: _toPostFeed(item),
                  isPreview: false,
                ),
              ),
            );
          } else {
            // Byte → thumbnail card → taps into full BytesFullScreen viewer
            final byteIndex =
            allBytes.indexWhere((b) => b.byteId == item.id);
            return Padding(
              padding:
              EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: _ByteThumbnailCard(
                item: item,
                onTap: () {
                  // Mark as watched before pushing viewer
                  ref
                      .read(taikenLearningFeedProvider(_key).notifier)
                      .recordByteWatched();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BytesFullScreen(
                        bytes: allBytes,
                        initialIndex: byteIndex >= 0 ? byteIndex : 0,
                      ),
                    ),
                  );
                },
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildShimmer() => ListView.builder(
    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    itemCount: 5,
    itemBuilder: (_, __) => Padding(
        padding: EdgeInsets.only(bottom: 12),
        child: _ShimmerCard()),
  );

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.menu_book_rounded,
              color: Colors.orange, size: 36),
        ),
        SizedBox(height: 16),
        Text('No content yet for this domain',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text('You can return to the mission anytime.',
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        SizedBox(height: 32),
        ElevatedButton(
          onPressed: _handleDone,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
                horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          child: Text('Return to Mission →',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Post read tracker — fires onRead after 5 s of being visible
// ─────────────────────────────────────────────────────────────────────────────

class _PostReadTracker extends StatefulWidget {
  final LearningFeedItem item;
  final VoidCallback onRead;
  final Widget child;
  const _PostReadTracker({
    required this.item,
    required this.onRead,
    required this.child,
  });

  @override
  State<_PostReadTracker> createState() => _PostReadTrackerState();
}

class _PostReadTrackerState extends State<_PostReadTracker> {
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted && !_fired) {
        _fired = true;
        widget.onRead();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─────────────────────────────────────────────────────────────────────────────
// Byte thumbnail card
// ─────────────────────────────────────────────────────────────────────────────

class _ByteThumbnailCard extends StatelessWidget {
  final LearningFeedItem item;
  final VoidCallback onTap;
  const _ByteThumbnailCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: SizedBox(
                width: 100,
                height: 110,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.thumbnailUrl != null
                        ? CachedNetworkImage(
                      imageUrl: item.thumbnailUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: Colors.grey[900]),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[900],
                        child: Icon(Icons.videocam_rounded,
                            color: Colors.white24),
                      ),
                    )
                        : Container(
                      color: Colors.grey[900],
                      child: Icon(Icons.videocam_rounded,
                          color: Colors.white24),
                    ),
                    Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('BYTE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.body != null)
                      Text(
                        item.body!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4),
                      ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor: Colors.grey[800],
                          backgroundImage: item.profilePic != null
                              ? CachedNetworkImageProvider(item.profilePic!)
                              : null,
                          child: item.profilePic == null
                              ? Text(
                            item.username
                                .substring(0, 1)
                                .toUpperCase(),
                            style: TextStyle(
                                color: Colors.white, fontSize: 9),
                          )
                              : null,
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            item.username,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11),
                          ),
                        ),
                        Icon(Icons.favorite_rounded,
                            color: Colors.grey[600], size: 12),
                        SizedBox(width: 3),
                        Text('${item.likeCount}',
                            style: TextStyle(
                                color: Colors.grey[600], fontSize: 11)),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Domain banner — also shows optional question preview
// ─────────────────────────────────────────────────────────────────────────────

class _DomainBanner extends StatelessWidget {
  final String domain;
  final String? questionPreview;
  const _DomainBanner({required this.domain, this.questionPreview});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.orange.withOpacity(0.15),
            Colors.deepOrange.withOpacity(0.08),
          ],
        ),
        border:
        Border(bottom: BorderSide(color: Colors.orange.withOpacity(0.2))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.lightbulb_rounded,
                color: Colors.orange, size: 18),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Before you continue, review these:',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text(
                  domain.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(
                      color: Colors.orange[300],
                      fontSize: 11,
                      letterSpacing: 1.0),
                ),
                if (questionPreview != null) ...[
                  SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.orange.withOpacity(0.2)),
                    ),
                    child: Text(
                      questionPreview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 12,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Readiness bottom bar
// ─────────────────────────────────────────────────────────────────────────────

class _ReadinessBar extends StatelessWidget {
  final int bytesWatched;
  final int postsRead;
  final int secondsSpent;
  final bool isReady;
  final VoidCallback? onReturn;

  const _ReadinessBar({
    required this.bytesWatched,
    required this.postsRead,
    required this.secondsSpent,
    required this.isReady,
    required this.onReturn,
  });

  @override
  Widget build(BuildContext context) {
    final byteP = (bytesWatched * 0.4).clamp(0.0, 0.4);
    final postP = (postsRead    * 0.4).clamp(0.0, 0.4);
    final timeP = (secondsSpent / 10 * 0.2).clamp(0.0, 0.2);
    final total = (byteP + postP + timeP).clamp(0.0, 1.0);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F1A),
        border:
        Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatChip(
                  icon: Icons.videocam_rounded,
                  label:
                  '$bytesWatched Byte${bytesWatched != 1 ? 's' : ''}',
                  color: Colors.blue),
              SizedBox(width: 12),
              _StatChip(
                  icon: Icons.article_rounded,
                  label: '$postsRead Post${postsRead != 1 ? 's' : ''}',
                  color: Colors.purple),
              SizedBox(width: 12),
              _StatChip(
                  icon: Icons.timer_rounded,
                  label: '${secondsSpent}s',
                  color: Colors.teal),
            ],
          ),
          SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total,
              minHeight: 5,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                  isReady ? Colors.green : Colors.orange),
            ),
          ),
          SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onReturn,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                isReady ? Colors.green[600] : Colors.grey[800],
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      isReady
                          ? Icons.arrow_forward_rounded
                          : Icons.lock_rounded,
                      size: 18),
                  SizedBox(width: 8),
                  Text(
                    isReady
                        ? 'Return to Mission →'
                        : 'Watch a byte or read a post to unlock',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerCard extends StatefulWidget {
  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
    _anim = Tween(begin: -1.5, end: 2.5)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        height: 110,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment(_anim.value, 0),
            end: Alignment(_anim.value + 1.0, 0),
            colors: const [
              Color(0xFF1A1A2E),
              Color(0xFF252540),
              Color(0xFF1A1A2E),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}