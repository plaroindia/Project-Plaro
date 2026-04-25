// ================================================================
// notifications_page.dart  (UPDATED)
//
// Changes:
//   - Two tabs: "All" (existing behaviour) and "Pearl Offers"
//     (freelance notifications only — type == 'freelance')
//   - Freelance tile has a distinct teal icon + taps open the
//     FreelanceOfferDetailSheet bottom-sheet
//   - Pro badge shown on current user avatar in AppBar
//   - All existing routing (follow, post, byte, taiken, dm) unchanged
// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Viewmodels/notifications_provider.dart';
import '../Viewmodels/user_provider.dart';
import '../Viewmodels/pro_provider.dart';
import '../Viewmodels/freelance_provider.dart';
import '../models/post.dart';
import '../models/byte.dart';
import 'chat_page.dart';
import 'post_full_screen.dart';
import 'bytes_full_screen.dart';
import 'taiken_experience_page.dart';
import 'profile.dart';
import 'freelance_feed_page.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage>
    with SingleTickerProviderStateMixin {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final TabController _tabController;
  String? _navigatingId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).refresh();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final isPro = ref.watch(isProProvider);

    final allNotifs = state.notifications;
    final freelanceNotifs =
    allNotifs.where((n) => n.type == 'freelance').toList();
    final generalNotifs =
    allNotifs.where((n) => n.type != 'freelance').toList();
    final freelanceUnread =
        freelanceNotifs.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text(
              'Notifications',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
            ),
            if (isPro) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (state.unreadCount > 0)
            TextButton(
              onPressed: () =>
                  ref.read(notificationsProvider.notifier).markAllRead(),
              child: const Text(
                'Mark all read',
                style: TextStyle(color: Colors.blue, fontSize: 13),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.blue,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          labelStyle:
          const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            const Tab(text: 'All'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Pearl Offers'),
                  if (freelanceUnread > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00BFA5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$freelanceUnread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 0: All (non-freelance) notifications ─────────────────
          _buildList(generalNotifs, state.isLoading),

          // ── Tab 1: Pearl Offers (freelance only) ─────────────────────
          _buildFreelanceTab(freelanceNotifs, state.isLoading),
        ],
      ),
    );
  }

  // ── Tab builders ──────────────────────────────────────────────────────────

  Widget _buildList(List<AppNotification> notifs, bool isLoading) {
    if (isLoading && notifs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (notifs.isEmpty) return _buildEmpty(false);

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final today = <AppNotification>[];
    final yesterday = <AppNotification>[];
    final earlier = <AppNotification>[];

    for (final n in notifs) {
      final local = n.createdAt.toLocal();
      final day = DateTime(local.year, local.month, local.day);
      if (!day.isBefore(todayStart)) {
        today.add(n);
      } else if (!day.isBefore(yesterdayStart)) {
        yesterday.add(n);
      } else {
        earlier.add(n);
      }
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
      child: ListView(
        children: [
          if (today.isNotEmpty) ...[
            _sectionHeader('Today'),
            ...today.map(_buildTile),
          ],
          if (yesterday.isNotEmpty) ...[
            _sectionHeader('Yesterday'),
            ...yesterday.map(_buildTile),
          ],
          if (earlier.isNotEmpty) ...[
            _sectionHeader('Earlier'),
            ...earlier.map(_buildTile),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildFreelanceTab(
      List<AppNotification> notifs, bool isLoading) {
    if (isLoading && notifs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
      child: CustomScrollView(
        slivers: [
          // "Browse all offers" header banner
          SliverToBoxAdapter(
            child: _FreelanceBanner(
              onBrowse: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FreelanceFeedPage()),
              ),
            ),
          ),
          if (notifs.isEmpty)
            SliverFillRemaining(child: _buildEmpty(true))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (_, i) => _buildFreelanceTile(notifs[i]),
                childCount: notifs.length,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ── Tile builders ─────────────────────────────────────────────────────────

  Widget _buildTile(AppNotification notif) {
    // Freelance notifications never appear in the "All" tab,
    // but guard here just in case.
    if (notif.type == 'freelance') return _buildFreelanceTile(notif);

    final isUnread = !notif.isRead;
    final isNavigating = _navigatingId == notif.id;

    return InkWell(
      onTap: isNavigating ? null : () => _handleTap(notif),
      child: Container(
        color: isUnread ? Colors.blue.withOpacity(0.06) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _iconBgColor(notif.type),
                shape: BoxShape.circle,
              ),
              child: isNavigating
                  ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
                  : Icon(_iconForType(notif.type),
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isUnread
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isUnread)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(notif.body,
                      style:
                      TextStyle(fontSize: 13, color: Colors.grey[400]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(_formatTime(notif.createdAt),
                      style:
                      TextStyle(fontSize: 11, color: Colors.grey[600])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFreelanceTile(AppNotification notif) {
    final isUnread = !notif.isRead;
    final postIdStr = notif.relatedId;

    return InkWell(
      onTap: () {
        ref.read(notificationsProvider.notifier).markRead(notif.id);
        if (postIdStr != null) {
          final postId = int.tryParse(postIdStr);
          if (postId != null) {
            _openFreelanceDetail(context, postId);
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isUnread
              ? const Color(0xFF00BFA5).withOpacity(0.08)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUnread
                ? const Color(0xFF00BFA5).withOpacity(0.35)
                : Colors.transparent,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFF00BFA5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.work_outline,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        notif.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isUnread
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    if (isUnread)
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00BFA5),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  Text(notif.body,
                      style:
                      TextStyle(fontSize: 13, color: Colors.grey[400]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text(_formatTime(notif.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[600])),
                    const Spacer(),
                    Text(
                      'View offer →',
                      style: TextStyle(
                        fontSize: 12,
                        color: const Color(0xFF00BFA5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Open freelance offer detail sheet ─────────────────────────────────────

  void _openFreelanceDetail(BuildContext context, int postId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => FreelanceOfferDetailSheet(postId: postId),
    );
  }

  // ── Empty states ──────────────────────────────────────────────────────────

  Widget _buildEmpty(bool isFreelanceTab) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isFreelanceTab
                ? Icons.work_off_outlined
                : Icons.notifications_none,
            size: 64,
            color: Colors.grey[600],
          ),
          const SizedBox(height: 16),
          Text(
            isFreelanceTab
                ? 'No freelance notifications yet'
                : 'No notifications yet',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isFreelanceTab
                ? 'When someone applies to your post\nor you get matched, it shows here.'
                : 'Activity from people you follow\nwill appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          if (isFreelanceTab) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const FreelanceFeedPage()),
              ),
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Browse Offers'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00BFA5),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ── Existing tap handler (ALL original routes preserved) ──────────────────

  Future<void> _handleTap(AppNotification notif) async {
    ref.read(notificationsProvider.notifier).markRead(notif.id);

    if (notif.type == 'dm' && notif.relatedId != null) {
      await _openChat(senderId: notif.relatedId!, senderName: notif.title);
      return;
    }

    if (notif.type == 'follow' && notif.relatedId != null) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OtherProfileScreen(userId: notif.relatedId),
        ),
      );
      return;
    }

    switch (notif.relatedType) {
      case 'user':
        if (notif.relatedId != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OtherProfileScreen(userId: notif.relatedId),
            ),
          );
        }
        break;
      case 'post':
        if (notif.relatedId != null) await _openPost(notif);
        break;
      case 'byte':
        if (notif.relatedId != null) await _openByte(notif);
        break;
      case 'taiken':
        if (notif.relatedId != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  TaikenExperiencePage(taikenId: notif.relatedId!),
            ),
          );
        }
        break;
    }
  }

  Future<void> _openPost(AppNotification notif) async {
    setState(() => _navigatingId = notif.id);
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      final postIdInt = int.tryParse(notif.relatedId!);
      if (postIdInt == null) return;

      final rows = await _supabase
          .from('post')
          .select('''
            post_id, user_id, title, content, media_urls, tags, domain,
            like_count, comment_count, share_count, is_published,
            created_at, educational_value,
            user_profiles!inner(username, profile_pic)
          ''')
          .eq('post_id', postIdInt)
          .eq('is_published', true)
          .limit(1);

      if ((rows as List).isEmpty) {
        _showContentGoneSnackbar('post');
        return;
      }

      final row = rows.first as Map<String, dynamic>;
      bool isLiked = false;
      if (currentUserId != null) {
        final likeRow = await _supabase
            .from('post_likes')
            .select('post_id')
            .eq('post_id', postIdInt)
            .eq('user_id', currentUserId)
            .maybeSingle();
        isLiked = likeRow != null;
      }

      final post = Post_feed.fromMap({
        ...row,
        'post_id': row['post_id'].toString(),
        'username': row['user_profiles']['username'],
        'profile_pic': row['user_profiles']['profile_pic'],
        'isliked': isLiked,
        'post_comments': [],
      });

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PostFullScreen(post: post)),
      );
    } catch (e) {
      debugPrint('[NotificationsPage] _openPost error: $e');
      _showContentGoneSnackbar('post');
    } finally {
      if (mounted) setState(() => _navigatingId = null);
    }
  }

  Future<void> _openByte(AppNotification notif) async {
    setState(() => _navigatingId = notif.id);
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      final byteIdInt = int.tryParse(notif.relatedId!);
      if (byteIdInt == null) return;

      final rows = await _supabase
          .from('bytes')
          .select('*, user_profiles!bytes_user_id_fkey(username, profile_pic)')
          .eq('byte_id', byteIdInt)
          .limit(1);

      if ((rows as List).isEmpty) {
        _showContentGoneSnackbar('byte');
        return;
      }

      final row = rows.first as Map<String, dynamic>;
      final userProfile = row['user_profiles'] as Map<String, dynamic>?;

      bool isLiked = false;
      if (currentUserId != null) {
        final likeRow = await _supabase
            .from('byte_likes')
            .select('byte_id')
            .eq('byte_id', byteIdInt)
            .eq('user_id', currentUserId)
            .maybeSingle();
        isLiked = likeRow != null;
      }

      final byte = Byte.fromJson({
        ...row,
        'byte_id': row['byte_id'].toString(),
        'username': userProfile?['username'],
        'profile_pic': userProfile?['profile_pic'],
        'isliked': isLiked,
      });

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              BytesFullScreen(bytes: [byte], initialIndex: 0),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationsPage] _openByte error: $e');
      _showContentGoneSnackbar('byte');
    } finally {
      if (mounted) setState(() => _navigatingId = null);
    }
  }

  Future<void> _openChat({
    required String senderId,
    required String senderName,
  }) async {
    try {
      final profile = await ref
          .read(userProfileRepositoryProvider)
          .getUserProfile(senderId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IndividualChatPage(
            receiver: profile,
            receiverId: senderId,
            receiverName: profile?.username ?? senderName,
            receiverProfilePic: profile?.profilePic,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IndividualChatPage(
            receiver: null,
            receiverId: senderId,
            receiverName: senderName,
          ),
        ),
      );
    }
  }

  void _showContentGoneSnackbar(String type) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('This $type is no longer available.'),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Visual helpers ────────────────────────────────────────────────────────

  IconData _iconForType(String type) {
    switch (type) {
      case 'follow':       return Icons.person_add;
      case 'new_post':     return Icons.article_outlined;
      case 'new_byte':     return Icons.play_circle_outline;
      case 'new_taiken':   return Icons.auto_stories_outlined;
      case 'rating':       return Icons.star;
      case 'points':       return Icons.bolt;
      case 'match':        return Icons.work_outline;
      case 'dm':           return Icons.chat_bubble_outline;
      case 'freelance':    return Icons.work_outline;
      default:             return Icons.notifications;
    }
  }

  Color _iconBgColor(String type) {
    switch (type) {
      case 'follow':       return Colors.blue;
      case 'new_post':     return Colors.indigo;
      case 'new_byte':     return Colors.deepOrange;
      case 'new_taiken':   return Colors.teal;
      case 'rating':       return Colors.amber[700]!;
      case 'points':       return Colors.purple;
      case 'match':        return Colors.green[700]!;
      case 'dm':           return Colors.blueGrey;
      case 'freelance':    return const Color(0xFF00BFA5);
      default:             return Colors.grey[700]!;
    }
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${local.day}/${local.month}/${local.year}';
  }
}

// ════════════════════════════════════════════════════════════════════════════
// _FreelanceBanner — top card in Pearl Offers tab
// ════════════════════════════════════════════════════════════════════════════

class _FreelanceBanner extends StatelessWidget {
  final VoidCallback onBrowse;
  const _FreelanceBanner({required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00897B), Color(0xFF004D40)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.work_outline, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pearl Offers',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Freelance tasks matched to your rank',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.8), fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onBrowse,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Browse',
                style: TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// FreelanceOfferDetailSheet — bottom sheet opened from notification tap
// ════════════════════════════════════════════════════════════════════════════

class FreelanceOfferDetailSheet extends ConsumerStatefulWidget {
  final int postId;
  const FreelanceOfferDetailSheet({super.key, required this.postId});

  @override
  ConsumerState<FreelanceOfferDetailSheet> createState() =>
      _FreelanceOfferDetailSheetState();
}

class _FreelanceOfferDetailSheetState
    extends ConsumerState<FreelanceOfferDetailSheet> {
  FreelancePost? _post;
  bool _loading = true;
  String? _error;
  final _msgCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userId =
          Supabase.instance.client.auth.currentUser?.id ?? '';
      final rows = await Supabase.instance.client.rpc(
        'get_freelance_feed',
        params: {'p_user_id': userId, 'p_limit': 50, 'p_offset': 0},
      ) as List;

      final match = rows.cast<Map<String, dynamic>>().firstWhere(
            (r) => (r['post_id'] as num).toInt() == widget.postId,
        orElse: () => {},
      );

      if (mounted) {
        setState(() {
          _post = match.isNotEmpty
              ? FreelancePost.fromRpc(match)
              : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
            child: Text('Could not load offer',
                style: TextStyle(color: Colors.grey[400])))
            : _post == null
            ? Center(
            child: Text('Offer not found',
                style: TextStyle(color: Colors.grey[400])))
            : _buildContent(scrollCtrl),
      ),
    );
  }

  Widget _buildContent(ScrollController ctrl) {
    final post = _post!;
    return ListView(
      controller: ctrl,
      padding: const EdgeInsets.all(20),
      children: [
        // Handle
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        // Rank + Pro badges
        Row(children: [
          _RankBadge(rank: post.freelanceMinRank),
          if (post.requiresPro) ...[
            const SizedBox(width: 6),
            _ProBadge(),
          ],
          const Spacer(),
          if (post.freelanceBudget != null)
            Text('💰 ${post.freelanceBudget}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white)),
        ]),
        const SizedBox(height: 14),
        Text(post.title,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        if (post.content != null) ...[
          const SizedBox(height: 10),
          Text(post.content!,
              style: TextStyle(fontSize: 14, color: Colors.grey[300])),
        ],
        if (post.freelanceDeadline != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(
              'Deadline: ${_fmt(post.freelanceDeadline!)}',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Icon(Icons.person_outline, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text('Posted by ${post.authorUsername}',
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        ]),
        const SizedBox(height: 24),
        if (post.alreadyApplied)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle_outline,
                  color: Colors.green, size: 18),
              SizedBox(width: 8),
              Text('You have already applied to this offer',
                  style: TextStyle(color: Colors.green, fontSize: 13)),
            ]),
          )
        else if (!post.isEligible)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border:
              Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.lock_outline,
                  color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  post.requiresPro
                      ? 'Requires Pro subscription to apply'
                      : 'Requires ${post.freelanceMinRank} rank to apply',
                  style: const TextStyle(
                      color: Colors.orange, fontSize: 13),
                ),
              ),
            ]),
          )
        else ...[
            TextField(
              controller: _msgCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Why are you a good fit for this task?',
                hintStyle: TextStyle(color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final error = await ref
                      .read(freelanceFeedProvider.notifier)
                      .apply(
                    postId: post.postId,
                    message: _msgCtrl.text,
                  );
                  if (error != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(error)),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00BFA5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Submit Application',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        const SizedBox(height: 20),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Small shared badge widgets ────────────────────────────────────────────────

class _RankBadge extends StatelessWidget {
  final String rank;
  const _RankBadge({required this.rank});

  Color get _color {
    switch (rank.toLowerCase()) {
      case 'intermediate': return Colors.blue;
      case 'advanced':     return Colors.purple;
      case 'expert':       return Colors.orange;
      case 'master':       return Colors.red;
      default:             return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _color),
    ),
    child: Text(
      rank.toUpperCase(),
      style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w700),
    ),
  );
}

class _ProBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.amber.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.amber),
    ),
    child: const Text(
      '⭐ PRO',
      style: TextStyle(
          color: Colors.amber,
          fontSize: 11,
          fontWeight: FontWeight.w700),
    ),
  );
}