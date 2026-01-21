import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'post_page.dart';
import 'package:plaro_3/View/taiken_list_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ViewModel/setProfileProvider.dart';
import '../ViewModel/auth_provider.dart';
import '../ViewModel/post_feed_provider.dart';
import 'widgets/post_card.dart';
import 'search_page.dart';
import '../ViewModel/theme_provider.dart';
import 'allevents_page.dart';
import 'profile.dart';
import '../ViewModel/user_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _feedsInitialized = false;
  final ScrollController _scrollController = ScrollController();

  // Optimization: Track if user has scrolled to prevent unnecessary loads
  bool _hasScrolled = false;

  // Optimization: Debounce loading more content
  DateTime? _lastLoadMoreTime;
  static const _loadMoreDebounce = Duration(milliseconds: 500);

  @override
  bool get wantKeepAlive => true; // Keep state alive when switching tabs

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasScrolled) {
      setState(() => _hasScrolled = true);
    }

    // OPTIMIZATION: Load more at 70% scroll instead of 80% for smoother experience
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.7) {
      _loadMoreContent();
    }
  }

  Future<void> _loadMoreContent() async {
    // OPTIMIZATION: Debounce to prevent multiple rapid calls
    final now = DateTime.now();
    if (_lastLoadMoreTime != null &&
        now.difference(_lastLoadMoreTime!) < _loadMoreDebounce) {
      return;
    }
    _lastLoadMoreTime = now;

    final postFeedState = ref.read(postFeedProvider);

    final futures = <Future>[];


    if (postFeedState.hasMore && !postFeedState.isLoadingMore) {
      futures.add(ref.read(postFeedProvider.notifier).loadMorePosts());
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }
  }

  Future<void> _loadUserProfile() async {
    if (_isInitialized) return;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await ref.read(setProfileProvider.notifier).getUserProfile(user.id);
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitialized = true);
      }
    }
  }

  Future<void> _initializeFeeds() async {
    if (_feedsInitialized) return;

    final postFeedState = ref.read(postFeedProvider);

    final futures = <Future>[];

    final bool shouldLoadPosts = postFeedState.posts.isEmpty &&
        (postFeedState.lastFetchTime == null ||
            DateTime.now().difference(postFeedState.lastFetchTime!) >
                Duration(minutes: 5));


    if (shouldLoadPosts && !postFeedState.isLoading) {
      futures.add(ref.read(postFeedProvider.notifier).loadPosts());
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    if (mounted) {
      setState(() => _feedsInitialized = true);
    }
  }

  Future<void> _handleSignOut() async {
    setState(() => _isLoading = true);

    try {
      await ref.read(authControllerProvider).logout();

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed out successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error signing out: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshFeed() async {
    debugPrint('🔄 Refreshing feeds with cache invalidation...');

    setState(() {
      _feedsInitialized = false;
      _hasScrolled = false;
    });

    try {
      await Future.wait([
        ref.read(postFeedProvider.notifier).refreshPosts(),
      ]);

      setState(() => _feedsInitialized = true);

      debugPrint('✅ Feeds refreshed successfully with fresh data');
    } catch (e) {
      debugPrint('❌ Error refreshing feeds: $e');
      setState(() => _feedsInitialized = true);
    }
  }

  List<Map<String, dynamic>> _getCombinedFeed(postFeedState) {
    final List<Map<String, dynamic>> combinedFeed = [];


    for (final post in postFeedState.posts) {
      DateTime timestamp;
      try {
        timestamp = DateTime.parse(post.created_at);
      } catch (e) {
        timestamp = DateTime.now();
      }

      combinedFeed.add({
        'type': 'post',
        'data': post,
        'timestamp': timestamp,
      });
    }

    combinedFeed.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    // Debug logging for combined feed
    debugPrint('DEBUG: Combined feed counts - ${combinedFeed.map((item) => '${item['type']}: ${item['data'].like_count} likes').toList()}');
    return combinedFeed;
  }


  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final authState = ref.watch(authStateProvider);
    final profileState = ref.watch(setProfileProvider);
    final postFeedState = ref.watch(postFeedProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    if (!_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadUserProfile();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeFeeds();
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0, // Flat design like YouTube
        iconTheme: Theme.of(context).appBarTheme.iconTheme,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "PLARO",
              style: TextStyle(
                color: Theme.of(context).appBarTheme.foregroundColor,
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.0,
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SearchScreen()
                      ),
                    );
                  },
                  icon: Icon(
                    Icons.search,
                    color: Theme.of(context).appBarTheme.iconTheme?.color,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/chat_list');
                  },
                  icon: Icon(
                    Icons.message,
                    color: Theme.of(context).appBarTheme.iconTheme?.color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      drawer: _buildDrawer(context, themeMode),
      body: authState.when(
        data: (session) {
          if (session == null) {
            return const Center(
              child: Text(
                'Please log in to continue',
                style: TextStyle(color: Colors.white54, fontSize: 18),
              ),
            );
          }

          return _buildCombinedFeed(postFeedState);
        },
        loading: () => _buildSkeletonLoader(),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                'Error: $error',
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.refresh(authStateProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, ThemeMode themeMode) {
    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              margin: const EdgeInsets.only(bottom: 16.0, top: 32.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10.0),
                  Center(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final currentUserProfile =
                        ref.watch(currentUserProfileProvider);
                        return currentUserProfile.when(
                          data: (profile) => CircleAvatar(
                            backgroundImage: profile?.profilePic != null
                                ? NetworkImage(profile!.profilePic!)
                                : const AssetImage('assets/plaro_logo.png')
                            as ImageProvider,
                            radius: 40.0,
                          ),
                          loading: () => const CircleAvatar(
                            radius: 40.0,
                            backgroundColor: Colors.grey,
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white
                                ),
                              ),
                            ),
                          ),
                          error: (error, stack) => const CircleAvatar(
                            backgroundImage: AssetImage('assets/plaro_logo.png'),
                            radius: 40.0,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Consumer(
                      builder: (context, ref, child) {
                        final authState = ref.watch(authStateProvider);
                        final currentUserProfile =
                        ref.watch(currentUserProfileProvider);

                        return authState.when(
                          data: (session) {
                            return currentUserProfile.when(
                              data: (profile) => Text(
                                profile?.username ??
                                    session?.user.email ??
                                    'No user',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              loading: () => Text(
                                'Loading...',
                                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)),
                              ),
                              error: (error, stack) => Text(
                                session?.user.email ?? 'Error loading user',
                                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                                textAlign: TextAlign.center,
                              ),
                            );
                          },
                          loading: () => Text(
                            'Loading...',
                            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7)),
                          ),
                          error: (error, stack) => Text(
                            'Error loading user',
                            style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            ListTile(
              leading: Icon(
                Icons.event_note,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Events',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AllEventsPage()
                  ),
                );
              },
            ),

            ListTile(
              leading: Icon(
                Icons.event_note,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Taikens',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const TaikensListPage()
                  ),
                );
              },
            ),


            ListTile(
              leading: Icon(
                Icons.settings,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                'Settings',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
              },
            ),

            SwitchListTile(
              title: Text(
                'Dark Mode',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
              value: themeMode == ThemeMode.dark,
              onChanged: (value) {
                ref.read(themeNotifierProvider.notifier).toggleTheme(value);
              },
              secondary: Icon(
                themeMode == ThemeMode.dark
                    ? Icons.dark_mode
                    : Icons.light_mode,
                color: Theme.of(context).iconTheme.color,
              ),
              activeColor: Theme.of(context).colorScheme.primary,
            ),

            Divider(color: Theme.of(context).dividerColor),

            ListTile(
              leading: _isLoading
                  ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).iconTheme.color ?? Colors.grey,
                  ),
                ),
              )
                  : Icon(
                Icons.logout,
                color: Theme.of(context).iconTheme.color,
              ),
              title: Text(
                _isLoading ? 'Signing out...' : 'Sign Out',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                ),
              ),
              onTap: _isLoading ? null : _handleSignOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombinedFeed(dynamic postFeedState) {
    final combinedFeed = _getCombinedFeed(postFeedState);
    final hasError =  postFeedState.error != null;
    final isLoading =  postFeedState.isLoading;
    final isLoadingMore = postFeedState.isLoadingMore;
    final isEmpty = combinedFeed.isEmpty;

    // OPTIMIZATION: Show cached data immediately while loading
    final bool showCachedData = combinedFeed.isNotEmpty && isLoading;

    return RefreshIndicator(
      onRefresh: _refreshFeed,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      color: Theme.of(context).colorScheme.primary,
      // OPTIMIZATION: Reduced displacement for smoother pull
      displacement: 40,
      strokeWidth: 2.5,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          // OPTIMIZATION: Better scroll physics like YouTube
          parent: BouncingScrollPhysics(),
        ),
        // OPTIMIZATION: Cache extent for smoother scrolling
        cacheExtent: 1000, // Pre-render content 1000px ahead
        slivers: [
          // Error handling - Dismissible banner
          if (hasError)
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.all(8),
                child: Material(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: () {
                      if (postFeedState.error != null) {
                        ref.read(postFeedProvider.notifier).clearError();
                      }
                      _refreshFeed();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.red,
                              size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                  postFeedState.error ??
                                  'Unknown error',
                              style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 13
                              ),
                            ),
                          ),
                          const Icon(Icons.refresh,
                              color: Colors.red,
                              size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // OPTIMIZATION: Show skeleton while initial load, cached data otherwise
          if (isEmpty && isLoading && !showCachedData)
            _buildSkeletonFeed()
          else if (combinedFeed.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final feedItem = combinedFeed[index];
                  final type = feedItem['type'] as String;
                  final data = feedItem['data'];

                  // OPTIMIZATION: Add subtle fade-in animation for items
                  return AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: PostCard(
                      post: data,
                      onTap: () {},
                      onUserInfo: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OtherProfileScreen(
                              userId: data.user_id,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
                childCount: combinedFeed.length,
                // OPTIMIZATION: Add semantic indexes for better accessibility
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                addSemanticIndexes: true,
              ),
            ),

          // Empty state
          if (isEmpty && !isLoading && !hasError)
            _buildEmptyState(),

          // OPTIMIZATION: Improved loading indicator for pagination
          if (isLoadingMore && combinedFeed.isNotEmpty)
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),

          // Bottom padding
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  // OPTIMIZATION: Skeleton loader for better perceived performance
  Widget _buildSkeletonLoader() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (context, index) => _SkeletonCard(),
    );
  }

  Widget _buildSkeletonFeed() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) => _SkeletonCard(),
        childCount: 5,
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.article_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No posts yet',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share something!',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PostCreateScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Posts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// OPTIMIZATION: Skeleton card widget for loading state
class _SkeletonCard extends StatefulWidget {
  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = theme.cardTheme.color ?? Colors.grey[850]!;
    final highlightColor = theme.brightness == Brightness.dark
        ? Colors.grey[700]!
        : Colors.grey[300]!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      color: baseColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      elevation: 0,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(_animation.value, 0),
                end: Alignment(_animation.value + 1, 0),
                colors: [
                  baseColor,
                  highlightColor,
                  baseColor,
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User header
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: highlightColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 120,
                              height: 12,
                              decoration: BoxDecoration(
                                color: highlightColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 80,
                              height: 10,
                              decoration: BoxDecoration(
                                color: highlightColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Content lines
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 200,
                        height: 12,
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0),
                  child: Row(
                    children: List.generate(
                      4,
                          (index) => Padding(
                        padding: const EdgeInsets.only(right: 24),
                        child: Row(
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: highlightColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 24,
                              height: 12,
                              decoration: BoxDecoration(
                                color: highlightColor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }
}