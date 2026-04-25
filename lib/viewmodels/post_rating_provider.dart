// ================================================================
// post_rating_provider.dart  (UPDATED)
//
// Change from original:
//   - submitRating inserts a 'rating' notification to the post
//     author after a successful submission.
// ================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'notifications_provider.dart'; // NEW

// ─────────────────────────────────────────────
//  Models (unchanged)
// ─────────────────────────────────────────────

class EducatorReview {
  final String id;
  final String educatorId;
  final String username;
  final String? profilePic;
  final int rating;
  final double accuracyScore;
  final double authenticityScore;
  final double usefulnessScore;
  final String? feedback;
  final DateTime createdAt;

  const EducatorReview({
    required this.id,
    required this.educatorId,
    required this.username,
    this.profilePic,
    required this.rating,
    required this.accuracyScore,
    required this.authenticityScore,
    required this.usefulnessScore,
    this.feedback,
    required this.createdAt,
  });

  factory EducatorReview.fromMap(Map<String, dynamic> m) {
    return EducatorReview(
      id: m['id'] as String,
      educatorId: m['educator_id'] as String,
      username: (m['user_profiles']?['username'] as String?) ?? 'Unknown',
      profilePic: m['user_profiles']?['profile_pic'] as String?,
      rating: (m['rating'] as num).toInt(),
      accuracyScore: (m['accuracy_score'] as num?)?.toDouble() ?? 0.0,
      authenticityScore: (m['usefulness_score'] as num?)?.toDouble() ?? 0.0,
      usefulnessScore: (m['rating'] as num).toDouble() / 5.0,
      feedback: m['feedback'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }
}

class PostRatingState {
  final List<EducatorReview> reviews;
  final bool isLoading;
  final bool isSubmitting;
  final String? error;
  final double averageRating;
  final int totalRatings;
  final double avgAccuracy;
  final double avgAuthenticity;
  final double avgUsefulness;
  final Map<int, int> distribution;

  const PostRatingState({
    this.reviews = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.error,
    this.averageRating = 0.0,
    this.totalRatings = 0,
    this.avgAccuracy = 0.0,
    this.avgAuthenticity = 0.0,
    this.avgUsefulness = 0.0,
    this.distribution = const {},
  });

  PostRatingState copyWith({
    List<EducatorReview>? reviews,
    bool? isLoading,
    bool? isSubmitting,
    String? error,
    double? averageRating,
    int? totalRatings,
    double? avgAccuracy,
    double? avgAuthenticity,
    double? avgUsefulness,
    Map<int, int>? distribution,
  }) {
    return PostRatingState(
      reviews: reviews ?? this.reviews,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      error: error,
      averageRating: averageRating ?? this.averageRating,
      totalRatings: totalRatings ?? this.totalRatings,
      avgAccuracy: avgAccuracy ?? this.avgAccuracy,
      avgAuthenticity: avgAuthenticity ?? this.avgAuthenticity,
      avgUsefulness: avgUsefulness ?? this.avgUsefulness,
      distribution: distribution ?? this.distribution,
    );
  }
}

// ─────────────────────────────────────────────
//  Notifier
// ─────────────────────────────────────────────

class PostRatingNotifier extends StateNotifier<PostRatingState> {
  final String postId;
  final SupabaseClient _supabase = Supabase.instance.client;

  PostRatingNotifier(this.postId) : super(const PostRatingState());

  Future<void> loadReviews() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rows = await _supabase
          .from('educator_content_reviews')
          .select('''
            id, educator_id, rating, accuracy_score,
            usefulness_score, feedback, created_at,
            user_profiles ( username, profile_pic, role )
          ''')
          .eq('content_type', 'post')
          .eq('content_id_int', int.parse(postId))
          .order('created_at', ascending: false);

      final filtered = (rows as List)
          .where((r) {
        final role = (r['user_profiles']?['role'] as String?)?.toLowerCase();
        return role == 'educator' || role == 'professional';
      }).toList();

      _computeAggregates(
          filtered.map((r) => EducatorReview.fromMap(r)).toList());
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _computeAggregates(List<EducatorReview> reviews) {
    if (reviews.isEmpty) {
      state = state.copyWith(
        reviews: reviews,
        isLoading: false,
        averageRating: 0.0,
        totalRatings: 0,
        avgAccuracy: 0.0,
        avgAuthenticity: 0.0,
        avgUsefulness: 0.0,
        distribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
      );
      return;
    }

    final total = reviews.length;
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      dist[r.rating] = (dist[r.rating] ?? 0) + 1;
    }

    state = state.copyWith(
      reviews: reviews,
      isLoading: false,
      averageRating:
      reviews.map((r) => r.rating).reduce((a, b) => a + b) / total,
      totalRatings: total,
      avgAccuracy:
      reviews.map((r) => r.accuracyScore).reduce((a, b) => a + b) / total,
      avgAuthenticity:
      reviews.map((r) => r.authenticityScore).reduce((a, b) => a + b) /
          total,
      avgUsefulness:
      reviews.map((r) => r.usefulnessScore).reduce((a, b) => a + b) /
          total,
      distribution: dist,
    );
  }

  Future<EducatorReview?> getMyReview() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final row = await _supabase
          .from('educator_content_reviews')
          .select()
          .eq('educator_id', userId)
          .eq('content_type', 'post')
          .eq('content_id_int', int.parse(postId))
          .maybeSingle();
      if (row == null) return null;
      return EducatorReview(
        id: row['id'],
        educatorId: row['educator_id'],
        username: '',
        rating: (row['rating'] as num).toInt(),
        accuracyScore: (row['accuracy_score'] as num?)?.toDouble() ?? 0.0,
        authenticityScore:
        (row['usefulness_score'] as num?)?.toDouble() ?? 0.0,
        usefulnessScore: (row['rating'] as num).toDouble() / 5.0,
        feedback: row['feedback'],
        createdAt: DateTime.parse(row['created_at']),
      );
    } catch (_) {
      return null;
    }
  }

  // UPDATED: notify post author on successful rating
  Future<bool> submitRating({
    required int rating,
    required double accuracyScore,
    required double authenticityScore,
    required double usefulnessScore,
    String? feedback,
    String? existingReviewId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return false;

    state = state.copyWith(isSubmitting: true, error: null);

    try {
      final payload = {
        'educator_id': userId,
        'content_type': 'post',
        'content_id_int': int.parse(postId),
        'rating': rating,
        'accuracy_score': accuracyScore,
        'usefulness_score': authenticityScore,
        if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
      };

      if (existingReviewId != null) {
        await _supabase
            .from('educator_content_reviews')
            .update(payload)
            .eq('id', existingReviewId);
      } else {
        await _supabase.from('educator_content_reviews').insert(payload);
        // Only notify on new rating, not updates
        _sendRatingNotification(userId: userId, rating: rating);
      }

      await loadReviews();
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  // Fire-and-forget — does not block or throw
  Future<void> _sendRatingNotification({
    required String userId,
    required int rating,
  }) async {
    try {
      // Fetch post author and rater username in parallel
      final results = await Future.wait([
        _supabase
            .from('post')
            .select('user_id')
            .eq('post_id', int.parse(postId))
            .maybeSingle(),
        _supabase
            .from('user_profiles')
            .select('username')
            .eq('user_id', userId)
            .maybeSingle(),
      ]);

      final postRow = results[0] as Map<String, dynamic>?;
      final raterRow = results[1] as Map<String, dynamic>?;

      if (postRow == null) return;
      final authorId = postRow['user_id'] as String?;
      if (authorId == null || authorId == userId) return; // don't self-notify

      final raterName = raterRow?['username'] as String? ?? 'An educator';
      final stars = '★' * rating + '☆' * (5 - rating);

      await NotificationsNotifier.insert(
        targetUserId: authorId,
        type: 'rating',
        title: 'Your post was rated $stars',
        body: '$raterName rated your post $rating out of 5',
        relatedType: 'post',
        relatedId: postId,
      );
    } catch (e) {
      // Non-fatal
    }
  }
}

// ─────────────────────────────────────────────
//  Providers (unchanged)
// ─────────────────────────────────────────────

final postRatingProvider = StateNotifierProvider.family<PostRatingNotifier,
    PostRatingState, String>((ref, postId) {
  final notifier = PostRatingNotifier(postId);
  notifier.loadReviews();
  return notifier;
});

final isVerifiedProfessionalProvider = FutureProvider<bool>((ref) async {
  ref.watch(authStateProvider);

  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) {
    debugPrint('[RoleCheck] No userId');
    return false;
  }

  try {
    final row = await Supabase.instance.client
        .from('user_profiles')
        .select('role')
        .eq('user_id', userId)
        .maybeSingle();

    debugPrint('[RoleCheck] userId=$userId row=$row');  // <-- ADD THIS

    if (row == null) return false;
    final role = row['role'] as String?;
    debugPrint('[RoleCheck] role=$role');  // <-- AND THIS
    return role?.toLowerCase() == 'professional' || role?.toLowerCase() == 'educator';

  } catch (e) {
    debugPrint('[RoleCheck] ERROR: $e');  // <-- AND THIS
    return false;
  }
});
