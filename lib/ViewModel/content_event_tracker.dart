import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final contentEventTrackerProvider = Provider((ref) => ContentEventTracker());

class ContentEventTracker {
  final _supabase = Supabase.instance.client;

  // Track view event
  Future<void> trackView({
    required String userId,
    required String contentType,
    int? contentIdInt,
    String? contentIdUuid,
    String? domain,
    String source = 'feed',
    String? sessionId,
  }) async {
    try {
      await _supabase.from('user_content_events').insert({
        'user_id': userId,
        'content_type': contentType,
        'content_id_int': contentIdInt,
        'content_id_uuid': contentIdUuid,
        'event_type': 'view',
        'domain': domain,
        'source': source,
        'session_id': sessionId,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error tracking view: $e');
    }
  }

  // Track like event
  Future<void> trackLike({
    required String userId,
    required String contentType,
    int? contentIdInt,
    String? contentIdUuid,
    String? domain,
  }) async {
    try {
      await _supabase.from('user_content_events').insert({
        'user_id': userId,
        'content_type': contentType,
        'content_id_int': contentIdInt,
        'content_id_uuid': contentIdUuid,
        'event_type': 'like',
        'domain': domain,
        'source': 'feed',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error tracking like: $e');
    }
  }

  // Track dwell time
  Future<void> trackDwell({
    required String userId,
    required String contentType,
    int? contentIdInt,
    String? contentIdUuid,
    required int dwellTimeSeconds,
    double? scrollDepth,
    String? domain,
  }) async {
    try {
      await _supabase.from('user_content_events').insert({
        'user_id': userId,
        'content_type': contentType,
        'content_id_int': contentIdInt,
        'content_id_uuid': contentIdUuid,
        'event_type': 'dwell',
        'dwell_time_seconds': dwellTimeSeconds,
        'scroll_depth': scrollDepth,
        'domain': domain,
        'source': 'feed',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error tracking dwell: $e');
    }
  }

  // Track skip event
  Future<void> trackSkip({
    required String userId,
    required String contentType,
    int? contentIdInt,
    String? contentIdUuid,
    String? domain,
  }) async {
    try {
      await _supabase.from('user_content_events').insert({
        'user_id': userId,
        'content_type': contentType,
        'content_id_int': contentIdInt,
        'content_id_uuid': contentIdUuid,
        'event_type': 'skip',
        'domain': domain,
        'source': 'feed',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error tracking skip: $e');
    }
  }
}