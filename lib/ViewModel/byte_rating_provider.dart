import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'post_rating_provider.dart';
import 'streakandpoints_provider.dart';

typedef ByteRatingState = PostRatingState;

class ByteRatingNotifier extends StateNotifier<ByteRatingState> {
  final String byteId;
  final Ref _ref;
  final SupabaseClient _supabase = Supabase.instance.client;

  ByteRatingNotifier(this.byteId, this._ref) : super(const PostRatingState());

  Future<void> loadReviews() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final rows = await _supabase
          .from('educator_content_reviews')
          .select('''
            id, educator_id, rating, accuracy_score, usefulness_score,
            feedback, created_at,
            user_profiles ( username, profile_pic, role )
          ''')
          .eq('content_type', 'byte')
          .eq('content_id_int', int.parse(byteId))
          .order('created_at', ascending: false);

      final filtered = (rows as List)
          .where((r) =>
      r['user_profiles']?['role'] == 'educator' ||
          r['user_profiles']?['role'] == 'professional')
          .toList();

      _setAggregates(filtered.map((r) => EducatorReview.fromMap(r)).toList());
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void _setAggregates(List<EducatorReview> reviews) {
    if (reviews.isEmpty) {
      state = state.copyWith(
        reviews: reviews, isLoading: false,
        averageRating: 0.0, totalRatings: 0,
        avgAccuracy: 0.0, avgAuthenticity: 0.0, avgUsefulness: 0.0,
        distribution: {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
      );
      return;
    }
    final n = reviews.length;
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in reviews) dist[r.rating] = (dist[r.rating] ?? 0) + 1;
    state = state.copyWith(
      reviews: reviews, isLoading: false,
      averageRating: reviews.map((r) => r.rating).reduce((a,b)=>a+b) / n,
      totalRatings: n,
      avgAccuracy: reviews.map((r) => r.accuracyScore).reduce((a,b)=>a+b) / n,
      avgAuthenticity: reviews.map((r) => r.authenticityScore).reduce((a,b)=>a+b) / n,
      avgUsefulness: reviews.map((r) => r.usefulnessScore).reduce((a,b)=>a+b) / n,
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
          .eq('content_type', 'byte')
          .eq('content_id_int', int.parse(byteId))
          .maybeSingle();
      if (row == null) return null;
      return EducatorReview(
        id: row['id'], educatorId: row['educator_id'], username: '',
        rating: (row['rating'] as num).toInt(),
        accuracyScore: (row['accuracy_score'] as num?)?.toDouble() ?? 0.0,
        authenticityScore: (row['usefulness_score'] as num?)?.toDouble() ?? 0.0,
        usefulnessScore: (row['rating'] as num).toDouble() / 5.0,
        feedback: row['feedback'],
        createdAt: DateTime.parse(row['created_at']),
      );
    } catch (_) { return null; }
  }

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
        'educator_id': userId, 'content_type': 'byte',
        'content_id_int': int.parse(byteId), 'rating': rating,
        'accuracy_score': accuracyScore, 'usefulness_score': authenticityScore,
        if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
      };
      String reviewId;
      if (existingReviewId != null) {
        await _supabase.from('educator_content_reviews')
            .update(payload).eq('id', existingReviewId);
        reviewId = existingReviewId;
      } else {
        final result = await _supabase.from('educator_content_reviews')
            .insert(payload).select('id').single();
        reviewId = result['id'] as String;
      }
      await _awardPoints(reviewId: reviewId,
          accuracyScore: accuracyScore, usefulnessScore: authenticityScore);
      await loadReviews();
      state = state.copyWith(isSubmitting: false);
      return true;
    } catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.toString());
      return false;
    }
  }

  Future<void> _awardPoints({
    required String reviewId,
    required double accuracyScore,
    required double usefulnessScore,
  }) async {
    try {
      final byteRow = await _supabase
          .from('bytes').select('user_id').eq('byte_id', int.parse(byteId)).maybeSingle();
      if (byteRow == null) return;
      await _ref.read(plaroPointsServiceProvider).awardPointsForRating(
        creatorId: byteRow['user_id'] as String,
        reviewId: reviewId,
        contentType: 'byte',
        contentId: byteId,
        accuracyScore: accuracyScore,
        usefulnessScore: usefulnessScore,
      );
    } catch (_) {}
  }
}

final byteRatingProvider =
StateNotifierProvider.family<ByteRatingNotifier, ByteRatingState, String>(
      (ref, byteId) {
    final notifier = ByteRatingNotifier(byteId, ref);
    notifier.loadReviews();
    return notifier;
  },
);