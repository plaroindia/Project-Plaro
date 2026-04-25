// content_event_tracker.dart
// UPGRADED: In-memory buffer, flushes every 15 s or every 10 events via RPC.
// Drop-in replacement — all existing call sites (trackView, trackLike, etc.)
// are preserved with identical signatures.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────

enum ContentType { post, byte, taiken }

enum EventType { view, like, comment, share, rate, complete, skip, dwell }

extension ContentTypeX on ContentType {
  String get value => name; // 'post' | 'byte' | 'taiken'
}

extension EventTypeX on EventType {
  String get value => name; // 'view' | 'like' | ...
}

class ContentEvent {
  final String userId;
  final String contentType;   // post | byte | taiken
  final String eventType;     // view | like | comment | share | rate | complete | skip | dwell
  final int?   contentIdInt;
  final String? contentIdUuid;
  final int?   dwellTime;
  final String? domain;
  final String  source;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  ContentEvent({
    required this.userId,
    required this.contentType,
    required this.eventType,
    this.contentIdInt,
    this.contentIdUuid,
    this.dwellTime,
    this.domain,
    this.source = 'feed',
    this.metadata,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'userId':        userId,
    'contentType':   contentType,
    'eventType':     eventType,
    if (contentIdInt  != null) 'contentIdInt':  contentIdInt,
    if (contentIdUuid != null) 'contentIdUuid': contentIdUuid,
    if (dwellTime     != null) 'dwellTime':     dwellTime,
    if (domain        != null) 'domain':        domain,
    'source':        source,
    if (metadata      != null) 'metadata':      metadata,
    'createdAt':     createdAt.toIso8601String(),
  };
}

// ─────────────────────────────────────────────────────────────
// Tracker
// ─────────────────────────────────────────────────────────────

class ContentEventTracker {
  ContentEventTracker() {
    _startFlushTimer();
  }

  final _supabase = Supabase.instance.client;

  static const int  _maxBufferSize  = 10;
  static const Duration _flushInterval = Duration(seconds: 15);

  final List<ContentEvent> _buffer = [];
  Timer? _flushTimer;
  bool   _isFlushing = false;

  // ── Timer ────────────────────────────────────────────────

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
  }

  // ── Public API ───────────────────────────────────────────
  // All methods match the original signature exactly.

  Future<void> trackView({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    String? domain,
    String  source = 'feed',
    String? sessionId,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'view',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid,
    domain: domain, source: source,
    metadata: sessionId != null ? {'sessionId': sessionId} : null,
  ));

  Future<void> trackLike({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    String? domain,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'like',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid, domain: domain,
  ));

  Future<void> trackComment({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    String? domain,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'comment',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid, domain: domain,
  ));

  Future<void> trackShare({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    String? domain,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'share',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid, domain: domain,
  ));

  Future<void> trackRate({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    String? domain,
    int?    rating,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'rate',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid, domain: domain,
    metadata: rating != null ? {'rating': rating} : null,
  ));

  Future<void> trackComplete({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    String? domain,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'complete',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid, domain: domain,
  ));

  Future<void> trackDwell({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    required int dwellTimeSeconds,
    double? scrollDepth,
    String? domain,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'dwell',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid,
    dwellTime: dwellTimeSeconds, domain: domain,
    metadata: scrollDepth != null ? {'scrollDepth': scrollDepth} : null,
  ));

  Future<void> trackSkip({
    required String userId,
    required String contentType,
    int?    contentIdInt,
    String? contentIdUuid,
    String? domain,
  }) => _enqueue(ContentEvent(
    userId: userId, contentType: contentType, eventType: 'skip',
    contentIdInt: contentIdInt, contentIdUuid: contentIdUuid, domain: domain,
  ));

  // ── Enqueue & flush logic ────────────────────────────────

  Future<void> _enqueue(ContentEvent event) async {
    _buffer.add(event);
    if (_buffer.length >= _maxBufferSize) {
      await _flush();
    }
  }

  /// Force-flush remaining events (call on app pause/dispose).
  Future<void> forceFlush() => _flush();

  Future<void> _flush() async {
    if (_isFlushing || _buffer.isEmpty) return;
    _isFlushing = true;

    // Grab snapshot and clear buffer immediately so new events
    // can accumulate while the RPC is in flight.
    final batch = List<ContentEvent>.from(_buffer);
    _buffer.clear();

    try {
      await _supabase.rpc(
        'track_user_events',
        params: {
          'p_events': batch.map((e) => e.toJson()).toList(),
        },
      );
      debugPrint('[EventTracker] Flushed ${batch.length} events');
    } catch (e) {
      // Re-queue failed events at the front so they aren't lost.
      _buffer.insertAll(0, batch);
      debugPrint('[EventTracker] Flush failed, re-queued ${batch.length} events: $e');
    } finally {
      _isFlushing = false;
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    // Best-effort flush on dispose (fire and forget).
    _flush();
  }
}

// ─────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────

final contentEventTrackerProvider = Provider<ContentEventTracker>((ref) {
  final tracker = ContentEventTracker();
  ref.onDispose(tracker.dispose);
  return tracker;
});