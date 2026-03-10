// ================================================================
// follow_provider.dart  (UPGRADED)
// Change: toggleFollow now calls update_follow_graph RPC instead
// of writing directly to user_follows. All other public API is
// identical so existing UI needs zero changes.
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Model/user_profile.dart';

// ── State (unchanged) ────────────────────────────────────────

class FollowState {
  final List<UserProfile> followers;
  final List<UserProfile> following;
  final bool isLoadingFollowers;
  final bool isLoadingFollowing;
  final String? error;
  final bool hasMoreFollowers;
  final bool hasMoreFollowing;
  final int followersPage;
  final int followingPage;
  final Map<String, bool> followingStatus;
  final Set<String> processingFollowRequests;
  final DateTime? lastFollowersUpdate;
  final DateTime? lastFollowingUpdate;
  final Map<String, int> followerCounts;
  final Map<String, int> followingCounts;

  const FollowState({
    this.followers = const [],
    this.following = const [],
    this.isLoadingFollowers = false,
    this.isLoadingFollowing = false,
    this.error,
    this.hasMoreFollowers = true,
    this.hasMoreFollowing = true,
    this.followersPage = 0,
    this.followingPage = 0,
    this.followingStatus = const {},
    this.processingFollowRequests = const {},
    this.lastFollowersUpdate,
    this.lastFollowingUpdate,
    this.followerCounts = const {},
    this.followingCounts = const {},
  });

  FollowState copyWith({
    List<UserProfile>? followers,
    List<UserProfile>? following,
    bool? isLoadingFollowers,
    bool? isLoadingFollowing,
    String? error,
    bool? hasMoreFollowers,
    bool? hasMoreFollowing,
    int? followersPage,
    int? followingPage,
    Map<String, bool>? followingStatus,
    Set<String>? processingFollowRequests,
    DateTime? lastFollowersUpdate,
    DateTime? lastFollowingUpdate,
    Map<String, int>? followerCounts,
    Map<String, int>? followingCounts,
  }) => FollowState(
    followers:               followers               ?? this.followers,
    following:               following               ?? this.following,
    isLoadingFollowers:      isLoadingFollowers      ?? this.isLoadingFollowers,
    isLoadingFollowing:      isLoadingFollowing      ?? this.isLoadingFollowing,
    error:                   error,
    hasMoreFollowers:        hasMoreFollowers        ?? this.hasMoreFollowers,
    hasMoreFollowing:        hasMoreFollowing        ?? this.hasMoreFollowing,
    followersPage:           followersPage           ?? this.followersPage,
    followingPage:           followingPage           ?? this.followingPage,
    followingStatus:         followingStatus         ?? this.followingStatus,
    processingFollowRequests: processingFollowRequests ?? this.processingFollowRequests,
    lastFollowersUpdate:     lastFollowersUpdate     ?? this.lastFollowersUpdate,
    lastFollowingUpdate:     lastFollowingUpdate     ?? this.lastFollowingUpdate,
    followerCounts:          followerCounts          ?? this.followerCounts,
    followingCounts:         followingCounts         ?? this.followingCounts,
  );
}

// ── Notifier ─────────────────────────────────────────────────

class FollowNotifier extends StateNotifier<FollowState> {
  FollowNotifier() : super(const FollowState());

  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _pageSize = 20;
  static const _cacheExpiry = Duration(minutes: 5);
  final Map<String, DateTime> _lastToggleTime = {};
  static const Duration _debounceDelay = Duration(milliseconds: 500);

  String? get _currentUserId => _supabase.auth.currentUser?.id;

  // ── Read operations (unchanged from original) ────────────

  Future<void> loadFollowers(String userId, {bool refresh = false}) async {
    if (!refresh &&
        state.lastFollowersUpdate != null &&
        DateTime.now().difference(state.lastFollowersUpdate!) < _cacheExpiry &&
        state.followers.isNotEmpty) return;

    if (state.isLoadingFollowers && !refresh) return;
    state = state.copyWith(isLoadingFollowers: true, error: null);

    try {
      final page   = refresh ? 0 : state.followersPage;
      final offset = page * _pageSize;

      final followsResponse = await _supabase
          .from('user_follows').select('follower_id')
          .eq('followee_id', userId)
          .order('followed_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      final followerIds = (followsResponse as List)
          .map((e) => e['follower_id'] as String).toList();

      if (followerIds.isEmpty) {
        state = state.copyWith(
          followers: refresh ? [] : state.followers,
          isLoadingFollowers: false, hasMoreFollowers: false,
          followersPage: refresh ? 1 : state.followersPage + 1,
          lastFollowersUpdate: DateTime.now(),
        );
        return;
      }

      final profilesResponse = await _supabase
          .from('user_profiles').select('*')
          .inFilter('user_id', followerIds);

      final newFollowers = (profilesResponse as List)
          .map((json) => UserProfile.fromJson(json)).toList();

      Map<String, bool> updatedStatus = Map.from(state.followingStatus);
      if (_currentUserId != null && newFollowers.isNotEmpty) {
        final checkResponse = await _supabase
            .from('user_follows').select('followee_id')
            .eq('follower_id', _currentUserId!)
            .inFilter('followee_id', followerIds);
        final followingSet = (checkResponse as List)
            .map((e) => e['followee_id'] as String).toSet();
        for (var f in newFollowers) {
          updatedStatus[f.user_id] = followingSet.contains(f.user_id);
        }
      }

      state = state.copyWith(
        followers: refresh ? newFollowers : [...state.followers, ...newFollowers],
        isLoadingFollowers: false,
        hasMoreFollowers: newFollowers.length == _pageSize,
        followersPage: refresh ? 1 : state.followersPage + 1,
        followingStatus: updatedStatus,
        lastFollowersUpdate: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(isLoadingFollowers: false,
          error: 'Failed to load followers: $e');
    }
  }

  Future<void> loadFollowing(String userId, {bool refresh = false}) async {
    if (!refresh &&
        state.lastFollowingUpdate != null &&
        DateTime.now().difference(state.lastFollowingUpdate!) < _cacheExpiry &&
        state.following.isNotEmpty) return;

    if (state.isLoadingFollowing && !refresh) return;
    state = state.copyWith(isLoadingFollowing: true, error: null);

    try {
      final page   = refresh ? 0 : state.followingPage;
      final offset = page * _pageSize;

      final followsResponse = await _supabase
          .from('user_follows').select('followee_id')
          .eq('follower_id', userId)
          .order('followed_at', ascending: false)
          .range(offset, offset + _pageSize - 1);

      final followeeIds = (followsResponse as List)
          .map((e) => e['followee_id'] as String).toList();

      if (followeeIds.isEmpty) {
        state = state.copyWith(
          following: refresh ? [] : state.following,
          isLoadingFollowing: false, hasMoreFollowing: false,
          followingPage: refresh ? 1 : state.followingPage + 1,
          lastFollowingUpdate: DateTime.now(),
        );
        return;
      }

      final profilesResponse = await _supabase
          .from('user_profiles').select('*')
          .inFilter('user_id', followeeIds);

      final newFollowing = (profilesResponse as List)
          .map((json) => UserProfile.fromJson(json)).toList();

      Map<String, bool> updatedStatus = Map.from(state.followingStatus);
      for (var f in newFollowing) updatedStatus[f.user_id] = true;

      state = state.copyWith(
        following: refresh ? newFollowing : [...state.following, ...newFollowing],
        isLoadingFollowing: false,
        hasMoreFollowing: newFollowing.length == _pageSize,
        followingPage: refresh ? 1 : state.followingPage + 1,
        followingStatus: updatedStatus,
        lastFollowingUpdate: DateTime.now(),
      );
    } catch (e) {
      state = state.copyWith(isLoadingFollowing: false,
          error: 'Failed to load following: $e');
    }
  }

  // ── UPGRADED: toggleFollow uses RPC ─────────────────────
  // The RPC handles user_follows + count updates + recommendation
  // refresh. Flutter never touches those tables directly.

  Future<void> toggleFollow(String targetUserId) async {
    if (_currentUserId == null || _currentUserId == targetUserId) return;
    if (state.processingFollowRequests.contains(targetUserId)) return;

    final isCurrentlyFollowing = state.followingStatus[targetUserId] ?? false;
    final action = isCurrentlyFollowing ? 'unfollow' : 'follow';

    // Optimistic UI update
    state = state.copyWith(
      processingFollowRequests: {...state.processingFollowRequests, targetUserId},
      followingStatus: {...state.followingStatus, targetUserId: !isCurrentlyFollowing},
    );
    _updateCountsInLists(targetUserId, isCurrentlyFollowing ? -1 : 1);

    try {
      // ── Single RPC call — no direct table writes ──────────
      await _supabase.rpc('update_follow_graph', params: {
        'p_target_user_id': targetUserId,
        'p_action':         action,
      });

      state = state.copyWith(
        processingFollowRequests: Set.from(state.processingFollowRequests)
          ..remove(targetUserId),
        lastFollowersUpdate: null, // invalidate cache
        lastFollowingUpdate: null,
        error: null,
      );
      debugPrint('[Follow] $action $targetUserId via RPC ✓');
    } catch (e) {
      // Revert optimistic update
      state = state.copyWith(
        followingStatus: {...state.followingStatus, targetUserId: isCurrentlyFollowing},
        processingFollowRequests: Set.from(state.processingFollowRequests)
          ..remove(targetUserId),
        error: 'Failed to ${action} user',
      );
      _updateCountsInLists(targetUserId, isCurrentlyFollowing ? 1 : -1);
      debugPrint('[Follow] RPC $action failed: $e');
    }
  }

  Future<void> toggleFollowWithDebounce(String targetUserId) async {
    final now  = DateTime.now();
    final last = _lastToggleTime[targetUserId];
    if (last != null && now.difference(last) < _debounceDelay) return;
    _lastToggleTime[targetUserId] = now;
    await toggleFollow(targetUserId);
  }

  // ── Unchanged helpers ────────────────────────────────────

  void _updateCountsInLists(String targetUserId, int increment) {
    state = state.copyWith(
      followers: state.followers.map((f) => f.user_id == targetUserId
          ? f.copyWith(followersCount: (f.followersCount ?? 0) + increment)
          : f).toList(),
      following: state.following.map((f) => f.user_id == targetUserId
          ? f.copyWith(followersCount: (f.followersCount ?? 0) + increment)
          : f).toList(),
    );
  }

  Future<Map<String, bool>> batchCheckFollowing(List<String> userIds) async {
    if (_currentUserId == null || userIds.isEmpty) return {};
    try {
      final response = await _supabase
          .from('user_follows').select('followee_id')
          .eq('follower_id', _currentUserId!)
          .inFilter('followee_id', userIds);
      final set = (response as List).map((e) => e['followee_id'] as String).toSet();
      return Map.fromEntries(userIds.map((id) => MapEntry(id, set.contains(id))));
    } catch (_) {
      return {};
    }
  }

  Future<void> refreshFollowStatusGlobally(String targetUserId) async {
    if (_currentUserId == null) return;
    try {
      final response = await _supabase
          .from('user_follows').select('follower_id')
          .eq('follower_id', _currentUserId!)
          .eq('followee_id', targetUserId)
          .maybeSingle();
      state = state.copyWith(followingStatus: {
        ...state.followingStatus,
        targetUserId: response != null,
      });
    } catch (_) {}
  }

  Future<void> refreshFollowingStatus(String userId) async {
    final map = await batchCheckFollowing([userId]);
    state = state.copyWith(followingStatus: {...state.followingStatus, ...map});
  }

  Future<void> loadMoreFollowers(String userId) async {
    if (!state.hasMoreFollowers || state.isLoadingFollowers) return;
    await loadFollowers(userId);
  }

  Future<void> loadMoreFollowing(String userId) async {
    if (!state.hasMoreFollowing || state.isLoadingFollowing) return;
    await loadFollowing(userId);
  }

  Future<void> refresh(String userId) async {
    await Future.wait([
      loadFollowers(userId, refresh: true),
      loadFollowing(userId, refresh: true),
    ]);
  }

  bool isFollowing(String userId)       => state.followingStatus[userId] ?? false;
  bool isProcessingFollow(String userId) => state.processingFollowRequests.contains(userId);
  void clearError()                      => state = state.copyWith(error: null);
  void clear()                           => state = const FollowState();
}

// ── Providers ─────────────────────────────────────────────────

final followProvider =
StateNotifierProvider<FollowNotifier, FollowState>((ref) => FollowNotifier());

final isFollowingProvider = Provider.family<bool, String>(
        (ref, userId) => ref.watch(followProvider).followingStatus[userId] ?? false);

final isProcessingFollowProvider = Provider.family<bool, String>(
        (ref, userId) =>
        ref.watch(followProvider).processingFollowRequests.contains(userId));