// ================================================================
// streak_provider.dart  (UPGRADED)
// CHANGE: All streak and point calculation is now server-side.
// get_user_consistency() RPC is the single source of truth.
// Local logPostCreated / logByteCreated / logTaikenStageCompletion
// calls are preserved so existing call sites still compile, but
// they now record into user_content_events via the event tracker
// and let the cron job recompute the streak overnight.
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

// ── Models ───────────────────────────────────────────────────

class UserStreak {
  final String userId;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityDate;
  final DateTime updatedAt;
  final int plaroPoints;

  const UserStreak({
    required this.userId,
    required this.currentStreak,
    required this.longestStreak,
    required this.lastActivityDate,
    required this.updatedAt,
    required this.plaroPoints,
  });

  bool get isActiveToday {
    if (lastActivityDate == null) return false;
    final now = DateTime.now().toUtc();
    return lastActivityDate!.year  == now.year &&
        lastActivityDate!.month == now.month &&
        lastActivityDate!.day   == now.day;
  }

  UserStreak copyWith({
    int? currentStreak, int? longestStreak,
    DateTime? lastActivityDate, DateTime? updatedAt, int? plaroPoints,
  }) => UserStreak(
    userId:           userId,
    currentStreak:    currentStreak    ?? this.currentStreak,
    longestStreak:    longestStreak    ?? this.longestStreak,
    lastActivityDate: lastActivityDate ?? this.lastActivityDate,
    updatedAt:        updatedAt        ?? this.updatedAt,
    plaroPoints:      plaroPoints      ?? this.plaroPoints,
  );
}

class MilestoneReward {
  final String userId;
  final int milestoneDays;
  final DateTime awardedAt;

  const MilestoneReward({
    required this.userId,
    required this.milestoneDays,
    required this.awardedAt,
  });

  factory MilestoneReward.fromMap(Map<String, dynamic> m) => MilestoneReward(
    userId:       m['userId'] as String? ?? '',
    milestoneDays: (m['milestoneDays'] as num).toInt(),
    awardedAt:    DateTime.parse(m['awardedAt'] as String),
  );

  int get points => StreakService.milestonePoints(milestoneDays);
}

class StreakState {
  final UserStreak? streak;
  final List<MilestoneReward> milestones;
  final bool isLoading;
  final String? error;
  final MilestoneReward? newMilestone;

  const StreakState({
    this.streak,
    this.milestones = const [],
    this.isLoading  = false,
    this.error,
    this.newMilestone,
  });

  StreakState copyWith({
    UserStreak?           streak,
    List<MilestoneReward>? milestones,
    bool?                 isLoading,
    String?               error,
    MilestoneReward?      newMilestone,
    bool clearNewMilestone = false,
    bool clearError        = false,
  }) => StreakState(
    streak:       streak       ?? this.streak,
    milestones:   milestones   ?? this.milestones,
    isLoading:    isLoading    ?? this.isLoading,
    error:        clearError   ? null : (error ?? this.error),
    newMilestone: clearNewMilestone ? null : (newMilestone ?? this.newMilestone),
  );
}

// ── Service ──────────────────────────────────────────────────

const Map<int, int> _milestoneTable = {
  3: 20, 7: 50, 14: 120, 30: 300, 60: 600,
  100: 1000, 180: 1800, 365: 3650, 500: 5000, 730: 7300,
};

class StreakService {
  final SupabaseClient _supabase;
  StreakService(this._supabase);

  static int milestonePoints(int days) => _milestoneTable[days] ?? 0;
  static List<MapEntry<int, int>> get allMilestones =>
      _milestoneTable.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
  static MapEntry<int, int>? nextMilestone(int current) {
    for (final e in allMilestones) if (e.key > current) return e;
    return null;
  }

  /// UPGRADED: single RPC call — no local calculation.
  Future<Map<String, dynamic>> fetchConsistency() async {
    final result = await _supabase.rpc('get_user_consistency');
    return (result as Map<String, dynamic>? ) ?? {};
  }

  // ── Activity logging (writes to user_daily_activity for the
  //    Postgres trigger; the cron recalculates streaks nightly).

  Future<void> logPostCreated({
    required String userId, required int postId, String? domain,
  }) async {
    debugPrint('[StreakService] logPostCreated uid=$userId postId=$postId');
    await _supabase.from('user_daily_activity').insert({
      'user_id':       userId,
      'activity_type': 'post_created',
      'content_id':    postId.toString(),
      'domain':        domain,
    });
  }

  Future<void> logByteCreated({
    required String userId, required int byteId, String? domain,
  }) async {
    await _supabase.from('user_daily_activity').insert({
      'user_id':       userId,
      'activity_type': 'byte_created',
      'content_id':    byteId.toString(),
      'domain':        domain,
    });
  }

  Future<void> logTaikenStageCompletion({
    required String userId, required String taikenStageId, String? domain,
  }) async {
    await _supabase.from('user_daily_activity').insert({
      'user_id':       userId,
      'activity_type': 'taiken_stage_completed',
      'content_id':    taikenStageId,
      'domain':        domain,
    });
  }

  MilestoneReward? detectNewMilestone(
      List<MilestoneReward> before, List<MilestoneReward> after) {
    final beforeDays = before.map((m) => m.milestoneDays).toSet();
    for (final m in after) if (!beforeDays.contains(m.milestoneDays)) return m;
    return null;
  }
}

// ── Notifier ─────────────────────────────────────────────────

class StreakNotifier extends StateNotifier<StreakState> {
  final StreakService _service;
  final String _userId;
  String get debugUserId => _userId;

  StreakNotifier(this._service, this._userId) : super(const StreakState()) {
    _init();
  }

  Future<void> _init() async {
    if (_userId.isEmpty) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _loadFromServer();
    } catch (e) {
      debugPrint('[StreakNotifier] init error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// UPGRADED: reads entirely from RPC, no local streak math.
  Future<void> _loadFromServer() async {
    final data = await _service.fetchConsistency();

    final milestones = ((data['milestones'] as List?) ?? [])
        .map((m) => MilestoneReward.fromMap(m as Map<String, dynamic>))
        .toList();

    final lastDate = data['lastActivityDate'] == null
        ? null
        : DateTime.parse(data['lastActivityDate'] as String);

    state = state.copyWith(
      isLoading: false,
      streak: UserStreak(
        userId:          _userId,
        currentStreak:   (data['currentStreak'] as num?)?.toInt() ?? 0,
        longestStreak:   (data['longestStreak'] as num?)?.toInt() ?? 0,
        lastActivityDate: lastDate,
        updatedAt:       DateTime.now(),
        plaroPoints:     (data['plaroPoints'] as num?)?.toInt() ?? 0,
      ),
      milestones: milestones,
    );
  }

  Future<void> refresh() => _init();

  // ── Log methods preserve call-site compatibility ──────────

  Future<void> _logAndRefresh(Future<void> Function() logFn) async {
    if (!mounted || _userId.isEmpty) return;
    final beforeMilestones = List<MilestoneReward>.from(state.milestones);
    try {
      await logFn();
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      await _loadFromServer();
      final earned = _service.detectNewMilestone(
          beforeMilestones, state.milestones);
      if (earned != null) {
        state = state.copyWith(newMilestone: earned);
        debugPrint('🏆 Milestone: ${earned.milestoneDays} days → ${earned.points} pts');
      }
    } catch (e) {
      debugPrint('[StreakNotifier] logAndRefresh error: $e');
    }
  }

  Future<void> logPostCreated({required int postId, String? domain}) =>
      _logAndRefresh(() => _service.logPostCreated(
          userId: _userId, postId: postId, domain: domain));

  Future<void> logByteCreated({required int byteId, String? domain}) =>
      _logAndRefresh(() => _service.logByteCreated(
          userId: _userId, byteId: byteId, domain: domain));

  Future<void> logTaikenStageCompletion({
    required String taikenStageId, String? domain,
  }) => _logAndRefresh(() => _service.logTaikenStageCompletion(
      userId: _userId, taikenStageId: taikenStageId, domain: domain));

  void clearNewMilestone() => state = state.copyWith(clearNewMilestone: true);
  void clearError()        => state = state.copyWith(clearError: true);
}

// ── Providers ─────────────────────────────────────────────────

final streakServiceProvider = Provider<StreakService>(
        (ref) => StreakService(Supabase.instance.client));

final streakProvider =
StateNotifierProvider<StreakNotifier, StreakState>((ref) {
  final streamSession = ref.watch(authStateProvider).valueOrNull;
  final userId = streamSession?.user.id
      ?? Supabase.instance.client.auth.currentSession?.user.id
      ?? '';
  return StreakNotifier(ref.read(streakServiceProvider), userId);
});

final currentStreakProvider   = Provider<int>(
        (ref) => ref.watch(streakProvider).streak?.currentStreak ?? 0);
final longestStreakProvider    = Provider<int>(
        (ref) => ref.watch(streakProvider).streak?.longestStreak ?? 0);
final plaroPointsProvider      = Provider<int>(
        (ref) => ref.watch(streakProvider).streak?.plaroPoints ?? 0);
final isStreakActiveTodayProvider = Provider<bool>(
        (ref) => ref.watch(streakProvider).streak?.isActiveToday ?? false);
final nextMilestoneProvider    = Provider<MapEntry<int, int>?>(
        (ref) => StreakService.nextMilestone(ref.watch(currentStreakProvider)));
final milestoneProgressProvider = Provider<double>((ref) {
  final current = ref.watch(currentStreakProvider);
  final next    = ref.watch(nextMilestoneProvider);
  if (next == null) return 1.0;
  final all   = StreakService.allMilestones;
  final idx   = all.indexWhere((e) => e.key == next.key);
  final prev  = idx > 0 ? all[idx - 1].key : 0;
  return ((current - prev) / (next.key - prev)).clamp(0.0, 1.0);
});
final newMilestoneProvider   = Provider<MilestoneReward?>(
        (ref) => ref.watch(streakProvider).newMilestone);
final milestoneHistoryProvider = Provider<List<MilestoneReward>>(
        (ref) => ref.watch(streakProvider).milestones);


// ================================================================
// plaro_points_service.dart  (READ-ONLY UPGRADE)
// All point calculation now happens on the server (cron jobs +
// RPC track_user_events side-effects).
// awardPointsForRating / awardPointsForContent / awardPointsForCompletion
// still exist so existing call sites compile, but they are now
// no-ops — the server handles it.  _insertTransaction is kept
// for the educator_rating path which is still Flutter-initiated.
// ================================================================

class PlaroPointsService {
  final _supabase = Supabase.instance.client;

  // ── READ: total points live in streak state via get_user_consistency ──
  // Use ref.watch(plaroPointsProvider) in widgets.

  // ── WRITE: only educator_rating still fires from Flutter. ─────────────
  // All other award paths (content creation, streaks, completions) are
  // handled server-side by cron / RPC track_user_events.

  Future<void> awardPointsForRating({
    required String creatorId,
    required String reviewId,
    required String contentType,
    required dynamic contentId,
    required double accuracyScore,
    required double usefulnessScore,
  }) async {
    int points = 0;
    if (accuracyScore >= 0.8 && usefulnessScore >= 0.8) {
      points = 5;
    } else if (accuracyScore >= 0.6 && usefulnessScore >= 0.6) {
      points = 3;
    } else {
      return; // Below threshold — server would also skip this
    }

    await _insertTransaction(
      userId:      creatorId,
      source:      'educator_rating',
      points:      points,
      contentType: contentType,
      contentId:   contentId,
      reason:      'Content validated by professional',
      metadata: {
        'review_id':       reviewId,
        'accuracy_score':  accuracyScore,
        'usefulness_score': usefulnessScore,
      },
    );
  }

  // These methods are now no-ops. The server awards points via the
  // track_user_events RPC side-effects and cron jobs.
  // Kept so existing call sites in post_provider / byte_provider / taiken
  // providers compile without changes.
  Future<void> awardPointsForContent({
    required String userId,
    required String contentType,
    required dynamic contentId,
  }) async {
    // No-op: server awards via cron compute_user_streaks +
    // track_user_events domain affinity side effect.
    debugPrint('[PlaroPoints] awardPointsForContent is now server-side for $contentType');
  }

  Future<void> awardPointsForCompletion({
    required String userId,
    required String contentType,
    required dynamic contentId,
  }) async {
    // No-op: server handles via track_user_events 'complete' event.
    debugPrint('[PlaroPoints] awardPointsForCompletion is now server-side for $contentType');
  }

  Future<void> awardConsistencyBonus({
    required String userId,
    required int streakDays,
  }) async {
    // No-op: server cron compute_user_streaks handles milestone bonuses.
    debugPrint('[PlaroPoints] awardConsistencyBonus is now server-side');
  }

  Future<void> _insertTransaction({
    required String userId,
    required String source,
    required int    points,
    String?         contentType,
    dynamic         contentId,
    String?         reason,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      dynamic normalizedId = contentId;
      if (contentId is num && contentId is! int) {
        normalizedId = contentId.toInt();
      }

      await _supabase.from('plaro_transactions').insert({
        'user_id':              userId,
        'source':               source,
        'points':               points,
        'related_content_type': contentType,
        if (normalizedId is int)    'related_content_id_int':  normalizedId,
        if (normalizedId is String) 'related_content_id_uuid': normalizedId,
        'reason':               reason,
        'metadata':             metadata,
      });
    } catch (e) {
      debugPrint('[PlaroPoints] _insertTransaction error: $e');
      rethrow;
    }
  }
}

final plaroPointsServiceProvider = Provider<PlaroPointsService>(
        (ref) => PlaroPointsService());