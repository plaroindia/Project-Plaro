import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'post_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Viewmodels/setProfileProvider.dart';
import '../Viewmodels/auth_provider.dart';
import '../Viewmodels/post_feed_provider.dart';
import '../Viewmodels/follow_provider.dart';
import '../Viewmodels/notifications_provider.dart';
import 'widgets/post_card.dart';
import 'search_page.dart';
import '../Viewmodels/theme_provider.dart';
import 'profile.dart';
import '../Viewmodels/user_provider.dart';
import '../Viewmodels/content_event_tracker.dart';
import 'settings_page.dart';
import 'notifications_page.dart';
import '../Viewmodels/account_switcher_provider.dart';
import 'navipg.dart' show AccountSwitcherSheet;
import 'navipg.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _feedsInitialized = false;
  final ScrollController _scrollController = ScrollController();

  bool _hasScrolled = false;
  DateTime? _lastLoadMoreTime;
  static const _loadMoreDebounce = Duration(milliseconds: 500);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUserProfile();
      _initializeFeeds();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(contentEventTrackerProvider).forceFlush();
    }
  }

  void _onScroll() {
    if (!_hasScrolled) setState(() => _hasScrolled = true);
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.7) {
      _loadMoreContent();
    }
  }

  Future<void> _loadMoreContent() async {
    final now = DateTime.now();
    if (_lastLoadMoreTime != null &&
        now.difference(_lastLoadMoreTime!) < _loadMoreDebounce) return;
    _lastLoadMoreTime = now;

    final postFeedState = ref.read(postFeedProvider);
    final futures = <Future>[];
    if (postFeedState.hasMore && !postFeedState.isLoadingMore) {
      futures.add(ref.read(postFeedProvider.notifier).loadMorePosts());
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
      _consumeFollowStatusCache();
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
      if (mounted) setState(() => _isInitialized = true);
    }
  }

  Future<void> _initializeFeeds() async {
    if (_feedsInitialized) return;
    _feedsInitialized = true;

    final postFeedState = ref.read(postFeedProvider);
    final bool cacheStale = postFeedState.lastFetchTime == null ||
        DateTime.now().difference(postFeedState.lastFetchTime!) >
            const Duration(minutes: 5);

    if (postFeedState.posts.isEmpty && cacheStale && !postFeedState.isLoading) {
      await ref.read(postFeedProvider.notifier).loadPosts();
      _consumeFollowStatusCache();
    }
  }

  void _consumeFollowStatusCache() {
    if (!mounted) return;
    final cache = ref.read(postFeedProvider).followStatusCache;
    if (cache.isEmpty) return;
    ref.read(followProvider.notifier).seedFollowingStatus(cache);
    ref.read(postFeedProvider.notifier).clearFollowStatusCache();
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshFeed() async {
    setState(() {
      _feedsInitialized = false;
      _hasScrolled = false;
    });
    try {
      await Future.wait([ref.read(postFeedProvider.notifier).refreshPosts()]);
      setState(() => _feedsInitialized = true);
    } catch (e) {
      setState(() => _feedsInitialized = true);
    }
  }

  List<Map<String, dynamic>> _getCombinedFeed(postFeedState) {
    return postFeedState.posts
        .map<Map<String, dynamic>>((post) => {'type': 'post', 'data': post})
        .toList();
  }

  // ── Bell icon widget with live unread badge ──────────────────────────────

  Widget _buildBellIcon() {
    final unread = ref.watch(unreadNotifCountProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: Icon(
            Icons.notifications_outlined,
            color: Theme.of(context).appBarTheme.iconTheme?.color,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
        ),
        if (unread > 0)
          Positioned(
            top: 6,
            right: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final authState = ref.watch(authStateProvider);
    final postFeedState = ref.watch(postFeedProvider);
    final themeMode = ref.watch(themeNotifierProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // ── Single AppBar: PLARO | search · bell · chat ──────────────────────
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        iconTheme: Theme.of(context).appBarTheme.iconTheme,
        title: const Text(
          'PLARO',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: 1.5,
          ),
        ),
        // Search · Bell · Chat live in actions — standard Android pattern.
        // Bell sits between search and chat so the most contextual
        // actions (search content, see alerts, open messages) are
        // left-to-right in priority order.
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
            icon: Icon(
              Icons.search,
              color: Theme.of(context).appBarTheme.iconTheme?.color,
            ),
          ),
          _buildBellIcon(),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/chat_list'),
            icon: Icon(
              Icons.forum,
              color: Theme.of(context).appBarTheme.iconTheme?.color,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _buildDrawer(context, themeMode),
      body: authState.when(
        data: (session) {
          if (session == null) {
            return Center(
              child: Text(
                'Please log in to continue',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.54),
                  fontSize: 18,
                ),
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
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
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
            // ── Profile header ──────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              margin: const EdgeInsets.only(bottom: 8.0, top: 32.0),
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
                            radius: 60.0,
                          ),
                          loading: () => CircleAvatar(
                            radius: 40.0,
                            backgroundColor: Theme.of(context).cardColor,
                            child: const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            ),
                          ),
                          error: (error, stack) => const CircleAvatar(
                            backgroundImage:
                            AssetImage('assets/plaro_logo.png'),
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
                          data: (session) => currentUserProfile.when(
                            data: (profile) => Text(
                              profile?.username ??
                                  session?.user.email ??
                                  'No user',
                              style: TextStyle(
                                color:
                                Theme.of(context).colorScheme.onPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                            loading: () => Text(
                              'Loading...',
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimary
                                      .withOpacity(0.7)),
                            ),
                            error: (error, stack) => Text(
                              session?.user.email ?? 'Error loading user',
                              style: TextStyle(
                                  color:
                                  Theme.of(context).colorScheme.onPrimary),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          loading: () => Text(
                            'Loading...',
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimary
                                    .withOpacity(0.7)),
                          ),
                          error: (error, stack) => Text(
                            'Error loading user',
                            style: TextStyle(
                                color:
                                Theme.of(context).colorScheme.onPrimary),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // ── Switch / Add account row ─────────────────────────────────────
            Consumer(
              builder: (context, ref, _) {
                final accounts = ref
                    .watch(accountSwitcherProvider.select((s) => s.accounts));
                final currentEmail =
                    Supabase.instance.client.auth.currentUser?.email ?? '';
                final otherAccounts =
                accounts.where((a) => a.email != currentEmail).toList();

                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Navigator.pop(context); // close drawer
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      isScrollControlled: true,
                      barrierColor: Colors.black.withOpacity(0.6),
                      builder: (_) => AccountSwitcherSheet(
                        onAfterSwitch: (result) {
                          final requiresOnboarding =
                              result['requiresOnboarding'] == true;
                          if (requiresOnboarding) {
                            Navigator.pushReplacementNamed(
                                context, '/onboarding');
                          } else {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const navCard()),
                                  (_) => false,
                            );
                          }
                        },
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // Stacked mini-avatars of other accounts (max 3)
                        SizedBox(
                          width: otherAccounts.isEmpty
                              ? 32
                              : 14.0 +
                              otherAccounts.length.clamp(1, 3) * 18.0,
                          height: 32,
                          child: Stack(
                            children: [
                              if (otherAccounts.isEmpty)
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.grey[700]!, width: 1.5),
                                  ),
                                  child: const Icon(Icons.add,
                                      size: 14, color: Colors.blue),
                                )
                              else
                                for (int i = 0;
                                i < otherAccounts.length.clamp(0, 3);
                                i++)
                                  Positioned(
                                    left: i * 18.0,
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .scaffoldBackgroundColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: otherAccounts[i].photoUrl !=
                                            null &&
                                            otherAccounts[i]
                                                .photoUrl!
                                                .isNotEmpty
                                            ? Image.network(
                                          otherAccounts[i].photoUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                                color: Colors.grey[800],
                                                child: const Icon(
                                                    Icons.person,
                                                    size: 14,
                                                    color: Colors.grey),
                                              ),
                                        )
                                            : Container(
                                          color: Colors.grey[800],
                                          child: const Icon(Icons.person,
                                              size: 14,
                                              color: Colors.grey),
                                        ),
                                      ),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            otherAccounts.isEmpty
                                ? 'Add account'
                                : 'Switch accounts',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.unfold_more,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.45),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            Divider(color: Theme.of(context).dividerColor),

            // ── Settings ────────────────────────────────────────────────────
            ListTile(
              leading: Icon(Icons.settings,
                  color: Theme.of(context).iconTheme.color),
              title: Text(
                'Settings',
                style:
                TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            Divider(color: Theme.of(context).dividerColor),

            // ── Sign out ────────────────────────────────────────────────────
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
                  : Icon(Icons.logout,
                  color: Theme.of(context).iconTheme.color),
              title: Text(
                _isLoading ? 'Signing out...' : 'Sign Out',
                style:
                TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
    final hasError = postFeedState.error != null;
    final isLoading = postFeedState.isLoading;
    final isLoadingMore = postFeedState.isLoadingMore;
    final isEmpty = combinedFeed.isEmpty;
    final bool showCachedData = combinedFeed.isNotEmpty && isLoading;

    return RefreshIndicator(
      onRefresh: _refreshFeed,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      color: Theme.of(context).colorScheme.primary,
      displacement: 40,
      strokeWidth: 2.5,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        cacheExtent: 1000,
        slivers: [
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
                              color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              postFeedState.error ?? 'Unknown error',
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13),
                            ),
                          ),
                          const Icon(Icons.refresh,
                              color: Colors.red, size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (isEmpty && isLoading && !showCachedData)
            _buildSkeletonFeed()
          else if (combinedFeed.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final feedItem = combinedFeed[index];
                  final data = feedItem['data'];
                  return AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: PostCard(
                      post: data,
                      onTap: () {
                        final userId = ref
                            .read(authStateProvider)
                            .valueOrNull
                            ?.user
                            .id;
                        if (userId != null) {
                          ref.read(contentEventTrackerProvider).trackView(
                            userId: userId,
                            contentType: 'post',
                            contentIdInt: int.tryParse(data.post_id ?? ''),
                            domain: data.domain,
                            source: 'feed',
                          );
                        }
                      },
                      onUserInfo: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                OtherProfileScreen(userId: data.user_id),
                          ),
                        );
                      },
                    ),
                  );
                },
                childCount: combinedFeed.length,
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                addSemanticIndexes: true,
              ),
            ),
          if (isEmpty && !isLoading && !hasError) _buildEmptyState(),
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
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

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
                color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to share something!',
              style: TextStyle(
                color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => PostCreateScreen()),
              ),
              icon: const Icon(Icons.add),
              label: const Text('Create Posts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton card (unchanged) ────────────────────────────────────────────────

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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      elevation: 0,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(_animation.value, 0),
                end: Alignment(_animation.value + 1, 0),
                colors: [baseColor, highlightColor, baseColor],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                            color: highlightColor, shape: BoxShape.circle),
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
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 80,
                              height: 10,
                              decoration: BoxDecoration(
                                  color: highlightColor,
                                  borderRadius: BorderRadius.circular(4)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 12,
                        decoration: BoxDecoration(
                            color: highlightColor,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 200,
                        height: 12,
                        decoration: BoxDecoration(
                            color: highlightColor,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
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
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              width: 24,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: highlightColor,
                                  borderRadius: BorderRadius.circular(4)),
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