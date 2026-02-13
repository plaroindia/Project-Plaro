import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'set_profile.dart';
import '../ViewModel/setProfileProvider.dart';
import '../ViewModel/auth_provider.dart';
import '../ViewModel/user_feed_provider.dart';
import '../ViewModel/follow_provider.dart';
import '../Model/byte.dart';
import '../Model/post.dart';
import '../Model/user_profile.dart';
import '../View/foll_page.dart';
import 'package:google_fonts/google_fonts.dart';
import 'widgets/lightbox_overlay.dart';
import '../View/post_full_screen.dart' as post_screen;
import '../View/bytes_full_screen.dart';
import 'widgets/follow_button.dart';
import '../ViewModel/post_rating_provider.dart';

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

  // Animation controllers for smooth transitions
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Track which tabs have been loaded
  final Set<int> _loadedTabs = {0}; // Start with first tab loaded

  bool get isOwnProfile =>
      widget.userId == null ||
          widget.userId == Supabase.instance.client.auth.currentUser?.id;

  String get targetUserId =>
      widget.userId ?? Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  bool get wantKeepAlive => true; // Keep state alive when switching tabs

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _postsScrollController.addListener(_onPostsScroll);
    _bytesScrollController.addListener(_onBytesScroll);

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    // Listen to tab changes for background preloading
    _tabController.addListener(_onTabChanged);

    // Start fade in
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
      // Clear everything
      ref.read(profileFeedProvider.notifier).clearFeed();
      if (!isOwnProfile) ref.read(followProvider.notifier).clear();

      setState(() {
        _isInitialized = false;
        _loadedTabs.clear(); // Clear loaded tabs tracking
        _tabController.index = 0; // Reset to first tab
      });

      _fadeController.reset();
      _loadUserProfile();
      _fadeController.forward();
    }
  }

  void _clearProvidersState() {
    if (!isOwnProfile) ref.read(followProvider.notifier).clear();
    ref.read(profileFeedProvider.notifier).clearFeed();
  }

  // OPTIMIZATION: Tab change listener for background preloading
  void _onTabChanged() {
    final currentTab = _tabController.index;

    if (!_loadedTabs.contains(currentTab)) {
      _loadedTabs.add(currentTab);
      _preloadTabContent(currentTab);
    }

    // Preload adjacent tab
    final nextTab = (currentTab + 1) % 2;
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
        notifier.loadUserPosts(targetUserId); // Remove isEmpty check
        break;
      case 1:
        notifier.loadUserBytes(targetUserId); // Remove isEmpty check
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
          // Only load visible tab initially
          await _loadVisibleTabContent();
        }
      } else {
        await ref.read(setProfileProvider.notifier).getUserProfile(targetUserId);
        await _loadVisibleTabContent();
      }
      setState(() => _isInitialized = true);
    } catch (e) {
      print(' Error loading profile: $e');
      setState(() => _isInitialized = true);
    }
  }

  // OPTIMIZATION: Load only the visible tab content
  Future<void> _loadVisibleTabContent() async {
    final currentTab = _tabController.index;
    _preloadTabContent(currentTab);
  }

  Future<void> _refreshProfile() async {
    _fadeController.reset();
    setState(() => _isInitialized = false);
    await ref.read(profileFeedProvider.notifier).refreshUserContent(targetUserId);
    await _loadUserProfile();
    _fadeController.forward();
  }

  void _openChat() {
    if (!isOwnProfile) {
      // Navigate to chat screen
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat feature coming soon!')),
      );
    }
  }

  // Helper method to get rank badge info
  Map<String, dynamic> _getRankInfo(String rankLevel) {
    switch (rankLevel.toLowerCase()) {
      case 'beginner':
        return {
          'color': Colors.grey,
          'icon': Icons.star_border,
          'label': 'Newbie',
        };
      case 'intermediate':
        return {
          'color': const Color(0xFFCD7F32), // Bronze color
          'icon': Icons.star_half,
          'label': 'Bronze',
        };
      case 'advanced':
        return {
          'color': const Color(0xFFC0C0C0), // Silver color
          'icon': Icons.star,
          'label': 'Silver',
        };
      case 'expert':
        return {
          'color': const Color(0xFFFFD700), // Gold color
          'icon': Icons.stars,
          'label': 'Gold',
        };
      case 'master':
        return {
          'color': const Color(0xFF9C27B0), // Purple for master
          'icon': Icons.workspace_premium,
          'label': 'Master',
        };
      default:
        return {
          'color': Colors.grey,
          'icon': Icons.star_border,
          'label': 'Newbie',
        };
    }
  }

// Helper to get next rank threshold
  int _getNextRankThreshold(String currentRank) {
    switch (currentRank.toLowerCase()) {
      case 'beginner':
        return 1000;
      case 'intermediate':
        return 50000;
      case 'advanced':
        return 1000000;
      default:
        return 0; // Max rank
    }
  }

// Format large numbers
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
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final authState = ref.watch(authStateProvider);
    final profileState = ref.watch(setProfileProvider);
    final feedState = ref.watch(profileFeedProvider);
    final followState = isOwnProfile ? null : ref.watch(followProvider);

    if (!_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserProfile());
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: RefreshIndicator(
        onRefresh: _refreshProfile,
        color: Colors.blue,
        backgroundColor: Colors.black,
        displacement: 40.0,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(), // OPTIMIZATION: Smooth scroll
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10.0, 5.0, 10.0, 0.0),
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
                      const SizedBox(height: 6.0),
                    ],
                  ),
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverAppBarDelegate(
                minHeight: 50.0,
                maxHeight: 50.0,
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
                ],
              ),
              const LightboxOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // OPTIMIZATION: Skeleton loading for profile
  Widget _buildProfileSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[600]!,
      child: Column(
        children: [
          const SizedBox(height: 20),
          // Avatar skeleton
          Container(
            width: 136,
            height: 136,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(height: 12),
          // Username skeleton
          Container(
            width: 150,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          // School skeleton
          Container(
            width: 200,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          // Bio skeleton
          Container(
            width: 250,
            height: 14,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 20),
          // Stats skeleton
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              3,
                  (index) => Column(
                children: [
                  Container(
                    width: 40,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 60,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHeader(AsyncValue profileState, AsyncValue authState) {
    return Row(
      children: [
        if (!isOwnProfile)
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
          ),
        if (!isOwnProfile) const SizedBox(width: 10),
        Expanded(
          child: profileState.when(
            data: (profile) => Text(
              profile?.username ?? widget.initialUserData?.username ?? 'Unknown User',
              style: GoogleFonts.playwriteFrModerne(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
                shadows: const [
                  Shadow(
                    blurRadius: 8,
                    color: Colors.blue,
                    offset: Offset(2, 2),
                  )
                ],
              ),
              overflow: TextOverflow.ellipsis,
            ),
            loading: () => const Text(
              'Loading...',
              style: TextStyle(color: Colors.grey),
            ),
            error: (error, stack) => Text(
              widget.initialUserData?.username ?? 'Error loading user',
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }


  Widget _buildProfileInfo(AsyncValue profileState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 20.0),

        // First Row: Profile Picture + User Details
        profileState.when(
          data: (profile) {
            if (profile == null) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Profile Picture
                  _buildCachedAvatar(profile.profilePic),

                  const SizedBox(width: 16.0),

                  // User Details (Right side)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Username
                        Text(
                          profile.username ?? widget.initialUserData?.username ?? 'No username',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 20.0,
                            letterSpacing: 2.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6.0),

                        // School
                        Text(
                          profile.study ?? 'No school info',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15.0,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 6.0),

                        // Bio
                        Text(
                          profile.bio ?? 'No bio',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8.0),

                        // Role & Location
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (profile.role != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.work_history_outlined,
                                      color: Colors.lightBlue, size: 14),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      profile.role!,
                                      style: const TextStyle(
                                          color: Colors.green, fontSize: 11.0),
                                    ),
                                  ),
                                  // Verify icon — only own profile + professional role
                                  if (isOwnProfile &&
                                      profile.role == 'professional') ...[
                                    const SizedBox(width: 6),
                                    _VerifyIcon(
                                      isVerified: profile.isVerified ?? false,
                                      userId: profile.user_id ?? '',
                                    ),
                                  ],
                                ],
                              ),
                            if (profile.location != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on_outlined,
                                      color: Colors.lightBlue, size: 14),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      profile.location!,
                                      style: const TextStyle(
                                          color: Colors.red, fontSize: 11.0),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 68.0,
                  backgroundColor: Colors.grey,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('Loading...', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          error: (error, stack) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundImage: AssetImage('assets/plaro_logo.png'),
                  radius: 68.0,
                ),
                const SizedBox(width: 16.0),
                Expanded(
                  child: Text(
                    widget.initialUserData?.username ?? 'Error loading profile',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20.0),



        // Second Row: Circular Progress Bar + Plaro Points & Consistency
        profileState.when(
          data: (profile) {
            if (profile == null) return const SizedBox.shrink();

            final rankInfo = _getRankInfo(profile.rankLevel);
            final nextThreshold = _getNextRankThreshold(profile.rankLevel);
            final progress = nextThreshold > 0
                ? (profile.totalPoints / nextThreshold).clamp(0.0, 1.0)
                : 1.0;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [

                  // Plaro Points & Consistency (Right side)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Plaro Points
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.withOpacity(0.3),
                                Colors.orange.withOpacity(0.1),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amber,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.toll,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Plaro Points',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Text(
                                    _formatPoints(profile.totalPoints),
                                    style: const TextStyle(
                                      color: Colors.amber,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Progress to next rank
                        if (nextThreshold > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${_formatPoints(profile.totalPoints)} / ${_formatPoints(nextThreshold)} to next rank',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          ),
                        ],

                        // const SizedBox(height: 12),
                        //
                        // // Consistency Score
                        // if (profile.consistencyScore > 0.3)
                        //   Container(
                        //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        //     decoration: BoxDecoration(
                        //       gradient: LinearGradient(
                        //         colors: [
                        //           Colors.green.withOpacity(0.3),
                        //           Colors.teal.withOpacity(0.1),
                        //         ],
                        //       ),
                        //       borderRadius: BorderRadius.circular(12),
                        //       border: Border.all(
                        //         color: Colors.green,
                        //         width: 1.5,
                        //       ),
                        //     ),
                        //     child: Row(
                        //       mainAxisSize: MainAxisSize.min,
                        //       children: [
                        //         Icon(
                        //           Icons.trending_up,
                        //           color: Colors.green[400],
                        //           size: 16,
                        //         ),
                        //         const SizedBox(width: 6),
                        //         Text(
                        //           'Consistency: ${(profile.consistencyScore * 100).toInt()}%',
                        //           style: TextStyle(
                        //             color: Colors.green[400],
                        //             fontSize: 12,
                        //             fontWeight: FontWeight.w600,
                        //           ),
                        //         ),
                        //       ],
                        //     ),
                        //   ),
                      ],
                    ),
                  ),


                  const SizedBox(width: 30.0),

                  // Circular Progress Bar (matching profile picture size)
                  SizedBox(
                    width: 90, // Same as profile picture diameter (68*2)
                    height: 90,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Circular progress indicator
                        SizedBox(
                          width: 90,
                          height: 90,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 10,
                            backgroundColor: Colors.grey[800],
                            valueColor: AlwaysStoppedAnimation(rankInfo['color']),
                          ),
                        ),
                        // Center content - Rank badge (trying to use network image-like styling)
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                rankInfo['color'].withOpacity(0.2),
                                Colors.black.withOpacity(0.3),
                              ],
                            ),
                            border: Border.all(
                              color: rankInfo['color'].withOpacity(0.5),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                rankInfo['icon'],
                                color: rankInfo['color'],
                                size: 36,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                rankInfo['label'],
                                style: TextStyle(
                                  color: rankInfo['color'],
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),


                ],
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => const SizedBox.shrink(),
        ),

        const SizedBox(height: 10.0),

        // Stats
        profileState.when(
          data: (profile) => profile != null
              ? Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: SizedBox(
              height: 60,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: _buildStatItem(
                      'Followers',
                      profile.followersCount?.toString() ?? '0',
                      profile,
                    ),
                  ),
                  SizedBox(
                    height: 30,
                    child: VerticalDivider(
                      color: Colors.grey[600],
                      thickness: 1,
                      width: 1,
                    ),
                  ),
                  Flexible(
                    child: _buildStatItem(
                      'Following',
                      profile.followingCount?.toString() ?? '0',
                      profile,
                    ),
                  ),
                  SizedBox(
                    height: 30,
                    child: VerticalDivider(
                      color: Colors.grey[600],
                      thickness: 1,
                      width: 1,
                    ),
                  ),
                  Flexible(
                    child: _buildStatItem(
                      'Streak',
                      profile.streakCount?.toString() ?? '0',
                      profile,
                    ),
                  ),
                ],
              ),
            ),
          )
              : const SizedBox.shrink(),
          loading: () => const SizedBox.shrink(),
          error: (error, stack) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 20.0),
      ],
    );
  }

  // OPTIMIZATION: Cached avatar with placeholder
  Widget _buildCachedAvatar(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return const CircleAvatar(
        backgroundImage: AssetImage('assets/plaro_logo.png'),
        radius: 68.0,
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      imageBuilder: (context, imageProvider) => CircleAvatar(
        backgroundImage: imageProvider,
        radius: 68.0,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: 68.0,
        backgroundColor: Colors.grey[800],
        child: const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
        ),
      ),
      errorWidget: (context, url, error) => const CircleAvatar(
        backgroundImage: AssetImage('assets/plaro_logo.png'),
        radius: 68.0,
      ),
    );
  }

  Widget _buildActionButtons(FollowState? followState) {
    if (isOwnProfile) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black54,
              side: const BorderSide(width: 3.0, color: Colors.blue),
              foregroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SetProfile()),
              ).then((_) => _refreshProfile());
            },
            child: const Text("Profile"),
          ),
          const SizedBox(width: 30.0),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              foregroundColor: Colors.blue,
              backgroundColor: Colors.black54,
              side: const BorderSide(width: 3.0, color: Colors.blue),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            onPressed: () {},
            child: const Text("Stats"),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FollowButton(
            targetUserId: targetUserId,
            compact: false,
            onFollowSuccess: () {
              ref.read(setProfileProvider.notifier).getUserProfile(targetUserId);
            },
          ),
          const SizedBox(width: 30.0),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black54,
              side: const BorderSide(width: 2.0, color: Colors.blue),
              foregroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.0),
              ),
            ),
            onPressed: _openChat,
            child: const Text("Message"),
          ),
        ],
      );
    }
  }

  Widget _buildTabBar(ProfileFeedState feedState) {
    return Container(
      color: Colors.black,
      child: TabBar(
        isScrollable: true,
        controller: _tabController,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(width: 2, color: Colors.blue[400]!),
          insets: const EdgeInsets.symmetric(horizontal: 16.0),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.blue,
        unselectedLabelColor: Colors.grey,
        physics: const BouncingScrollPhysics(),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.view_array_outlined, size: 16),
                const SizedBox(width: 4),
                Text('Posts (${feedState.posts.length})'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.video_library_outlined, size: 16),
                const SizedBox(width: 4),
                Text('Bytes (${feedState.bytes.length})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsTab(ProfileFeedState feedState) {
    final isLoading = feedState.isLoadingPosts && feedState.posts.isEmpty;
    final isEmpty = feedState.posts.isEmpty && !feedState.isLoadingPosts;

    if (isLoading) {
      return _buildGridSkeleton();
    }

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
              builder: (_) => post_screen.PostFullScreen(post: post),
            ),
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

    if (isLoading) {
      return _buildGridSkeleton();
    }

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

  // OPTIMIZATION: Skeleton loader for grids
  Widget _buildGridSkeleton() {
    return Padding(
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
        itemBuilder: (context, index) => Shimmer.fromColors(
          baseColor: Colors.grey[800]!,
          highlightColor: Colors.grey[600]!,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  // OPTIMIZATION: Reusable empty state
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
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
          backgroundColor: Colors.grey[900],
          title: Text(
            'Delete $type',
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            'Are you sure you want to delete this $type? This action cannot be undone.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatItem(String label, String value, UserProfile? userProfile) {
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ],
      ),
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

// OPTIMIZED: ProfilePostsGrid with cached images
class ProfilePostsGrid extends ConsumerWidget {
  final List<Post_feed> posts;
  final ScrollController scrollController;
  final Function(Post_feed) onPostTap;
  final Function(String) onLike;
  final Function(String)? onDelete;
  final bool isLoadingMore;
  final bool hasMore;

  const ProfilePostsGrid({
    Key? key,
    required this.posts,
    required this.scrollController,
    required this.onPostTap,
    required this.onLike,
    this.onDelete,
    required this.isLoadingMore,
    required this.hasMore,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(profileFeedProvider);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: CustomScrollView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          if (feedState.error != null) _buildErrorBanner(feedState.error!, ref),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final post = posts[index];
                return _buildOptimizedPostCard(post);
              },
              childCount: posts.length,
            ),
          ),
          if (isLoadingMore) _buildLoadingIndicator(),
          if (!hasMore && posts.isNotEmpty) _buildEndMessage('No more posts'),
        ],
      ),
    );
  }

  Widget _buildOptimizedPostCard(Post_feed post) {
    // Use the first image URL or fallback to empty string
    final imageUrl = post.imageUrls.isNotEmpty ? post.imageUrls[0] : '';

    return GestureDetector(
      onTap: () => onPostTap(post),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imageUrl.isNotEmpty
              ? CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: Colors.grey[800],
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.grey[800],
              child: const Icon(Icons.broken_image, color: Colors.grey),
            ),
            memCacheWidth: 400, // Memory optimization
            maxWidthDiskCache: 400, // Disk cache optimization
          )
              : Container(
            color: Colors.grey[800],
            child: const Icon(Icons.image, color: Colors.grey, size: 40),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String error, WidgetRef ref) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(16),
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
              child: Text(
                error,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
            IconButton(
              onPressed: () =>
                  ref.read(profileFeedProvider.notifier).clearError(),
              icon: const Icon(Icons.close, color: Colors.red, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildEndMessage(String message) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            message,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Verify Icon — shown next to role chip for own professional profiles
// ─────────────────────────────────────────────────────────────────────────────

class _VerifyIcon extends ConsumerWidget {
  final bool isVerified;
  final String userId;

  const _VerifyIcon({required this.isVerified, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isVerified) {
      // Already verified — show static blue checkmark, no tap
      return const Tooltip(
        message: 'Verified Professional',
        child: Icon(Icons.verified, color: Colors.blue, size: 18),
      );
    }

    // Not yet verified — show tappable shield icon
    return GestureDetector(
      onTap: () => _showVerifyDialog(context, ref),
      child: Tooltip(
        message: 'Get Verified',
        child: Icon(
          Icons.verified_outlined,
          color: Colors.grey.shade500,
          size: 18,
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
          .update({'is_verified': true})
          .eq('user_id', widget.userId);

      // Refresh the profile state so the icon updates immediately
      await ref.read(setProfileProvider.notifier).getUserProfile(widget.userId);

      // Invalidate the cached verification check so RankedByDialog
      // re-fetches and shows the Rate button straight away
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
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.verified_outlined, color: Colors.blue, size: 22),
          SizedBox(width: 10),
          Text('Verify Account',
              style: TextStyle(color: Colors.white, fontSize: 17)),
        ],
      ),
      content: const Text(
        'Verifying your account lets you rate educational posts as a professional.',
        style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
          child:
          const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _loading ? null : _verify,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          ),
          child: _loading
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          )
              : const Text('Verify',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// OPTIMIZED: ProfileBytesGrid with thumbnails
class ProfileBytesGrid extends ConsumerWidget {
  final List<Byte> bytes;
  final ScrollController scrollController;
  final Function(Byte) onByteTap;
  final bool isLoadingMore;
  final bool hasMore;

  const ProfileBytesGrid({
    Key? key,
    required this.bytes,
    required this.scrollController,
    required this.onByteTap,
    required this.isLoadingMore,
    required this.hasMore,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedState = ref.watch(profileFeedProvider);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: CustomScrollView(
        controller: scrollController,
        physics: const BouncingScrollPhysics(),
        slivers: [
          if (feedState.error != null) _buildErrorBanner(feedState.error!, ref),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.9,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final byte = bytes[index];
                return _buildOptimizedByteCard(byte, context);
              },
              childCount: bytes.length,
            ),
          ),
          if (isLoadingMore) _buildLoadingIndicator(),
          if (!hasMore && bytes.isNotEmpty) _buildEndMessage('No more bytes'),
        ],
      ),
    );
  }

  Widget _buildOptimizedByteCard(Byte byte, BuildContext context) {
    // Use thumbnailUrl if available, otherwise fallback to videoUrl or empty
    final thumbnailCandidate = byte.thumbnailUrl;
    final thumbnailUrl =
    (thumbnailCandidate != null && thumbnailCandidate.isNotEmpty) ? thumbnailCandidate : byte.videoUrl;

    return GestureDetector(
      onTap: () => onByteTap(byte),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Video thumbnail (if available)
              if (thumbnailUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: thumbnailUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[800],
                    child: const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.video_library,
                        color: Colors.grey, size: 40),
                  ),
                  memCacheWidth: 400,
                  maxWidthDiskCache: 400,
                )
              else
                Container(
                  color: Colors.grey[800],
                  child: const Icon(Icons.video_library,
                      color: Colors.grey, size: 40),
                ),
              // Play button overlay
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String error, WidgetRef ref) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(16),
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
              child: Text(
                error,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
            IconButton(
              onPressed: () =>
                  ref.read(profileFeedProvider.notifier).clearError(),
              icon: const Icon(Icons.close, color: Colors.red, size: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ),
      ),
    );
  }

  Widget _buildEndMessage(String message) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Text(
            message,
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      ),
    );
  }
}