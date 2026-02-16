import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

// ─────────────────────────────────────────────
//  Models
// ─────────────────────────────────────────────

class EducatorReview {
  final String id;
  final String educatorId;
  final String username;
  final String? profilePic;
  final int rating;
  final double accuracyScore;
  final double authenticityScore; // maps to usefulness_score in DB
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
      // DB column usefulness_score is used as authenticity here
      // and accuracy_score doubled as usefulness in display.
      // We store: accuracy → accuracy, usefulness → authenticity, rating/5 → usefulness
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
  // Aggregates (derived from reviews)
  final double averageRating;
  final int totalRatings;
  final double avgAccuracy;
  final double avgAuthenticity;
  final double avgUsefulness;
  // Distribution 1-5
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

  /// Load all educator reviews for a given post
  Future<void> loadReviews() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rows = await _supabase
          .from('educator_content_reviews')
          .select('''
            id,
            educator_id,
            rating,
            accuracy_score,
            usefulness_score,
            feedback,
            created_at,
            user_profiles (
              username,
              profile_pic,
              role
            )
          ''')
          .eq('content_type', 'post')
          .eq('content_id_int', int.parse(postId))
          .order('created_at', ascending: false);

      // Only include educators and professionals
      final filtered = (rows as List)
          .where((r) =>
      r['user_profiles']?['role'] == 'educator' ||
          r['user_profiles']?['role'] == 'professional')
          .toList();

      final reviews =
      filtered.map((r) => EducatorReview.fromMap(r)).toList();

      _computeAggregates(reviews);
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
    final avgRating =
        reviews.map((r) => r.rating).reduce((a, b) => a + b) / total;
    final avgAcc =
        reviews.map((r) => r.accuracyScore).reduce((a, b) => a + b) / total;
    final avgAuth =
        reviews.map((r) => r.authenticityScore).reduce((a, b) => a + b) /
            total;
    final avgUse =
        reviews.map((r) => r.usefulnessScore).reduce((a, b) => a + b) / total;

    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) {
      dist[r.rating] = (dist[r.rating] ?? 0) + 1;
    }

    state = state.copyWith(
      reviews: reviews,
      isLoading: false,
      averageRating: avgRating,
      totalRatings: total,
      avgAccuracy: avgAcc,
      avgAuthenticity: avgAuth,
      avgUsefulness: avgUse,
      distribution: dist,
    );
  }

  /// Check if current educator already rated this post
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
      // Minimal EducatorReview without profile join
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

  /// Submit or update a rating
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
        // We map authenticityScore to DB usefulness_score column
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
      }

      await loadReviews();
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }
}

// ─────────────────────────────────────────────
//  Providers
// ─────────────────────────────────────────────

/// Family provider — one notifier per post ID
final postRatingProvider = StateNotifierProvider.family<PostRatingNotifier,
    PostRatingState, String>((ref, postId) {
  final notifier = PostRatingNotifier(postId);
  notifier.loadReviews();
  return notifier;
});

/// Whether the current user is a professional or educator who can rate content.
///
/// IMPORTANT — cache-bust on auth change:
/// By watching [authStateProvider] the FutureProvider re-evaluates every time
/// the session changes (login, logout, token refresh).  Without this, Riverpod
/// caches the result from the previous user and the Rate button shows/hides
/// based on whoever was logged in first — hot-reload was the only fix in dev,
/// and production users would be stuck until an app restart.
final isVerifiedProfessionalProvider = FutureProvider<bool>((ref) async {
  // Watch the auth stream — any session change triggers a re-evaluation.
  final session = ref.watch(authStateProvider).valueOrNull;

  // No session → definitely not a professional.
  final userId = session?.user.id;
  if (userId == null) return false;

  try {
    final row = await Supabase.instance.client
        .from('user_profiles')
        .select('role')
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return false;
    final role = row['role'] as String?;
    return role == 'professional' || role == 'educator';
  } catch (_) {
    return false;
  }
});