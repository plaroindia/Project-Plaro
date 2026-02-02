import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PlaroPointsService {
  final _supabase = Supabase.instance.client;

  // Award points for educator rating
  Future<void> awardPointsForRating({
    required String creatorId,
    required String reviewId,
    required String contentType,
    required dynamic contentId, // Can be int or uuid
    required double accuracyScore,
    required double usefulnessScore,
  }) async {
    int points = 0;

    if (accuracyScore >= 0.8 && usefulnessScore >= 0.8) {
      points = 5;
    } else if (accuracyScore >= 0.6 && usefulnessScore >= 0.6) {
      points = 3;
    } else {
      return; // Don't award for poor ratings
    }

    await _insertTransaction(
      userId: creatorId,
      source: 'educator_rating',
      points: points,
      contentType: contentType,
      contentId: contentId,
      reason: 'Content validated by professional',
      metadata: {
        'review_id': reviewId,
        'accuracy_score': accuracyScore,
        'usefulness_score': usefulnessScore,
      },
    );
  }

  // Award points for content creation
  Future<void> awardPointsForContent({
    required String userId,
    required String contentType, // 'post', 'byte', 'taiken'
    required dynamic contentId,
  }) async {
    final pointsMap = {
      'post': 2,
      'byte': 2,
      'taiken': 10,
      'course': 15,
    };

    final points = pointsMap[contentType] ?? 1;

    await _insertTransaction(
      userId: userId,
      source: '${contentType}_published',
      points: points,
      contentType: contentType,
      contentId: contentId,
      reason: 'Created $contentType',
    );
  }

  // Award points for completing content
  Future<void> awardPointsForCompletion({
    required String userId,
    required String contentType,
    required dynamic contentId,
  }) async {
    final pointsMap = {
      'taiken': 5,
      'course': 10,
      'module': 3,
      'checkpoint': 5,
    };

    final points = pointsMap[contentType] ?? 1;

    await _insertTransaction(
      userId: userId,
      source: '${contentType}_completed',
      points: points,
      contentType: contentType,
      contentId: contentId,
      reason: 'Completed $contentType',
    );
  }

  // Award consistency bonus
  Future<void> awardConsistencyBonus({
    required String userId,
    required int streakDays,
  }) async {
    // Award bonus every 7 days
    if (streakDays % 7 == 0) {
      final points = (streakDays / 7).floor();

      await _insertTransaction(
        userId: userId,
        source: 'consistency_bonus',
        points: points,
        reason: '$streakDays day streak bonus',
      );
    }
  }

  // Internal method to insert transaction
  Future<void> _insertTransaction({
    required String userId,
    required String source,
    required int points,
    String? contentType,
    dynamic contentId,
    String? reason,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _supabase.from('plaro_transactions').insert({
        'user_id': userId,
        'source': source,
        'points': points,
        'related_content_type': contentType,
        if (contentId is int) 'related_content_id_int': contentId,
        if (contentId is String) 'related_content_id_uuid': contentId,
        'reason': reason,
        'metadata': metadata,
      });
    } catch (e) {
      print('Error awarding points: $e');
      rethrow;
    }
  }
}

//  CORRECTED: Riverpod Provider
final plaroPointsServiceProvider = Provider<PlaroPointsService>((ref) {
  return PlaroPointsService();
});