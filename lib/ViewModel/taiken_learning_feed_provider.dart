// =============================================================================
// taiken_learning_feed_provider.dart  — FIXED v3
//
// Root cause identified from DB screenshot:
//   The `skill` column in pearl_content_recommendations stores the domain
//   (e.g. 'biological_sciences', 'engineering_general'). The RPC
//   get_user_feed accepts p_domain and filters on pcr.skill = p_domain
//   server-side. The Flutter code was NOT passing p_domain, so the RPC
//   returned items from ALL skills mixed together. The client-side
//   filter on i['domain'] (which comes from the content table's own domain
//   column — often NULL or mismatched) then silently dropped everything.
//
// Fixes in this version:
//   1. Pass p_domain to get_user_feed RPC → server filters pcr.skill = domain
//      This is the reliable field and is what the DB actually stores.
//   2. Remove unreliable client-side domain filter (was filtering on content
//      table's domain col which can be NULL/mismatched vs pcr.skill).
//   3. LearningFeedItem gains userId, commentCount, tags, createdAt fields
//      so PostCard has everything needed for like/comment/ownership.
//   4. _fetchBytesDirect: second-chance fallback if domain-filtered query
//      returns empty (handles bytes with NULL domain column).
//   5. _fetchPostsDirect: selects user_id + comment_count for PostCard.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum LearningItemType { byte, post }

class LearningFeedItem {
  final String id;
  final LearningItemType type;

  // Content
  final String? title;
  final String? body;
  final String? thumbnailUrl;
  final String? videoUrl;         // bytes only
  final List<String> mediaUrls;   // posts: image URLs
  final List<String> tags;
  final String? domain;

  // Author — userId needed so PostCard can check ownership
  final String userId;
  final String username;
  final String? profilePic;

  // Engagement
  final int likeCount;
  final int commentCount;
  final double relevanceScore;

  // Timestamps
  final DateTime? createdAt;

  const LearningFeedItem({
    required this.id,
    required this.type,
    this.title,
    this.body,
    this.thumbnailUrl,
    this.videoUrl,
    this.mediaUrls = const [],
    this.tags = const [],
    this.domain,
    this.userId = '',
    required this.username,
    this.profilePic,
    this.likeCount = 0,
    this.commentCount = 0,
    this.relevanceScore = 0.5,
    this.createdAt,
  });

  bool get isByte => type == LearningItemType.byte;
  bool get isPost => type == LearningItemType.post;
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class LearningFeedState {
  final List<LearningFeedItem> items;
  final bool isLoading;
  final bool hasMore;
  final String? error;
  final int bytesWatched;
  final int postsRead;
  final int secondsSpent;

  const LearningFeedState({
    this.items       = const [],
    this.isLoading   = false,
    this.hasMore     = true,
    this.error,
    this.bytesWatched = 0,
    this.postsRead    = 0,
    this.secondsSpent = 0,
  });

  LearningFeedState copyWith({
    List<LearningFeedItem>? items,
    bool? isLoading,
    bool? hasMore,
    String? error,
    bool clearError = false,
    int? bytesWatched,
    int? postsRead,
    int? secondsSpent,
  }) {
    return LearningFeedState(
      items:        items        ?? this.items,
      isLoading:    isLoading    ?? this.isLoading,
      hasMore:      hasMore      ?? this.hasMore,
      error:        clearError ? null : (error ?? this.error),
      bytesWatched: bytesWatched ?? this.bytesWatched,
      postsRead:    postsRead    ?? this.postsRead,
      secondsSpent: secondsSpent ?? this.secondsSpent,
    );
  }

  /// Threshold: watched ≥1 byte OR read ≥1 post, AND spent ≥10 seconds.
  bool get isReadyToReturn =>
      (bytesWatched >= 1 || postsRead >= 1) && secondsSpent >= 10;
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class LearningFeedNotifier extends StateNotifier<LearningFeedState> {
  LearningFeedNotifier({required this.taikenId, required this.domain})
      : super(const LearningFeedState());

  final String taikenId;
  final String domain;

  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _pageSize = 12;

  double? _nextCursorScore;
  String? _nextCursorId;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load({bool refresh = false}) async {
    if (state.isLoading) return;

    if (refresh) {
      _nextCursorScore = null;
      _nextCursorId    = null;
      state = const LearningFeedState(isLoading: true);
    } else {
      if (!state.hasMore) return;
      state = state.copyWith(isLoading: true);
    }

    try {
      final items = await _fetchFromRpc();

      // RPC returned nothing (or nothing for this domain) → go to fallback
      if (items.isEmpty && refresh) {
        await _loadFallback(refresh: true);
        return;
      }

      state = state.copyWith(
        items:      refresh ? items : [...state.items, ...items],
        isLoading:  false,
        hasMore:    items.length == _pageSize,
        clearError: true,
      );
    } catch (e) {
      debugPrint('[LearningFeed] RPC failed ($e), using direct fallback');
      await _loadFallback(refresh: refresh);
    }
  }

  // ── RPC path ──────────────────────────────────────────────────────────────
  // The `skill` column in pearl_content_recommendations stores the domain
  // (confirmed from DB screenshot). get_user_feed accepts p_domain and
  // filters server-side on pcr.skill = p_domain — this is the correct,
  // reliable field. Passing it here means we get ONLY items recommended
  // for this skill/domain. Without it, ALL domains were returned and the
  // old client-side filter on i['domain'] (content table col, often NULL)
  // silently dropped everything — that was the root cause of bytes not loading.

  Future<List<LearningFeedItem>> _fetchFromRpc() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final params = <String, dynamic>{
      'p_limit':         _pageSize,
      'p_content_types': ['byte', 'post'],
      // KEY FIX: pass domain so RPC filters pcr.skill = p_domain server-side
      'p_domain':        domain,
    };

    if (_nextCursorScore != null) {
      params['p_cursor_score'] = _nextCursorScore;
      params['p_cursor_id']   = _nextCursorId;
    }

    final data = await _supabase.rpc('get_user_feed', params: params)
    as Map<String, dynamic>;

    _nextCursorScore = (data['nextCursorScore'] as num?)?.toDouble();
    _nextCursorId    = data['nextCursorId'] as String?;

    // No client-side domain filter needed — RPC already filtered by pcr.skill
    final all = (data['items'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .where((i) => i['contentType'] == 'byte' || i['contentType'] == 'post')
        .map(_parseRpcItem)
        .toList();

    return all;
  }

  LearningFeedItem _parseRpcItem(Map<String, dynamic> i) {
    final isByte    = i['contentType'] == 'byte';
    final mediaUrls = (i['mediaUrls'] as List?)?.cast<String>() ?? [];

    return LearningFeedItem(
      id:            i['contentId'] as String,
      type:          isByte ? LearningItemType.byte : LearningItemType.post,
      title:         i['title']        as String?,
      body:          i['body']         as String?,
      thumbnailUrl:  i['thumbnailUrl'] as String?,
      videoUrl:      isByte && mediaUrls.isNotEmpty ? mediaUrls[0] : null,
      mediaUrls:     isByte ? [] : mediaUrls,
      tags:          (i['tags'] as List?)?.cast<String>() ?? [],
      domain:        i['domain']       as String?,
      // ── FIX 2: userId from RPC so PostCard can check ownership ──
      userId:        i['userId']       as String? ?? '',
      username:      i['username']     as String? ?? 'Unknown',
      profilePic:    i['profilePic']   as String?,
      likeCount:     (i['likeCount']   as num?)?.toInt() ?? 0,
      // ── FIX 3: commentCount was missing ──
      commentCount:  (i['commentCount'] as num?)?.toInt() ?? 0,
      relevanceScore:(i['relevanceScore'] as num?)?.toDouble() ?? 0.5,
      createdAt:     i['createdAt'] != null
          ? DateTime.tryParse(i['createdAt'] as String)
          : null,
    );
  }

  // ── Fallback: direct DB queries ───────────────────────────────────────────

  Future<void> _loadFallback({required bool refresh}) async {
    try {
      final results = await Future.wait([
        _fetchBytesDirect(),
        _fetchPostsDirect(),
      ]);
      final bytes = results[0];
      final posts = results[1];

      // Interleave byte, post, byte, post…
      final merged = <LearningFeedItem>[];
      final maxLen = bytes.length > posts.length ? bytes.length : posts.length;
      for (var i = 0; i < maxLen; i++) {
        if (i < bytes.length) merged.add(bytes[i]);
        if (i < posts.length) merged.add(posts[i]);
      }

      debugPrint('[LearningFeed] Fallback loaded '
          '${bytes.length} bytes + ${posts.length} posts');

      state = state.copyWith(
        items:      refresh ? merged : [...state.items, ...merged],
        isLoading:  false,
        hasMore:    false,
        clearError: true,
      );
    } catch (e) {
      debugPrint('[LearningFeed] Fallback also failed: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load learning content: $e',
      );
    }
  }

  /// Direct bytes query — domain-filtered with a second-chance fallback
  /// if no bytes exist for this domain.
  Future<List<LearningFeedItem>> _fetchBytesDirect() async {
    // ── FIX 4: try domain-filtered first; if empty, return all recent bytes ──
    Future<List> _query({bool withDomain = true}) async {
      var q = _supabase
          .from('bytes')
          .select(
          'byte_id, byte, caption, like_count, thumbnail_url, domain, '
              'user_id, created_at, updated_at, '
              'user_profiles!bytes_user_id_fkey(username, profile_pic)')
          .eq('is_hidden', false);
      if (withDomain) q = q.eq('domain', domain);
      return await q.order('created_at', ascending: false).limit(6) as List;
    }

    var rows = await _query(withDomain: true);
    // Second-chance: domain might be null on old bytes, widen the search
    if (rows.isEmpty) {
      debugPrint('[LearningFeed] No bytes for domain "$domain", '
          'widening to all bytes');
      rows = await _query(withDomain: false);
    }

    return rows.map((r) {
      final profile = r['user_profiles'] as Map<String, dynamic>? ?? {};
      return LearningFeedItem(
        id:           (r['byte_id'] as int).toString(),
        type:         LearningItemType.byte,
        body:         r['caption']       as String?,
        videoUrl:     r['byte']          as String?,
        thumbnailUrl: r['thumbnail_url'] as String?,
        domain:       r['domain']        as String?,
        userId:       r['user_id']       as String? ?? '',
        username:     profile['username']    as String? ?? 'Unknown',
        profilePic:   profile['profile_pic'] as String?,
        likeCount:    (r['like_count'] as int?) ?? 0,
        createdAt:    r['created_at'] != null
            ? DateTime.tryParse(r['created_at'] as String)
            : null,
      );
    }).toList();
  }

  /// Direct posts query — selects user_id, comment_count so PostCard has
  /// all the data it needs for likes / comments / ownership checks.
  Future<List<LearningFeedItem>> _fetchPostsDirect() async {
    // ── FIX 5: select user_id + comment_count ──
    final rows = await _supabase
        .from('post')
        .select(
        'post_id, user_id, title, content, like_count, comment_count, '
            'media_urls, tags, domain, created_at, '
            'user_profiles!inner(username, profile_pic)')
        .eq('is_hidden', false)
        .eq('is_published', true)
        .eq('domain', domain)
        .order('created_at', ascending: false)
        .limit(6);

    return (rows as List).map((r) {
      final profile   = r['user_profiles'] as Map<String, dynamic>? ?? {};
      final mediaUrls = (r['media_urls'] as List?)?.cast<String>() ?? [];
      return LearningFeedItem(
        id:           (r['post_id'] as int).toString(),
        type:         LearningItemType.post,
        title:        r['title']         as String?,
        body:         r['content']       as String?,
        mediaUrls:    mediaUrls,
        thumbnailUrl: mediaUrls.isNotEmpty ? mediaUrls[0] : null,
        tags:         (r['tags'] as List?)?.cast<String>() ?? [],
        domain:       r['domain']        as String?,
        userId:       r['user_id']       as String? ?? '',
        username:     profile['username']    as String? ?? 'Unknown',
        profilePic:   profile['profile_pic'] as String?,
        likeCount:    (r['like_count']   as int?) ?? 0,
        commentCount: (r['comment_count'] as int?) ?? 0,
        createdAt:    r['created_at'] != null
            ? DateTime.tryParse(r['created_at'] as String)
            : null,
      );
    }).toList();
  }

  // ── Engagement tracking ────────────────────────────────────────────────────

  void recordByteWatched() =>
      state = state.copyWith(bytesWatched: state.bytesWatched + 1);

  void recordPostRead() =>
      state = state.copyWith(postsRead: state.postsRead + 1);

  void recordSeconds(int seconds) =>
      state = state.copyWith(secondsSpent: state.secondsSpent + seconds);

  void clearError() => state = state.copyWith(clearError: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final taikenLearningFeedProvider = StateNotifierProvider.family<
    LearningFeedNotifier,
    LearningFeedState,
    ({String taikenId, String domain})>(
      (ref, args) => LearningFeedNotifier(
    taikenId: args.taikenId,
    domain:   args.domain,
  ),
);