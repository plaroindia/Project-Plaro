// ================================================================
// freelance_provider.dart
//
// Handles:
//   - FreelancePost model (maps get_freelance_feed RPC result)
//   - FreelanceFeedNotifier: paginated feed, apply, withdraw
//   - FreelanceApplicationsNotifier: post-author view of applicants
//   - canApply() gating helper (rank + pro check)
//   - Notifications on apply (notifies post author via
//     NotificationsNotifier.insert with type='freelance')
//
// DB dependencies (all migrations already applied):
//   post.is_freelance, post.freelance_budget, post.freelance_deadline,
//   post.freelance_min_rank, post.freelance_status, post.requires_pro
//   freelance_applications (id, post_id, applicant_id, message, status)
//   user_profiles.subscription_tier, user_profiles.pro_expires_at
//   get_freelance_feed(p_user_id, p_limit, p_offset) RPC
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notifications_provider.dart';
import 'auth_provider.dart';

// ── Rank ordering (mirrors DB CHECK constraint) ──────────────────────────────

const List<String> kRankOrder = [
  'beginner',
  'intermediate',
  'advanced',
  'expert',
  'master',
];

/// Returns true when [userRank] satisfies [postMinRank] and any pro gate.
bool canApply({
  required String? userRank,
  required String? postMinRank,
  required bool userIsPro,
  required bool postRequiresPro,
}) {
  if (userRank == null || postMinRank == null) return false;
  final userIdx = kRankOrder.indexOf(userRank.toLowerCase());
  final postIdx = kRankOrder.indexOf(postMinRank.toLowerCase());
  if (userIdx < 0 || postIdx < 0) return false;
  if (userIdx < postIdx) return false;
  if (postRequiresPro && !userIsPro) return false;
  return true;
}

// ── Model ─────────────────────────────────────────────────────────────────────

class FreelancePost {
  final int postId;
  final String title;
  final String? content;
  final String? domain;
  final String? freelanceBudget;
  final DateTime? freelanceDeadline;
  final String freelanceMinRank;
  final String freelanceStatus;
  final bool requiresPro;
  final DateTime createdAt;
  final String authorUsername;
  final String? authorProfilePic;
  // Computed server-side by the RPC:
  final String? userRank;    // current user's rank_level
  final String? userTier;    // current user's subscription_tier
  final bool isEligible;     // rank + pro gate already computed in Postgres
  final bool alreadyApplied;

  const FreelancePost({
    required this.postId,
    required this.title,
    this.content,
    this.domain,
    this.freelanceBudget,
    this.freelanceDeadline,
    required this.freelanceMinRank,
    required this.freelanceStatus,
    required this.requiresPro,
    required this.createdAt,
    required this.authorUsername,
    this.authorProfilePic,
    this.userRank,
    this.userTier,
    required this.isEligible,
    required this.alreadyApplied,
  });

  factory FreelancePost.fromRpc(Map<String, dynamic> m) {
    return FreelancePost(
      postId:          (m['post_id'] as num).toInt(),
      title:           (m['title'] as String?) ?? '(untitled)',
      content:         m['content'] as String?,
      domain:          m['domain'] as String?,
      freelanceBudget: m['freelance_budget'] as String?,
      freelanceDeadline: m['freelance_deadline'] == null
          ? null
          : DateTime.parse(m['freelance_deadline'] as String),
      freelanceMinRank: (m['freelance_min_rank'] as String?) ?? 'beginner',
      freelanceStatus:  (m['freelance_status']  as String?) ?? 'open',
      requiresPro:      (m['requires_pro']       as bool?)  ?? false,
      createdAt:        DateTime.parse(m['created_at'] as String),
      authorUsername:   (m['author_username']   as String?) ?? 'Unknown',
      authorProfilePic: m['author_profile_pic'] as String?,
      userRank:         m['user_rank']          as String?,
      userTier:         m['user_tier']          as String?,
      isEligible:       (m['is_eligible']       as bool?)   ?? false,
      alreadyApplied:   (m['already_applied']   as bool?)   ?? false,
    );
  }

  FreelancePost copyWith({bool? alreadyApplied}) => FreelancePost(
    postId: postId,
    title: title,
    content: content,
    domain: domain,
    freelanceBudget: freelanceBudget,
    freelanceDeadline: freelanceDeadline,
    freelanceMinRank: freelanceMinRank,
    freelanceStatus: freelanceStatus,
    requiresPro: requiresPro,
    createdAt: createdAt,
    authorUsername: authorUsername,
    authorProfilePic: authorProfilePic,
    userRank: userRank,
    userTier: userTier,
    isEligible: isEligible,
    alreadyApplied: alreadyApplied ?? this.alreadyApplied,
  );
}

// ── FreelanceApplication model ────────────────────────────────────────────────

class FreelanceApplication {
  final String id;
  final int postId;
  final String applicantId;
  final String? message;
  final String status; // pending | accepted | rejected | withdrawn
  final DateTime createdAt;
  // Enriched fields (for post-author view)
  final String? applicantUsername;
  final String? applicantProfilePic;
  final String? applicantRank;

  const FreelanceApplication({
    required this.id,
    required this.postId,
    required this.applicantId,
    this.message,
    required this.status,
    required this.createdAt,
    this.applicantUsername,
    this.applicantProfilePic,
    this.applicantRank,
  });

  factory FreelanceApplication.fromMap(Map<String, dynamic> m) {
    final profile = m['user_profiles'] as Map<String, dynamic>?;
    final rank = profile?['user_profile_rank'] as Map<String, dynamic>?;
    return FreelanceApplication(
      id:          m['id'] as String,
      postId:      (m['post_id'] as num).toInt(),
      applicantId: m['applicant_id'] as String,
      message:     m['message'] as String?,
      status:      (m['status'] as String?) ?? 'pending',
      createdAt:   DateTime.parse(m['created_at'] as String),
      applicantUsername:   profile?['username'] as String?,
      applicantProfilePic: profile?['profile_pic'] as String?,
      applicantRank:       rank?['rank_level'] as String?,
    );
  }

  FreelanceApplication copyWith({String? status}) => FreelanceApplication(
    id: id, postId: postId, applicantId: applicantId, message: message,
    status: status ?? this.status, createdAt: createdAt,
    applicantUsername: applicantUsername, applicantProfilePic: applicantProfilePic,
    applicantRank: applicantRank,
  );
}

// ── FreelanceFeed state ───────────────────────────────────────────────────────

class FreelanceFeedState {
  final List<FreelancePost> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? error;
  // Tracks which post IDs are mid-apply to prevent double-taps
  final Set<int> applyingPosts;

  const FreelanceFeedState({
    this.posts         = const [],
    this.isLoading     = false,
    this.isLoadingMore = false,
    this.hasMore       = true,
    this.error,
    this.applyingPosts = const {},
  });

  FreelanceFeedState copyWith({
    List<FreelancePost>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? error,
    bool clearError = false,
    Set<int>? applyingPosts,
  }) => FreelanceFeedState(
    posts:         posts         ?? this.posts,
    isLoading:     isLoading     ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMore:       hasMore       ?? this.hasMore,
    error:         clearError ? null : (error ?? this.error),
    applyingPosts: applyingPosts ?? this.applyingPosts,
  );
}

// ── FreelanceFeedNotifier ─────────────────────────────────────────────────────

class FreelanceFeedNotifier extends StateNotifier<FreelanceFeedState> {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _pageSize = 20;

  FreelanceFeedNotifier() : super(const FreelanceFeedState());

  String? get _userId => _supabase.auth.currentUser?.id;

  // ── Load / paginate ────────────────────────────────────────────────────────

  Future<void> loadFeed() async {
    if (_userId == null) return;
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final rows = await _supabase.rpc(
        'get_freelance_feed',
        params: {
          'p_user_id': _userId,
          'p_limit':   _pageSize,
          'p_offset':  0,
        },
      ) as List;

      final posts = rows
          .map((r) => FreelancePost.fromRpc(r as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        posts:     posts,
        isLoading: false,
        hasMore:   posts.length == _pageSize,
      );
    } catch (e) {
      debugPrint('[FreelanceFeed] loadFeed error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (_userId == null || !state.hasMore || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final rows = await _supabase.rpc(
        'get_freelance_feed',
        params: {
          'p_user_id': _userId,
          'p_limit':   _pageSize,
          'p_offset':  state.posts.length,
        },
      ) as List;

      final more = rows
          .map((r) => FreelancePost.fromRpc(r as Map<String, dynamic>))
          .toList();

      state = state.copyWith(
        posts:         [...state.posts, ...more],
        isLoadingMore: false,
        hasMore:       more.length == _pageSize,
      );
    } catch (e) {
      debugPrint('[FreelanceFeed] loadMore error: $e');
      state = state.copyWith(isLoadingMore: false, error: e.toString());
    }
  }

  Future<void> refresh() => loadFeed();

  // ── Apply ──────────────────────────────────────────────────────────────────

  /// Returns null on success, or an error string on failure.
  Future<String?> apply({
    required int postId,
    required String message,
  }) async {
    final userId = _userId;
    if (userId == null) return 'Not authenticated';

    // Find the post in state for eligibility check and author lookup
    final postIdx = state.posts.indexWhere((p) => p.postId == postId);
    if (postIdx == -1) return 'Post not found';
    final post = state.posts[postIdx];

    // Client-side gate (server RLS is the real guard)
    if (!post.isEligible) {
      if (post.requiresPro && post.userTier != 'pro') {
        return 'This post requires a Pro subscription';
      }
      return 'Your rank (${post.userRank ?? 'unknown'}) does not meet the minimum required rank (${post.freelanceMinRank})';
    }

    if (post.alreadyApplied) return 'You have already applied to this post';

    // Debounce
    if (state.applyingPosts.contains(postId)) return null;
    state = state.copyWith(applyingPosts: {...state.applyingPosts, postId});

    try {
      await _supabase.from('freelance_applications').upsert({
    'post_id':      postId,
    'applicant_id': userId,
    'message':      message.trim().isEmpty ? null : message.trim(),
    'status':       'pending',   // reset to pending on re-apply
  },
  onConflict: 'post_id,applicant_id',
);

      // Optimistic update — mark as applied in the list
      final updated = List<FreelancePost>.from(state.posts);
      updated[postIdx] = post.copyWith(alreadyApplied: true);
      state = state.copyWith(
        posts:         updated,
        applyingPosts: {...state.applyingPosts}..remove(postId),
      );

      // Fetch post author's user_id so we can notify them.
      // The RPC only returns username/pic, not user_id, so one extra query.
      _notifyAuthorOnApply(postId: postId, applicantId: userId);

      return null; // success
    } catch (e) {
      debugPrint('[FreelanceFeed] apply error: $e');
      state = state.copyWith(
        applyingPosts: {...state.applyingPosts}..remove(postId),
        error:         e.toString(),
      );
      return 'Failed to apply. Please try again.';
    }
  }

  /// Fire-and-forget — does not block the apply return value.
  Future<void> _notifyAuthorOnApply({
    required int postId,
    required String applicantId,
  }) async {
    try {
      final results = await Future.wait([
        _supabase
            .from('post')
            .select('user_id')
            .eq('post_id', postId)
            .maybeSingle(),
        _supabase
            .from('user_profiles')
            .select('username')
            .eq('user_id', applicantId)
            .maybeSingle(),
      ]);

      final postRow      = results[0] as Map<String, dynamic>?;
      final applicantRow = results[1] as Map<String, dynamic>?;

      if (postRow == null) return;
      final authorId = postRow['user_id'] as String?;
      if (authorId == null || authorId == applicantId) return;

      final applicantName = applicantRow?['username'] as String? ?? 'Someone';

      await NotificationsNotifier.insert(
        targetUserId: authorId,
        type:         'freelance',
        title:        'New application on your post',
        body:         '$applicantName applied for your freelance task',
        relatedType:  'post',
        relatedId:    postId.toString(),
      );
    } catch (e) {
      debugPrint('[FreelanceFeed] _notifyAuthorOnApply error (non-fatal): $e');
    }
  }

  // ── Withdraw ───────────────────────────────────────────────────────────────

  /// Withdraws the current user's application for [postId].
  Future<String?> withdraw({required int postId}) async {
    final userId = _userId;
    if (userId == null) return 'Not authenticated';

    try {
      await _supabase
          .from('freelance_applications')
          .update({'status': 'withdrawn'})
          .eq('post_id',      postId)
          .eq('applicant_id', userId);

      // Optimistic update
      final idx = state.posts.indexWhere((p) => p.postId == postId);
      if (idx != -1) {
        final updated = List<FreelancePost>.from(state.posts);
        updated[idx] = state.posts[idx].copyWith(alreadyApplied: false);
        state = state.copyWith(posts: updated);
      }
      return null;
    } catch (e) {
      debugPrint('[FreelanceFeed] withdraw error: $e');
      return 'Failed to withdraw application.';
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ── FreelanceApplications state (post-author view) ───────────────────────────

class FreelanceApplicationsState {
  final List<FreelanceApplication> applications;
  final bool isLoading;
  final String? error;

  const FreelanceApplicationsState({
    this.applications = const [],
    this.isLoading    = false,
    this.error,
  });

  FreelanceApplicationsState copyWith({
    List<FreelanceApplication>? applications,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) => FreelanceApplicationsState(
    applications: applications ?? this.applications,
    isLoading:    isLoading    ?? this.isLoading,
    error:        clearError ? null : (error ?? this.error),
  );
}

// ── FreelanceApplicationsNotifier ────────────────────────────────────────────

class FreelanceApplicationsNotifier
    extends StateNotifier<FreelanceApplicationsState> {
  final int postId;
  final SupabaseClient _supabase = Supabase.instance.client;

  FreelanceApplicationsNotifier(this.postId)
      : super(const FreelanceApplicationsState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final rows = await _supabase
          .from('freelance_applications')
          .select('''
            id, post_id, applicant_id, message, status, created_at,
            user_profiles (
            username,
            profile_pic,
             user_profile_rank ( rank_level )
            )
          ''')
          .eq('post_id', postId)
          .order('created_at', ascending: true);

      state = state.copyWith(
        applications: (rows as List)
            .map((r) => FreelanceApplication.fromMap(r as Map<String, dynamic>))
            .toList(),
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[FreelanceApplications] load error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Post author accepts an application and closes the post to further applies.
  Future<String?> accept(String applicationId) async {
    return _updateStatus(applicationId, 'accepted', closePost: true);
  }

  /// Post author rejects an application.
  Future<String?> reject(String applicationId) async {
    return _updateStatus(applicationId, 'rejected');
  }

  Future<String?> _updateStatus(
    String applicationId,
    String newStatus, {
    bool closePost = false,
  }) async {
    try {
      await _supabase
          .from('freelance_applications')
          .update({'status': newStatus})
          .eq('id', applicationId);

      if (closePost) {
        await _supabase
            .from('post')
            .update({'freelance_status': 'filled'})
            .eq('post_id', postId);
      }

      // Optimistic update
      final updated = state.applications.map((a) {
        if (a.id == applicationId) return a.copyWith(status: newStatus);
        return a;
      }).toList();
      state = state.copyWith(applications: updated);

      // Notify the applicant
      final application = state.applications
          .firstWhere((a) => a.id == applicationId, orElse: () => throw Exception());

      final titleMsg = newStatus == 'accepted'
          ? 'Your freelance application was accepted 🎉'
          : 'Update on your freelance application';
      final bodyMsg = newStatus == 'accepted'
          ? 'The post author accepted your application!'
          : 'The post author reviewed your application.';

      await NotificationsNotifier.insert(
        targetUserId: application.applicantId,
        type:         'freelance',
        title:        titleMsg,
        body:         bodyMsg,
        relatedType:  'post',
        relatedId:    postId.toString(),
      );

      return null;
    } catch (e) {
      debugPrint('[FreelanceApplications] _updateStatus error: $e');
      return 'Failed to update application status.';
    }
  }

  Future<void> refresh() => load();
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Main freelance feed — use this in the freelance tab.
final freelanceFeedProvider =
    StateNotifierProvider<FreelanceFeedNotifier, FreelanceFeedState>((ref) {
  final notifier = FreelanceFeedNotifier();
  // Auto-load when auth user is present
  final session = ref.watch(authStateProvider).valueOrNull;
  if (session?.user != null) notifier.loadFeed();
  return notifier;
});

/// Per-post applicant list — for the post author to manage applications.
final freelanceApplicationsProvider = StateNotifierProvider.family<
    FreelanceApplicationsNotifier, FreelanceApplicationsState, int>(
  (ref, postId) => FreelanceApplicationsNotifier(postId),
);

/// Convenience: just the count of pending applications for a given post.
final pendingApplicationCountProvider =
    Provider.family<int, int>((ref, postId) {
  return ref
      .watch(freelanceApplicationsProvider(postId))
      .applications
      .where((a) => a.status == 'pending')
      .length;
});
