import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_profile.dart';
import '../Viewmodels/follow_provider.dart';
import '../Viewmodels/auth_provider.dart';
import 'profile.dart';
import 'widgets/follow_button.dart';

class FollowPage extends ConsumerStatefulWidget {
  final String userId;
  final int initialTab;

  const FollowPage({
    super.key,
    required this.userId,
    this.initialTab = 0,
  });

  @override
  ConsumerState<FollowPage> createState() => _FollowPageState();
}

class _FollowPageState extends ConsumerState<FollowPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _followersScrollController = ScrollController();
  final ScrollController _followingScrollController = ScrollController();

  bool _isSearching = false;
  String _searchQuery = '';

  List<UserProfile> _filteredFollowers = [];
  List<UserProfile> _filteredFollowing = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _searchController.addListener(_onSearchChanged);
    _followersScrollController.addListener(_onFollowersScroll);
    _followingScrollController.addListener(_onFollowingScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _followersScrollController.dispose();
    _followingScrollController.dispose();
    super.dispose();
  }

  void _loadInitialData() {
    final notifier = ref.read(followProvider.notifier);
    notifier.loadFollowers(widget.userId, refresh: true);
    notifier.loadFollowing(widget.userId, refresh: true);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
      _updateFilteredLists();
    });
  }

  void _updateFilteredLists() {
    final s = ref.read(followProvider);
    if (_searchQuery.isEmpty) {
      _filteredFollowers = s.followers;
      _filteredFollowing = s.following;
    } else {
      bool _matches(UserProfile u) =>
          u.username.toLowerCase().contains(_searchQuery) ||
          (u.bio?.toLowerCase().contains(_searchQuery) ?? false) ||
          (u.role?.toLowerCase().contains(_searchQuery) ?? false);
      _filteredFollowers = s.followers.where(_matches).toList();
      _filteredFollowing = s.following.where(_matches).toList();
    }
  }

  void _onFollowersScroll() {
    if (_followersScrollController.position.pixels >=
        _followersScrollController.position.maxScrollExtent - 200) {
      // Calling without refresh:true triggers the next page
      ref.read(followProvider.notifier).loadFollowers(widget.userId);
    }
  }

  void _onFollowingScroll() {
    if (_followingScrollController.position.pixels >=
        _followingScrollController.position.maxScrollExtent - 200) {
      ref.read(followProvider.notifier).loadFollowing(widget.userId);
    }
  }

  Future<void> _onRefresh() async {
    ref.read(followProvider.notifier).loadFollowers(widget.userId, refresh: true);
    ref.read(followProvider.notifier).loadFollowing(widget.userId, refresh: true);
  }

  void _toggleSearch() {
    setState(() {
      if (_isSearching) {
        _searchController.clear();
        _searchQuery = '';
        _updateFilteredLists();
      }
      _isSearching = !_isSearching;
    });
  }

  @override
  Widget build(BuildContext context) {
    final followState = ref.watch(followProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Update filtered lists every build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateFilteredLists();
    });

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.4)),
                  border: InputBorder.none,
                ),
              )
            : Text(
                'Connections',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
              color: colorScheme.onSurface,
            ),
            onPressed: _toggleSearch,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(4),
              labelColor: Colors.white,
              unselectedLabelColor: colorScheme.onSurface.withOpacity(0.5),
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              tabs: [
                _buildTab(
                  'Followers',
                  _searchQuery.isEmpty
                      ? followState.followers.length
                      : _filteredFollowers.length,
                ),
                _buildTab(
                  'Following',
                  _searchQuery.isEmpty
                      ? followState.following.length
                      : _filteredFollowing.length,
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(
            followState,
            isFollowers: true,
            scrollController: _followersScrollController,
          ),
          _buildList(
            followState,
            isFollowers: false,
            scrollController: _followingScrollController,
          ),
        ],
      ),
    );
  }

  Tab _buildTab(String label, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    FollowState followState, {
    required bool isFollowers,
    required ScrollController scrollController,
  }) {
    final isLoading =
        isFollowers ? followState.isLoadingFollowers : followState.isLoadingFollowing;
    final list = isFollowers
        ? (_searchQuery.isEmpty ? followState.followers : _filteredFollowers)
        : (_searchQuery.isEmpty ? followState.following : _filteredFollowing);
    final hasMore =
        isFollowers ? followState.hasMoreFollowers : followState.hasMoreFollowing;

    if (isLoading && list.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0077FF)),
        ),
      );
    }

    if (followState.error != null && list.isEmpty) {
      return _buildErrorState(followState.error!, isFollowers);
    }

    if (list.isEmpty) {
      return RefreshIndicator(
        onRefresh: _onRefresh,
        color: const Color(0xFF0077FF),
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.28),
            _buildEmptyState(isFollowers),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      color: const Color(0xFF0077FF),
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: list.length + (hasMore && _searchQuery.isEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= list.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0077FF)),
                ),
              ),
            );
          }
          return _UserConnectionCard(
            user: list[index],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OtherProfileScreen(
                  userId: list[index].user_id,
                  initialUserData: list[index],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(bool isFollowers) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0077FF).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isFollowers ? Icons.people_outline_rounded : Icons.person_add_outlined,
              size: 52,
              color: const Color(0xFF0077FF).withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _searchQuery.isNotEmpty
                ? 'No results found'
                : isFollowers
                    ? 'No followers yet'
                    : 'Not following anyone',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Try a different search term'
                : isFollowers
                    ? 'Followers will appear here'
                    : 'People you follow will appear here',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error, bool isFollowers) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 56, color: Colors.red[300]),
          const SizedBox(height: 16),
          Text(
            'Failed to load ${isFollowers ? "followers" : "following"}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () {
              if (isFollowers) {
                ref
                    .read(followProvider.notifier)
                    .loadFollowers(widget.userId, refresh: true);
              } else {
                ref
                    .read(followProvider.notifier)
                    .loadFollowing(widget.userId, refresh: true);
              }
            },
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0077FF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Enhanced user connection card
// ─────────────────────────────────────────────────────────────────────────────

class _UserConnectionCard extends ConsumerWidget {
  final UserProfile user;
  final VoidCallback onTap;

  const _UserConnectionCard({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId =
        ref.watch(authStateProvider).valueOrNull?.user.id;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.onSurface.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.onSurface.withOpacity(0.07),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar with gradient ring
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(2.5),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: theme.cardColor,
                backgroundImage: (user.profilePic != null &&
                        user.profilePic!.isNotEmpty)
                    ? CachedNetworkImageProvider(user.profilePic!)
                    : null,
                child: (user.profilePic == null || user.profilePic!.isEmpty)
                    ? Text(
                        user.username.isNotEmpty
                            ? user.username[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // Info section
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '@${user.username}',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.isVerified == true) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded,
                            color: Color(0xFF0077FF), size: 14),
                      ],
                    ],
                  ),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      user.bio!,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (user.role != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0077FF).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        user.role!,
                        style: const TextStyle(
                          color: Color(0xFF0077FF),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Follow button (only for other users)
            if (currentUserId != null && currentUserId != user.user_id)
              FollowButton(
                key: ValueKey('foll_card_${user.user_id}'),
                targetUserId: user.user_id,
                compact: true,
              ),
          ],
        ),
      ),
    );
  }
}