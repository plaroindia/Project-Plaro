import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'set_profile.dart';
import '../Viewmodels/setProfileProvider.dart';
import '../Viewmodels/auth_provider.dart';
import '../Viewmodels/user_feed_provider.dart';
import '../Viewmodels/follow_provider.dart';
import '../models/byte.dart';
import '../models/post.dart';
import '../models/taiken.dart';
import '../models/user_profile.dart';
import '../views/foll_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/lightbox_overlay.dart';
import '../views/post_full_screen.dart' as post_screen;
import '../views/bytes_full_screen.dart';
import 'widgets/follow_button.dart';
import '../Viewmodels/post_rating_provider.dart';
import 'taiken_experience_page.dart';
import 'chat_page.dart';

// ── Provider: fetch taikens created by a specific user ───────────────────────
final userCreatedTaikensProvider =
FutureProvider.family<List<Taiken>, String>((ref, userId) async {
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('taikens')
      .select('*, user_profiles!taikens_creator_id_fkey(username, profile_pic)')
      .eq('creator_id', userId)
      .order('created_at', ascending: false);
  return (response as List).map((j) {
    final map = j as Map<String, dynamic>;
    final creatorProfile = map['user_profiles'] as Map<String, dynamic>?;
    return Taiken.fromJson({
      ...map,
      if (creatorProfile != null) ...{
        'creator_username': creatorProfile['username'],
        'creator_profile_pic': creatorProfile['profile_pic'],
      },
    });
  }).toList();
});

// ── Separate provider for OTHER users' profiles (never pollutes own profile) ──
final otherUserProfileProvider =
FutureProvider.family<UserProfile?, String>((ref, userId) async {
  final supabase = Supabase.instance.client;
  final response = await supabase.from('user_profiles').select('''
      *,
      user_profile_rank(
        total_points,
        rank_level,
        consistency_score,
        authenticity_score,
        contribution_score,
        freelance_eligible,
        verified_educator
      )
    ''').eq('user_id', userId).maybeSingle();
  if (response == null) return null;
  final dynamic rankData = response['user_profile_rank'];
  final Map<String, dynamic>? rankMap = rankData is List
      ? (rankData.isNotEmpty ? rankData.first as Map<String, dynamic> : null)
      : rankData as Map<String, dynamic>?;
  final profileData = {
    ...response,
    if (rankMap != null) ...{
      'total_points': rankMap['total_points'],
      'rank_level': rankMap['rank_level'],
      'consistency_score': rankMap['consistency_score'],
      'authenticity_score': rankMap['authenticity_score'],
      'contribution_score': rankMap['contribution_score'],
      'freelance_eligible': rankMap['freelance_eligible'],
      'verified_educator': rankMap['verified_educator'],
    }
  };
  return UserProfile.fromJson(profileData);
});

// ── Live follow-count provider — always reads fresh from DB ──────────────────
// BUG FIX: The previous code showed stale follower/following counts on other
// users' profiles because it relied on the cached DB column values that are
// only updated server-side. This provider reads the actual follow table counts
// directly so they stay accurate after follow/unfollow actions.
final liveFollowCountsProvider =
FutureProvider.family<Map<String, int>, String>((ref, userId) async {
  final supabase = Supabase.instance.client;

  // Count rows in the follows table directly — these are always accurate
  final followersRes = await supabase
      .from('follows')
      .select('follower_id')
      .eq('following_id', userId);

  final followingRes = await supabase
      .from('follows')
      .select('following_id')
      .eq('follower_id', userId);

  return {
    'followers': (followersRes as List).length,
    'following': (followingRes as List).length,
  };
});

class OtherProfileScreen extends ConsumerStatefulWidget {
  final String? userId;
  final UserProfile? initialUserData;

  const OtherProfileScreen({super.key, this.userId, this.initialUserData});

  @override
  ConsumerState<OtherProfileScreen> createState() => _OtherProfileScreen();
}

class _OtherProfileScreen extends ConsumerState<OtherProfileScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool _isInitialized = false;
  late TabController _tabController;
  final ScrollController _postsScrollController = ScrollController();
  final ScrollController _toastsScrollController = ScrollController();
  final ScrollController _bytesScrollController = ScrollController();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final Set<int> _loadedTabs = {0};

  bool get isOwnProfile =>
      widget.userId == null ||
          widget.userId == Supabase.instance.client.auth.currentUser?.id;

  String get targetUserId =>
      widget.userId ?? Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _postsScrollController.addListener(_onPostsScroll);
    _bytesScrollController.addListener(_onBytesScroll);

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _tabController.addListener(_onTabChanged);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _postsScrollController.dispose();
    _toastsScrollController.dispose();
    _bytesScrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(OtherProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      ref.read(profileFeedProvider.notifier).clearFeed();
      if (!isOwnProfile) ref.read(followProvider.notifier).clear();

      setState(() {
        _isInitialized = false;
        _loadedTabs.clear();
        _tabController.index = 0;
      });

      _fadeController.reset();
      _loadUserProfile();
      _fadeController.forward();
    }
  }

  void _onTabChanged() {
    final currentTab = _tabController.index;

    if (!_loadedTabs.contains(currentTab)) {
      _loadedTabs.add(currentTab);
      _preloadTabContent(currentTab);
    }

    final nextTab = (currentTab + 1) % 3;
    if (!_loadedTabs.contains(nextTab)) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_loadedTabs.contains(nextTab)) {
          _loadedTabs.add(nextTab);
          _preloadTabContent(nextTab);
        }
      });
    }
  }

  void _preloadTabContent(int tabIndex) {
    final notifier = ref.read(profileFeedProvider.notifier);

    switch (tabIndex) {
      case 0:
        notifier.loadUserPosts(targetUserId);
        break;
      case 1:
        notifier.loadUserBytes(targetUserId);
        break;
      case 2:
        ref.invalidate(userCreatedTaikensProvider(targetUserId));
        break;
    }
  }

  void _onPostsScroll() {
    if (_postsScrollController.position.pixels >=
        _postsScrollController.position.maxScrollExtent - 300) {
      ref.read(profileFeedProvider.notifier).loadMoreUserPosts(targetUserId);
    }
  }

  void _onBytesScroll() {
    if (_bytesScrollController.position.pixels >=
        _bytesScrollController.position.maxScrollExtent - 300) {
      ref.read(profileFeedProvider.notifier).loadMoreUserBytes(targetUserId);
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      if (isOwnProfile) {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await ref.read(setProfileProvider.notifier).getUserProfile(user.id);
          await _loadVisibleTabContent();
        }
      } else {
        await _loadVisibleTabContent();
      }
      setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Error loading profile: $e');
      setState(() => _isInitialized = true);
    }
  }

  Future<void> _loadVisibleTabContent() async {
    _preloadTabContent(_tabController.index);
  }

  Future<void> _refreshProfile() async {
    _fadeController.reset();
    setState(() => _isInitialized = false);
    if (!isOwnProfile) {
      ref.invalidate(otherUserProfileProvider(targetUserId));
      // BUG FIX: Also invalidate live counts on refresh
      ref.invalidate(liveFollowCountsProvider(targetUserId));
    }
    await ref
        .read(profileFeedProvider.notifier)
        .refreshUserContent(targetUserId);
    await _loadUserProfile();
    _fadeController.forward();
  }

  void _openChat() {
    if (isOwnProfile) return;

    // Read the already-loaded profile from the provider (it's on screen, so
    // it's guaranteed to be in cache — no extra network call needed).
    final profile = ref
        .read(otherUserProfileProvider(targetUserId))
        .valueOrNull;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IndividualChatPage(
          receiver: profile,
          receiverId: targetUserId,
          receiverName:
              profile?.username ??
              widget.initialUserData?.username ??
              'User',
          receiverProfilePic:
              profile?.profilePic ??
              widget.initialUserData?.profilePic,
        ),
      ),
    );
  }

  Map<String, dynamic> _getRankInfo(String rankLevel) {
    switch (rankLevel.toLowerCase()) {
      case 'beginner':
        return {
          'color': Colors.grey,
          'icon': Icons.star_border,
          'label': 'Newbie',
          'gradient': [Colors.grey.shade700, Colors.grey.shade500],
        };
      case 'intermediate':
        return {
          'color': const Color(0xFFCD7F32),
          'icon': Icons.star_half,
          'label': 'Bronze',
          'gradient': [const Color(0xFFCD7F32), const Color(0xFFE8A045)],
        };
      case 'advanced':
        return {
          'color': const Color(0xFFC0C0C0),
          'icon': Icons.star,
          'label': 'Silver',
          'gradient': [const Color(0xFF9E9E9E), const Color(0xFFE0E0E0)],
        };
      case 'expert':
        return {
          'color': const Color(0xFFFFD700),
          'icon': Icons.stars,
          'label': 'Gold',
          'gradient': [const Color(0xFFFFD700), const Color(0xFFFFA000)],
        };
      case 'master':
        return {
          'color': const Color(0xFF9C27B0),
          'icon': Icons.workspace_premium,
          'label': 'Master',
          'gradient': [const Color(0xFF7B1FA2), const Color(0xFFCE93D8)],
        };
      default:
        return {
          'color': Colors.grey,
          'icon': Icons.star_border,
          'label': 'Newbie',
          'gradient': [Colors.grey.shade700, Colors.grey.shade500],
        };
    }
  }

  int _getNextRankThreshold(String currentRank) {
    switch (currentRank.toLowerCase()) {
      case 'beginner':
        return 1000;
      case 'intermediate':
        return 50000;
      case 'advanced':
        return 1000000;
      default:
        return 0;
    }
  }

  String _formatPoints(int points) {
    if (points >= 1000000) {
      return '${(points / 1000000).toStringAsFixed(1)}M';
    } else if (points >= 1000) {
      return '${(points / 1000).toStringAsFixed(1)}K';
    }
    return points.toString();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final authState = ref.watch(authStateProvider);
    final feedState = ref.watch(profileFeedProvider);
    final followState = isOwnProfile ? null : ref.watch(followProvider);

    final AsyncValue<UserProfile?> profileState = isOwnProfile
        ? ref.watch(setProfileProvider)
        : ref.watch(otherUserProfileProvider(targetUserId));

    if (!_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserProfile());
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        color: Colors.blue,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        displacement: 40.0,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(profileState, authState),
                    if (!_isInitialized && profileState.isLoading)
                      _buildProfileSkeleton()
                    else
                      _buildProfileInfo(profileState),
                    _buildActionButtons(followState),
                    const SizedBox(height: 8.0),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                minHeight: 76.0,   // ← was 52.0 — extra 24dp stops it snapping behind notif bar
                maxHeight: 76.0,
                child: _buildTabBar(feedState),
              ),
            ),
          ],
          body: Stack(
            children: [
              TabBarView(
                controller: _tabController,
                physics: const BouncingScrollPhysics(),
                children: [
                  _buildPostsTab(feedState),
                  _buildBytesTab(feedState),
                  _buildTaikensTab(),
                ],
              ),
              const LightboxOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[850]!,
      highlightColor: Colors.grey[700]!,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: 140,
                          height: 18,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 8),
                      Container(
                          width: 100,
                          height: 13,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 8),
                      Container(
                          width: 160,
                          height: 13,
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: List.generate(
                3,
                    (i) => Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14))),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AsyncValue profileState, AsyncValue authState) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
        child: Row(
          children: [
            if (!isOwnProfile)
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: Theme.of(context).colorScheme.onSurface, size: 18),
              ),
            if (!isOwnProfile) const SizedBox(width: 4),
            Expanded(
              child: profileState.when(
                data: (profile) => Text(
                  profile?.username ??
                      widget.initialUserData?.username ??
                      'Unknown User',
                  style: GoogleFonts.playwriteFrModerne(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                    shadows: const [
                      Shadow(
                        blurRadius: 10,
                        color: Colors.blue,
                        offset: Offset(1, 2),
                      )
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                loading: () => Text(
                  'Loading...',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4)),
                ),
                error: (error, stack) => Text(
                  widget.initialUserData?.username ?? 'Error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileInfo(AsyncValue profileState) {
    return profileState.when(
      data: (profile) {
        if (profile == null) return const SizedBox.shrink();
        return _buildProfileContent(profile);
      },
      loading: () => _buildProfileSkeleton(),
      error: (error, stack) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          widget.initialUserData?.username ?? 'Error loading profile',
          style: const TextStyle(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildProfileContent(UserProfile profile) {
    final rankInfo = _getRankInfo(profile.rankLevel);
    final nextThreshold = _getNextRankThreshold(profile.rankLevel);
    final progress = nextThreshold > 0
        ? (profile.totalPoints / nextThreshold).clamp(0.0, 1.0)
        : 1.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: avatar + identity ─────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(profile.profilePic),
              const SizedBox(width: 18),
              Expanded(child: _buildIdentity(profile)),
            ],
          ),

          // ── Bio section ────────────────────────────────────────
          if (profile.bio != null && profile.bio!.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildBioSection(profile.bio!),
          ],

          const SizedBox(height: 16),

          // ── Points + rank row ──────────────────────────────────
          _buildPointsAndRank(profile, rankInfo, progress, nextThreshold),

          const SizedBox(height: 14),

          // ── Stats row ─────────────────────────────────────────
          _buildStatsRow(profile),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAvatar(String? imageUrl) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.4),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CircleAvatar(
              radius: 44,
              backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                  ? CachedNetworkImageProvider(imageUrl)
                  : const AssetImage('assets/plaro_logo.png') as ImageProvider,
              backgroundColor: Theme.of(context).cardColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentity(UserProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        // Username
        Text(
          profile.username ?? widget.initialUserData?.username ?? '',
          style: const TextStyle(
            color: Color(0xFF4FC3F7),
            fontSize: 19,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),

        // Study/school — styled as a subtle pill
        if (profile.study != null && profile.study!.isNotEmpty)
          _buildInfoPill(
            icon: Icons.school_outlined,
            text: profile.study!,
            iconColor: const Color(0xFF80DEEA),
            textColor:
            Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
          ),

        const SizedBox(height: 6),

        // Role + location chips in a row
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (profile.role != null)
              _buildRoleChip(profile),
            if (profile.location != null && profile.location!.isNotEmpty)
              _buildLocationChip(profile.location!),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String text,
    required Color iconColor,
    required Color textColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: iconColor),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: textColor,
              fontSize: 12.5,
              letterSpacing: 0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildRoleChip(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.work_history_outlined,
              color: Colors.green, size: 12),
          const SizedBox(width: 4),
          Text(
            profile.role!,
            style: const TextStyle(
                color: Colors.green,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          if (isOwnProfile && profile.role == 'professional') ...[
            const SizedBox(width: 5),
            _VerifyIcon(
              isVerified: profile.isVerified ?? false,
              userId: profile.user_id ?? '',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLocationChip(String location) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border:
        Border.all(color: Colors.redAccent.withOpacity(0.28), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on_outlined,
              color: Colors.redAccent, size: 12),
          const SizedBox(width: 4),
          Text(
            location,
            style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildBioSection(String bio) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.07),
          width: 1,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.55),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                bio,
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.72),
                  fontSize: 13,
                  height: 1.55,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPointsAndRank(UserProfile profile,
      Map<String, dynamic> rankInfo, double progress, int nextThreshold) {
    final rankColor = rankInfo['color'] as Color;
    final rankGradient = rankInfo['gradient'] as List<Color>;

    return Row(
      children: [
        // Points card
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.amber.withOpacity(0.14),
                  Colors.orange.withOpacity(0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.amber.withOpacity(0.55),
                width: 1.1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.toll,
                          color: Colors.amber, size: 15),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plaro Points',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.45),
                            fontSize: 9.5,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          _formatPoints(profile.totalPoints),
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (nextThreshold > 0) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: rankColor.withOpacity(0.12),
                      valueColor: AlwaysStoppedAnimation(rankColor),
                      minHeight: 3.5,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_formatPoints(profile.totalPoints)} / ${_formatPoints(nextThreshold)} to next rank',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.38),
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(width: 14),

        // Rank ring
        SizedBox(
          width: 88,
          height: 88,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 88,
                height: 88,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  backgroundColor: rankColor.withOpacity(0.12),
                  valueColor: AlwaysStoppedAnimation(rankColor),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      rankGradient[0].withOpacity(0.15),
                      rankGradient[1].withOpacity(0.08),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: rankColor.withOpacity(0.25),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      rankInfo['icon'] as IconData,
                      color: rankColor,
                      size: 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rankInfo['label'] as String,
                      style: TextStyle(
                        color: rankColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsRow(UserProfile profile) {
    // BUG FIX: For other users, read live counts from the follows table.
    // For own profile, the setProfileProvider already returns accurate counts
    // since it's refreshed on load (the DB columns are updated server-side).
    if (!isOwnProfile) {
      final liveCountsAsync =
      ref.watch(liveFollowCountsProvider(targetUserId));

      return liveCountsAsync.when(
        data: (counts) => _buildStatItemsRow(
          profile: profile,
          followersCount: counts['followers'] ?? profile.followersCount ?? 0,
          followingCount: counts['following'] ?? profile.followingCount ?? 0,
          streakCount: profile.streakCount ?? 0,
        ),
        loading: () => _buildStatItemsRow(
          profile: profile,
          followersCount: profile.followersCount ?? 0,
          followingCount: profile.followingCount ?? 0,
          streakCount: profile.streakCount ?? 0,
        ),
        error: (_, __) => _buildStatItemsRow(
          profile: profile,
          followersCount: profile.followersCount ?? 0,
          followingCount: profile.followingCount ?? 0,
          streakCount: profile.streakCount ?? 0,
        ),
      );
    }

    return _buildStatItemsRow(
      profile: profile,
      followersCount: profile.followersCount ?? 0,
      followingCount: profile.followingCount ?? 0,
      streakCount: profile.streakCount ?? 0,
    );
  }

  Widget _buildStatItemsRow({
    required UserProfile profile,
    required int followersCount,
    required int followingCount,
    required int streakCount,
  }) {
    return Row(
      children: [
        Expanded(
          child: _buildStatItem('Followers', followersCount.toString(), profile),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStatItem('Following', followingCount.toString(), profile),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildStreakItem(streakCount),
        ),
      ],
    );
  }

  Widget _buildStreakItem(int streak) {
    final isActive = streak > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.deepOrange.withOpacity(0.08)
            : Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? Colors.deepOrange.withOpacity(0.3)
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.07),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                streak.toString(),
                style: TextStyle(
                  color: isActive
                      ? Colors.deepOrange
                      : Theme.of(context).colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                '🔥',
                style: TextStyle(
                  fontSize: 14,
                  color: isActive ? null : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Streak',
            style: TextStyle(
              color: isActive
                  ? Colors.deepOrange.withOpacity(0.8)
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(FollowState? followState) {
    if (isOwnProfile) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: _ProfileButton(
                label: 'Edit Profile',
                icon: Icons.edit_outlined,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SetProfile()),
                  ).then((_) => _refreshProfile());
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileButton(
                label: 'Stats',
                icon: Icons.bar_chart_rounded,
                onPressed: () {},
              ),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          children: [
            Expanded(
              child: FollowButton(
                targetUserId: targetUserId,
                compact: false,
                onFollowSuccess: () {
                  ref.invalidate(otherUserProfileProvider(targetUserId));
                  // BUG FIX: Refresh live counts after follow/unfollow
                  ref.invalidate(liveFollowCountsProvider(targetUserId));
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ProfileButton(
                label: 'Message',
                icon: Icons.chat_bubble_outline_rounded,
                onPressed: _openChat,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildTabBar(ProfileFeedState feedState) {
    final taikensAsync = ref.watch(userCreatedTaikensProvider(targetUserId));
    final taikensCount =
    taikensAsync.maybeWhen(data: (t) => t.length, orElse: () => 0);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 7),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          indicatorPadding: const EdgeInsets.all(4),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          labelStyle:
          const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
          unselectedLabelStyle:
          const TextStyle(fontWeight: FontWeight.w500, fontSize: 11.5),
          dividerColor: Colors.transparent,
          physics: const BouncingScrollPhysics(),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.view_array_outlined, size: 13),
                  const SizedBox(width: 4),
                  Text('Posts (${feedState.posts.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.video_library_outlined, size: 13),
                  const SizedBox(width: 4),
                  Text('Bytes (${feedState.bytes.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.school_outlined, size: 13),
                  const SizedBox(width: 4),
                  Text('Taikens ($taikensCount)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsTab(ProfileFeedState feedState) {
    final isLoading = feedState.isLoadingPosts && feedState.posts.isEmpty;
    final isEmpty = feedState.posts.isEmpty && !feedState.isLoadingPosts;

    if (isLoading) return _buildGridSkeleton();

    if (isEmpty) {
      return _buildEmptyState(
        icon: Icons.view_array_outlined,
        title: isOwnProfile ? 'No posts yet' : 'No posts to show',
        subtitle: isOwnProfile
            ? 'Your posts will appear here'
            : 'This user hasn\'t posted anything yet',
      );
    }

    return AnimatedOpacity(
      opacity: _isInitialized ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: ProfilePostsGrid(
        posts: feedState.posts,
        scrollController: _postsScrollController,
        onPostTap: (post) {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => post_screen.PostFullScreen(post: post, fromProfileFeed: true)),
          );
        },
        onLike: (postId) {
          ref.read(profileFeedProvider.notifier).togglePostLike(postId);
        },
        onDelete: isOwnProfile
            ? (postId) {
          _showDeleteConfirmation('post', () {
            ref.read(profileFeedProvider.notifier).deletePost(postId);
          });
        }
            : null,
        isLoadingMore: feedState.isLoadingMorePosts,
        hasMore: feedState.hasMorePosts,
      ),
    );
  }

  Widget _buildBytesTab(ProfileFeedState feedState) {
    final isLoading = feedState.isLoadingBytes && feedState.bytes.isEmpty;
    final isEmpty = feedState.bytes.isEmpty && !feedState.isLoadingBytes;

    if (isLoading) return _buildGridSkeleton();

    if (isEmpty) {
      return _buildEmptyState(
        icon: Icons.video_library_outlined,
        title: isOwnProfile ? 'No bytes yet' : 'No bytes to show',
        subtitle: isOwnProfile
            ? 'Your bytes will appear here'
            : 'This user hasn\'t posted any bytes yet',
      );
    }

    return AnimatedOpacity(
      opacity: _isInitialized ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: ProfileBytesGrid(
        bytes: feedState.bytes,
        scrollController: _bytesScrollController,
        onByteTap: (byte) {
          final bytes = feedState.bytes;
          final index = bytes.indexWhere((b) => b.byteId == byte.byteId);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BytesFullScreen(
                bytes: bytes,
                initialIndex: index < 0 ? 0 : index,
              ),
            ),
          );
        },
        isLoadingMore: feedState.isLoadingMoreBytes,
        hasMore: feedState.hasMoreBytes,
      ),
    );
  }

  Widget _buildTaikensTab() {
    final taikensAsync = ref.watch(userCreatedTaikensProvider(targetUserId));

    return taikensAsync.when(
      loading: () => _buildGridSkeleton(),
      error: (_, __) => _buildEmptyState(
        icon: Icons.school_outlined,
        title: 'Could not load Taikens',
        subtitle: 'Pull to refresh and try again',
      ),
      data: (taikens) {
        if (taikens.isEmpty) {
          return _buildEmptyState(
            icon: Icons.school_outlined,
            title:
            isOwnProfile ? 'No Taikens created yet' : 'No Taikens to show',
            subtitle: isOwnProfile
                ? 'Taikens you create will appear here'
                : 'This user hasn\'t created any Taikens yet',
          );
        }

        return AnimatedOpacity(
          opacity: _isInitialized ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: taikens.length,
            itemBuilder: (context, index) =>
                _buildProfileTaikenCard(taikens[index]),
          ),
        );
      },
    );
  }

  Widget _buildProfileTaikenCard(Taiken taiken) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => TaikenExperiencePage(taikenId: taiken.taikenId)),
        ),
        borderRadius: BorderRadius.circular(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                bottomLeft: Radius.circular(14),
              ),
              child: taiken.thumbnailUrl != null
                  ? CachedNetworkImage(
                imageUrl: taiken.thumbnailUrl!,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 96,
                  height: 96,
                  color: Theme.of(context).cardColor,
                  child: Icon(Icons.school_outlined,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.25),
                      size: 28),
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 96,
                  height: 96,
                  color: Theme.of(context).cardColor,
                  child: Icon(Icons.school_outlined,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.25),
                      size: 28),
                ),
              )
                  : Container(
                width: 96,
                height: 96,
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.07),
                child: Icon(Icons.school_outlined,
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withOpacity(0.4),
                    size: 28),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      taiken.title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildMiniChip(taiken.domain, Colors.blue),
                        const SizedBox(width: 5),
                        _buildMiniChip(
                          taiken.difficulty,
                          taiken.difficulty == 'beginner'
                              ? Colors.green
                              : taiken.difficulty == 'intermediate'
                              ? Colors.orange
                              : Colors.red,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(Icons.layers_outlined,
                            size: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4)),
                        const SizedBox(width: 3),
                        Text(
                          '${taiken.totalStages} stages',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.star, size: 11, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          taiken.averageRating.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.4),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: taiken.isPublished
                                ? Colors.green.withOpacity(0.13)
                                : Colors.orange.withOpacity(0.13),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            taiken.isPublished ? 'Live' : 'Draft',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: taiken.isPublished
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
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

  Widget _buildMiniChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.11),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
          color: color, fontSize: 10, fontWeight: FontWeight.w600),
    ),
  );

  Widget _buildGridSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[850]!,
      highlightColor: Colors.grey[700]!,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: 6,
          itemBuilder: (context, index) => Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 56,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.22)),
          const SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
                color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
                fontSize: 13),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(String type, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text('Delete $type',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface)),
          content: Text(
            'Are you sure you want to delete this $type? This action cannot be undone.',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.65)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5))),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
              child:
              const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(
      String label, String value, UserProfile? userProfile) {
    return GestureDetector(
      onTap: (label == 'Followers' || label == 'Following')
          ? () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FollowPage(
              userId: targetUserId,
              initialTab: label == 'Following' ? 1 : 0,
            ),
          ),
        );
      }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
            Theme.of(context).colorScheme.onSurface.withOpacity(0.07),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.45),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable pill button
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _ProfileButton({
    required this.label,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: Icon(icon, size: 15),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.07),
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        shadowColor: Colors.transparent,
        elevation: 0,
        side: BorderSide(
          color: Colors.blue.withOpacity(0.45),
          width: 1.1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: onPressed,
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate({
    required this.minHeight,
    required this.maxHeight,
    required this.child,
  });

  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight ||
        minHeight != oldDelegate.minHeight ||
        child != oldDelegate.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ProfilePostsGrid
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePostsGrid extends ConsumerWidget {
  final List<Post_feed> posts;
  final ScrollController scrollController;
  final Function(Post_feed) onPostTap;
  final Function(String) onLike;
  final Function(String)? onDelete;
  final bool isLoadingMore;
  final bool hasMore;

  const ProfilePostsGrid({
    super.key,
    required this.posts,
    required this.scrollController,
    required this.onPostTap,
    required this.onLike,
    this.onDelete,
    required this.isLoadingMore,
    required this.hasMore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(profileFeedProvider);

    return ListView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: [
        if (feedState.error != null)
          _buildErrorBannerInline(feedState.error!, ref, context),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.5,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) =>
              _buildOptimizedPostCard(posts[index], context),
        ),
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
          ),
        if (!hasMore && posts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('No more posts',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.35),
                      fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorBannerInline(
      String error, WidgetRef ref, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(error,
                  style:
                  const TextStyle(color: Colors.red, fontSize: 12))),
          IconButton(
            onPressed: () =>
                ref.read(profileFeedProvider.notifier).clearError(),
            icon: const Icon(Icons.close, color: Colors.red, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizedPostCard(Post_feed post, BuildContext context) {
    final imageUrl = post.imageUrls.isNotEmpty ? post.imageUrls[0] : '';

    return GestureDetector(
      onTap: () => onPostTap(post),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageUrl.isNotEmpty
            ? CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Theme.of(context).cardColor,
          ),
          errorWidget: (context, url, error) => Container(
            color: Theme.of(context).cardColor,
            child: Icon(Icons.broken_image,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.3)),
          ),
          memCacheWidth: 400,
          maxWidthDiskCache: 400,
        )
            : Container(
          color: Theme.of(context).cardColor,
          child: Icon(Icons.image,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.3),
              size: 36),
        ),
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
//  _VerifyIcon
// ─────────────────────────────────────────────────────────────────────────────

class _VerifyIcon extends ConsumerWidget {
  final bool isVerified;
  final String userId;

  const _VerifyIcon({required this.isVerified, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isVerified) {
      return const Tooltip(
        message: 'Verified Professional',
        child: Icon(Icons.verified, color: Colors.blue, size: 16),
      );
    }

    return GestureDetector(
      onTap: () => _showVerifyDialog(context, ref),
      child: Tooltip(
        message: 'Get Verified',
        child: Icon(
          Icons.verified_outlined,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
          size: 16,
        ),
      ),
    );
  }

  void _showVerifyDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _VerifyDialog(userId: userId),
    );
  }
}

class _VerifyDialog extends ConsumerStatefulWidget {
  final String userId;
  const _VerifyDialog({required this.userId});

  @override
  ConsumerState<_VerifyDialog> createState() => _VerifyDialogState();
}

class _VerifyDialogState extends ConsumerState<_VerifyDialog> {
  bool _loading = false;

  Future<void> _verify() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client
          .from('user_profiles')
          .update({'is_verified': true}).eq('user_id', widget.userId);

      await ref
          .read(setProfileProvider.notifier)
          .getUserProfile(widget.userId);
      ref.invalidate(otherUserProfileProvider(widget.userId));
      ref.invalidate(isVerifiedProfessionalProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account verified!'),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.verified_outlined, color: Colors.blue, size: 22),
          const SizedBox(width: 10),
          Text('Verify Account',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 17)),
        ],
      ),
      content: Text(
        'Verifying your account lets you rate educational posts as a professional.',
        style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withOpacity(0.5),
            fontSize: 13,
            height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5))),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _verify,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: _loading
              ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onSurface),
          )
              : const Text('Verify',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ProfileBytesGrid
// ─────────────────────────────────────────────────────────────────────────────

class ProfileBytesGrid extends ConsumerWidget {
  final List<Byte> bytes;
  final ScrollController scrollController;
  final Function(Byte) onByteTap;
  final bool isLoadingMore;
  final bool hasMore;

  const ProfileBytesGrid({
    super.key,
    required this.bytes,
    required this.scrollController,
    required this.onByteTap,
    required this.isLoadingMore,
    required this.hasMore,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(profileFeedProvider);

    return ListView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: [
        if (feedState.error != null)
          _buildErrorBannerInline(feedState.error!, ref, context),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.9,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: bytes.length,
          itemBuilder: (context, index) =>
              _buildOptimizedByteCard(bytes[index], context),
        ),
        if (isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
          ),
        if (!hasMore && bytes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Text('No more bytes',
                  style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.35),
                      fontSize: 13)),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorBannerInline(
      String error, WidgetRef ref, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(error,
                  style:
                  const TextStyle(color: Colors.red, fontSize: 12))),
          IconButton(
            onPressed: () =>
                ref.read(profileFeedProvider.notifier).clearError(),
            icon: const Icon(Icons.close, color: Colors.red, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildOptimizedByteCard(Byte byte, BuildContext context) {
    final thumbnailCandidate = byte.thumbnailUrl;
    final thumbnailUrl =
    (thumbnailCandidate != null && thumbnailCandidate.isNotEmpty)
        ? thumbnailCandidate
        : byte.videoUrl;

    return GestureDetector(
      onTap: () => onByteTap(byte),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbnailUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) =>
                    Container(color: Theme.of(context).cardColor),
                errorWidget: (context, url, error) => Container(
                  color: Theme.of(context).cardColor,
                  child: Icon(Icons.video_library,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.3),
                      size: 36),
                ),
                memCacheWidth: 400,
                maxWidthDiskCache: 400,
              )
            else
              Container(
                color: Theme.of(context).cardColor,
                child: Icon(Icons.video_library,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.3),
                    size: 36),
              ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: 28,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}