// FIXED VERSION:
//   - Automatically calls generate_user_recommendations when needed
//   - Checks if recommendations are stale/empty before fetching feed
//   - Adds proper error handling for recommendation generation
//   - All other functionality preserved

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Model/post.dart';
import '../Model/comment.dart';

// ─────────────────────────────────────────────────────────────
// Feed item model returned by get_user_feed RPC
// ─────────────────────────────────────────────────────────────

class FeedItem {
  final String  recommendationId;
  final String  contentType;   // post | byte | taiken
  final String  contentId;
  final String? title;
  final String? body;
  final int     likeCount;
  final int     commentCount;
  final int     shareCount;
  final List<String> tags;
  final List<String> mediaUrls;
  final String? thumbnailUrl;
  final String? domain;
  final DateTime createdAt;
  final String  username;
  final String? profilePic;
  final double  relevanceScore;
  final String? reason;

  const FeedItem({
    required this.recommendationId,
    required this.contentType,
    required this.contentId,
    this.title,
    this.body,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.tags = const [],
    this.mediaUrls = const [],
    this.thumbnailUrl,
    this.domain,
    required this.createdAt,
    required this.username,
    this.profilePic,
    required this.relevanceScore,
    this.reason,
  });

  factory FeedItem.fromJson(Map<String, dynamic> j) => FeedItem(
    recommendationId: j['recommendationId'] as String,
    contentType:  j['contentType'] as String,
    contentId:    j['contentId'] as String,
    title:        j['title'] as String?,
    body:         j['body'] as String?,
    likeCount:    (j['likeCount'] as num?)?.toInt() ?? 0,
    commentCount: (j['commentCount'] as num?)?.toInt() ?? 0,
    shareCount:   (j['shareCount'] as num?)?.toInt() ?? 0,
    tags:         (j['tags'] as List?)?.cast<String>() ?? [],
    mediaUrls:    (j['mediaUrls'] as List?)?.cast<String>() ?? [],
    thumbnailUrl: j['thumbnailUrl'] as String?,
    domain:       j['domain'] as String?,
    createdAt:    DateTime.parse(j['createdAt'] as String),
    username:     j['username'] as String? ?? 'Unknown',
    profilePic:   j['profilePic'] as String?,
    relevanceScore: (j['relevanceScore'] as num?)?.toDouble() ?? 0.0,
    reason:       j['reason'] as String?,
  );

  /// Convert to the legacy Post_feed model so existing UI widgets still work.
  Post_feed toPostFeed({bool isLiked = false}) => Post_feed(
    post_id:       contentId,
    user_id:       '',
    username:      username,
    profile_pic:   profilePic,
    content:       body,
    title:         title,
    tags:          tags,
    created_at:    createdAt,
    like_count:    likeCount,
    comment_count: commentCount,
    share_count:   shareCount,
    isliked:       isLiked,
    commentsList:  [],
    media_urls:    mediaUrls,
  );
}

// ─────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────

class PostFeedState {
  final List<Post_feed> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final Set<String> likingPosts;
  final Set<String> likingComments;
  final bool hasMore;
  final int currentPage;
  final DateTime? lastFetchTime;

  // Cursor pagination state (replaces currentPage offset logic)
  final double? nextCursorScore;
  final String? nextCursorId;

  // NEW: Track if we're currently generating recommendations
  final bool isGeneratingRecommendations;

  const PostFeedState({
    this.posts = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.likingPosts = const {},
    this.likingComments = const {},
    this.hasMore = true,
    this.currentPage = 0,
    this.lastFetchTime,
    this.nextCursorScore,
    this.nextCursorId,
    this.isGeneratingRecommendations = false,
  });

  PostFeedState copyWith({
    List<Post_feed>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    Set<String>? likingPosts,
    Set<String>? likingComments,
    bool? hasMore,
    int? currentPage,
    DateTime? lastFetchTime,
    double? nextCursorScore,
    String? nextCursorId,
    bool clearCursor = false,
    bool? isGeneratingRecommendations,
  }) => PostFeedState(
    posts:           posts           ?? this.posts,
    isLoading:       isLoading       ?? this.isLoading,
    isLoadingMore:   isLoadingMore   ?? this.isLoadingMore,
    error:           error,
    likingPosts:     likingPosts     ?? this.likingPosts,
    likingComments:  likingComments  ?? this.likingComments,
    hasMore:         hasMore         ?? this.hasMore,
    currentPage:     currentPage     ?? this.currentPage,
    lastFetchTime:   lastFetchTime   ?? this.lastFetchTime,
    nextCursorScore: clearCursor ? null : (nextCursorScore ?? this.nextCursorScore),
    nextCursorId:    clearCursor ? null : (nextCursorId    ?? this.nextCursorId),
    isGeneratingRecommendations: isGeneratingRecommendations ?? this.isGeneratingRecommendations,
  );
}

// ─────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────

class PostFeedNotifier extends StateNotifier<PostFeedState> {
  PostFeedNotifier() : super(const PostFeedState());

  final SupabaseClient _supabase = Supabase.instance.client;

  static const int      _pageSize    = 15;
  static const Duration _cacheExpiry = Duration(minutes: 5);
  static const Duration _recommendationStaleThreshold = Duration(hours: 24);

  // In-memory like state & comment cache (unchanged from original)
  final Map<String, bool>          _likedCache    = {};
  final Map<String, List<Comment>> _commentCache  = {};

  // ── NEW: Check if user has fresh recommendations ────────────────────────

  /// Returns true if the user has recommendations that were created/updated
  /// within the last 24 hours. Returns false if empty or stale.
  Future<bool> _hasRecentRecommendations() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final response = await _supabase
          .from('pearl_content_recommendations')
          .select('created_at')
          .eq('user_id', user.id)
          .gte('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        debugPrint('[PostFeed] No recommendations found for user');
        return false;
      }

      final createdAt = DateTime.parse(response['created_at'] as String);
      final age = DateTime.now().difference(createdAt);

      debugPrint('[PostFeed] Latest recommendation age: ${age.inHours}h');
      return age < _recommendationStaleThreshold;
    } catch (e) {
      debugPrint('[PostFeed] Error checking recommendations: $e');
      return false;
    }
  }

  /// Calls the generate_user_recommendations RPC to populate
  /// pearl_content_recommendations for the current user.
  Future<void> _ensureRecommendationsExist() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    // Check if we already have fresh recommendations
    if (await _hasRecentRecommendations()) {
      debugPrint('[PostFeed] Recent recommendations exist, skipping generation');
      return;
    }

    debugPrint('[PostFeed] 🔄 Generating recommendations for user ${user.id}...');
    state = state.copyWith(isGeneratingRecommendations: true);

    try {
      // Call the RPC to generate recommendations
      await _supabase.rpc('generate_user_recommendations', params: {
        'p_user_id': user.id,
      });

      debugPrint('[PostFeed] ✅ Recommendations generated successfully');
    } catch (e) {
      debugPrint('[PostFeed] ⚠️ Failed to generate recommendations: $e');
      // Don't throw - we'll fall back to direct posts
    } finally {
      state = state.copyWith(isGeneratingRecommendations: false);
    }
  }

  // ── Feed loading via RPC ────────────────────────────────

  Future<void> loadPosts() async {
    if (state.isLoading) return;

    // Cache hit: skip refetch
    if (state.lastFetchTime != null &&
        DateTime.now().difference(state.lastFetchTime!) < _cacheExpiry &&
        state.posts.isNotEmpty) {
      debugPrint('[PostFeed] Using cached posts');
      return;
    }

    state = state.copyWith(isLoading: true, error: null, clearCursor: true);

    try {
      // 🔥 NEW: Ensure recommendations exist before fetching feed
      await _ensureRecommendationsExist();

      final data = await _supabase.rpc('get_user_feed', params: {
        'p_limit':         _pageSize,
        'p_content_types': ['post'],
      }) as Map<String, dynamic>;

      final items = _parseItems(data);

      // ── Fallback: pearl_content_recommendations is still empty
      //    (new user with no domain preferences, or generate failed)
      if (items.isEmpty) {
        debugPrint('[PostFeed] ⚠️ get_user_feed returned empty, using fallback');
        await _loadPostsDirectly();
        return;
      }

      final likedIds = await _batchCheckLikes(items);

      state = state.copyWith(
        posts:           items.map((i) => i.toPostFeed(isLiked: likedIds.contains(i.contentId))).toList(),
        isLoading:       false,
        hasMore:         items.length == _pageSize,
        currentPage:     1,
        lastFetchTime:   DateTime.now(),
        nextCursorScore: data['nextCursorScore'] as double?,
        nextCursorId:    data['nextCursorId'] as String?,
      );

      debugPrint('[PostFeed] ✅ Loaded ${items.length} personalized posts');
    } catch (e) {
      // RPC failed entirely — fall back to direct query
      debugPrint('[PostFeed] ❌ RPC failed, using direct fallback: $e');
      await _loadPostsDirectly();
    }
  }

  Future<void> loadMorePosts() async {
    if (state.isLoadingMore || !state.hasMore) return;
    if (state.nextCursorScore == null) return;

    state = state.copyWith(isLoadingMore: true, error: null);

    try {
      final data = await _supabase.rpc('get_user_feed', params: {
        'p_cursor_score':  state.nextCursorScore,
        'p_cursor_id':     state.nextCursorId,
        'p_limit':         _pageSize,
        'p_content_types': ['post'],
      }) as Map<String, dynamic>;

      final items = _parseItems(data);
      final likedIds = await _batchCheckLikes(items);

      // De-duplicate against existing posts
      final existingIds = state.posts.map((p) => p.post_id).toSet();
      final newPosts = items
          .where((i) => !existingIds.contains(i.contentId))
          .map((i) => i.toPostFeed(isLiked: likedIds.contains(i.contentId)))
          .toList();

      state = state.copyWith(
        posts:           [...state.posts, ...newPosts],
        isLoadingMore:   false,
        hasMore:         items.length == _pageSize,
        currentPage:     state.currentPage + 1,
        nextCursorScore: data['nextCursorScore'] as double?,
        nextCursorId:    data['nextCursorId'] as String?,
      );

      debugPrint('[PostFeed] ✅ Loaded ${newPosts.length} more posts (page ${state.currentPage})');
    } catch (e) {
      state = state.copyWith(isLoadingMore: false, error: 'Failed to load more: $e');
    }
  }

  Future<void> refreshPosts() async {
    debugPrint('[PostFeed] 🔄 Refreshing feed (clearing cache)...');
    _commentCache.clear();
    _likedCache.clear();

    // Clear state and force regeneration of recommendations
    state = const PostFeedState();

    // Force regenerate recommendations on refresh
    await _ensureRecommendationsExist();

    await loadPosts();
  }

  // ── Inject external posts (e.g. from TaikenLearningPage) ─────────────────
  // Merges posts into state so PostCard can find them for likes/comments.
  // Posts already present (same post_id) are not duplicated.
  void injectPosts(List<Post_feed> posts) {
    final existingIds = state.posts.map((p) => p.post_id).toSet();
    final newOnes = posts.where((p) => !existingIds.contains(p.post_id)).toList();
    if (newOnes.isEmpty) return;
    state = state.copyWith(posts: [...state.posts, ...newOnes]);
  }

  // ── Direct fallback: fetches from post table when RPC returns empty ─────────
  // Used when pearl_content_recommendations hasn't been seeded yet
  // (new user, recommendation pipeline still warming up).
  // Also called on RPC error so the feed always shows something.
  Future<void> _loadPostsDirectly() async {
    try {
      final user = _supabase.auth.currentUser;
      final response = await _supabase
          .from('post')
          .select('post_id,user_id,content,title,tags,domain,created_at,'
          'like_count,comment_count,share_count,is_published,'
          'media_urls,user_profiles!inner(username,profile_pic)')
          .eq('is_published', true)
          .eq('is_hidden', false)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      final posts = <Post_feed>[];
      final postIds = <int>[];
      for (final row in response as List) {
        final pid = row['post_id'] as int;
        postIds.add(pid);
        posts.add(Post_feed(
          post_id:       pid.toString(),
          user_id:       row['user_id'] as String,
          username:      row['user_profiles']['username'] as String,
          profile_pic:   row['user_profiles']['profile_pic'] as String?,
          content:       row['content'] as String?,
          title:         row['title'] as String?,
          tags:          (row['tags'] as List?)?.cast<String>() ?? [],
          created_at:    DateTime.parse(row['created_at'] as String),
          like_count:    row['like_count'] as int,
          comment_count: row['comment_count'] as int,
          share_count:   row['share_count'] as int,
          isliked:       false,
          commentsList:  [],
          media_urls:    (row['media_urls'] as List?)?.cast<String>() ?? [],
        ));
      }

      // Batch-check likes
      Set<String> likedIds = {};
      if (user != null && postIds.isNotEmpty) {
        try {
          final liked = await _supabase
              .from('post_likes')
              .select('post_id')
              .eq('user_id', user.id)
              .inFilter('post_id', postIds);
          likedIds = (liked as List)
              .map((r) => (r['post_id'] as int).toString())
              .toSet();
        } catch (_) {}
      }

      final finalPosts = posts
          .map((p) => p.copyWith(isliked: likedIds.contains(p.post_id)))
          .toList();

      state = state.copyWith(
        posts:         finalPosts,
        isLoading:     false,
        isLoadingMore: false,
        hasMore:       posts.length == _pageSize,
        currentPage:   1,
        lastFetchTime: DateTime.now(),
        // No cursor — direct mode uses page-based loading
        nextCursorScore: null,
        nextCursorId:    null,
      );
      debugPrint('[PostFeed] 📋 Fallback loaded ${finalPosts.length} posts directly');
    } catch (e) {
      state = state.copyWith(
        isLoading:     false,
        isLoadingMore: false,
        error:         'Failed to load posts: $e',
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────

  List<FeedItem> _parseItems(Map<String, dynamic> data) {
    final list = data['items'] as List? ?? [];
    return list.map((e) => FeedItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Set<String>> _batchCheckLikes(List<FeedItem> items) async {
    final user = _supabase.auth.currentUser;
    if (user == null || items.isEmpty) return {};

    try {
      final postIds = items
          .where((i) => i.contentType == 'post')
          .map((i) => int.tryParse(i.contentId))
          .whereType<int>()
          .toList();

      final byteIds = items
          .where((i) => i.contentType == 'byte')
          .map((i) => int.tryParse(i.contentId))
          .whereType<int>()
          .toList();

      final Set<String> liked = {};

      if (postIds.isNotEmpty) {
        final rows = await _supabase
            .from('post_likes')
            .select('post_id')
            .eq('user_id', user.id)
            .inFilter('post_id', postIds);
        for (final r in rows as List) {
          liked.add((r['post_id'] as int).toString());
        }
      }

      if (byteIds.isNotEmpty) {
        final rows = await _supabase
            .from('byte_likes')
            .select('byte_id')
            .eq('user_id', user.id)
            .inFilter('byte_id', byteIds);
        for (final r in rows as List) {
          liked.add((r['byte_id'] as int).toString());
        }
      }

      return liked;
    } catch (_) {
      return {};
    }
  }

  // ── Like (unchanged logic, same DB writes) ──────────────

  Future<void> toggleLike(String postId) async {
    if (state.likingPosts.contains(postId)) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    final idx = state.posts.indexWhere((p) => p.post_id == postId);
    if (idx == -1) return;

    final current = state.posts[idx];
    final nowLiked = !(current.isliked);

    final newPosts = [...state.posts];
    newPosts[idx] = current.copyWith(isliked: nowLiked);
    state = state.copyWith(
      posts:       newPosts,
      likingPosts: {...state.likingPosts, postId},
    );

    try {
      final postIdInt = int.parse(postId);
      if (current.isliked) {
        await _supabase.from('post_likes')
            .delete()
            .eq('post_id', postIdInt)
            .eq('user_id', user.id);
      } else {
        await _supabase.from('post_likes').insert({
          'post_id': postIdInt,
          'user_id': user.id,
          'liked_at': DateTime.now().toIso8601String(),
        });
      }
      state = state.copyWith(likingPosts: {...state.likingPosts}..remove(postId));
      await _reloadSinglePost(postId, idx);
    } catch (e) {
      final reverted = [...state.posts];
      reverted[idx] = current;
      state = state.copyWith(
        posts:       reverted,
        likingPosts: {...state.likingPosts}..remove(postId),
        error:       'Failed to update like',
      );
    }
  }

  Future<void> _reloadSinglePost(String postId, int index) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final postIdInt = int.parse(postId);
      final row = await _supabase
          .from('post')
          .select('post_id,user_id,content,title,tags,created_at,'
          'like_count,comment_count,share_count,is_published,'
          'media_urls,user_profiles!inner(username,profile_pic)')
          .eq('post_id', postIdInt)
          .single();

      final likeRow = await _supabase
          .from('post_likes')
          .select('post_id')
          .eq('user_id', user.id)
          .eq('post_id', postIdInt);
      final isLiked = (likeRow as List).isNotEmpty;

      final updated = Post_feed(
        post_id:      postId,
        user_id:      row['user_id'] as String,
        username:     row['user_profiles']['username'] as String,
        profile_pic:  row['user_profiles']['profile_pic'] as String?,
        content:      row['content'] as String?,
        title:        row['title'] as String?,
        tags:         (row['tags'] as List?)?.cast<String>() ?? [],
        created_at:   DateTime.parse(row['created_at'] as String),
        like_count:   row['like_count'] as int,
        comment_count: row['comment_count'] as int,
        share_count:  row['share_count'] as int,
        isliked:      isLiked,
        commentsList: [],
        media_urls:   (row['media_urls'] as List?)?.cast<String>() ?? [],
      );

      final newPosts = [...state.posts];
      if (index < newPosts.length) newPosts[index] = updated;
      state = state.copyWith(posts: newPosts);
    } catch (_) {}
  }

  // ── Comments (unchanged from original) ─────────────────

  Future<List<Comment>> loadComments(String postId) async {
    if (_commentCache.containsKey(postId)) return _commentCache[postId]!;

    final postIdInt = int.parse(postId);
    final user = _supabase.auth.currentUser;

    try {
      final response = await _supabase
          .from('post_comments')
          .select('*,user_profiles!inner(username,profile_pic)')
          .eq('post_id', postIdInt)
          .isFilter('parent_comment_id', null)
          .order('created_at', ascending: false);

      final commentIds = (response as List).map((c) => c['comment_id'] as int).toList();
      Set<int> likedIds = {};
      if (user != null && commentIds.isNotEmpty) {
        final liked = await _supabase
            .from('post_comment_likes')
            .select('comment_id')
            .eq('user_id', user.id)
            .inFilter('comment_id', commentIds);
        likedIds = (liked as List).map((e) => e['comment_id'] as int).toSet();
      }

      final comments = (response as List).map((c) => Comment.fromPostMap({
        ...c,
        'username':    c['user_profiles']['username'],
        'profile_pic': c['user_profiles']['profile_pic'],
        'isliked':     likedIds.contains(c['comment_id']),
      })).toList();

      _commentCache[postId] = comments;
      return comments;
    } catch (e) {
      state = state.copyWith(error: 'Failed to load comments: $e');
      return [];
    }
  }

  Future<bool> addComment(String postId, String content) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await _supabase.from('post_comments').insert({
        'post_id': int.parse(postId),
        'user_id': userId,
        'content': content,
        'created_at': DateTime.now().toIso8601String(),
      });
      _commentCache.remove(postId);
      final idx = state.posts.indexWhere((p) => p.post_id == postId);
      if (idx != -1) await _reloadSinglePost(postId, idx);
      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to add comment: $e');
      return false;
    }
  }

  Future<List<Comment>> loadReplies(String postId, int parentCommentId) async {
    final postIdInt = int.parse(postId);
    final user = _supabase.auth.currentUser;
    try {
      final response = await _supabase
          .from('post_comments')
          .select('*,user_profiles!inner(username,profile_pic)')
          .eq('post_id', postIdInt)
          .eq('parent_comment_id', parentCommentId)
          .order('created_at', ascending: false);

      final replyIds = (response as List).map((c) => c['comment_id'] as int).toList();
      Set<int> likedIds = {};
      if (user != null && replyIds.isNotEmpty) {
        final liked = await _supabase
            .from('post_comment_likes')
            .select('comment_id')
            .eq('user_id', user.id)
            .inFilter('comment_id', replyIds);
        likedIds = (liked as List).map((e) => e['comment_id'] as int).toSet();
      }
      return (response as List).map((c) => Comment.fromMap({
        ...c,
        'username':    c['user_profiles']['username'],
        'profile_pic': c['user_profiles']['profile_pic'],
        'uliked':      likedIds.contains(c['comment_id']),
      })).toList();
    } catch (e) {
      return [];
    }
  }

  Future<bool> addReply(String postId, int parentCommentId, String content) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;
    try {
      await _supabase.from('post_comments').insert({
        'post_id':           int.parse(postId),
        'user_id':           userId,
        'content':           content,
        'parent_comment_id': parentCommentId,
        'created_at':        DateTime.now().toIso8601String(),
      });
      final idx = state.posts.indexWhere((p) => p.post_id == postId);
      if (idx != -1) await _reloadSinglePost(postId, idx);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<int> getRepliesCount(int parentCommentId) async {
    try {
      final rows = await _supabase
          .from('post_comments')
          .select('comment_id')
          .eq('parent_comment_id', parentCommentId);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> toggleCommentLike(int commentId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final key = commentId.toString();
    if (state.likingComments.contains(key)) return;

    state = state.copyWith(likingComments: {...state.likingComments, key});
    try {
      final existing = await _supabase
          .from('post_comment_likes')
          .select('post_comment_like_id')
          .eq('comment_id', commentId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        await _supabase.from('post_comment_likes')
            .delete()
            .eq('post_comment_like_id', existing['post_comment_like_id'])
            .eq('user_id', userId);
      } else {
        await _supabase.from('post_comment_likes').insert({
          'comment_id': commentId,
          'user_id':    userId,
          'liked_at':   DateTime.now().toIso8601String(),
        });
      }
    } finally {
      state = state.copyWith(likingComments: {...state.likingComments}..remove(key));
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

// ─────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────

final postFeedProvider =
StateNotifierProvider<PostFeedNotifier, PostFeedState>((ref) {
  return PostFeedNotifier();
});