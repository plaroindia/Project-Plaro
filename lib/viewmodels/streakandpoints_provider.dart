// ================================================================
// streak_provider.dart  (UPGRADED)
// CHANGE: All streak and point calculation is now server-side.
// get_user_consistency() RPC is the single source of truth.
// Local logPostCreated / logByteCreated / logTaikenStageCompletion
// calls are preserved so existing call sites still compile, but
// they now record into user_content_events via the event tracker
// and let the cron job recompute the streak overnight.
//
// NEW (Freelance/Pro):
//   computeLevel(totalPoints) — numeric level for progress bars
//   rankFromPoints(totalPoints) — rank string (mirrors DB trigger)
//   rankTierIndex(rank) — int index for rank comparison in UI
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';
import 'notifications_provider.dart';

// ── Rank helpers (public — use these anywhere in the app) ────────────────────

/// Returns a numeric level 1–99 from total Plaro points.
/// Level 1 = 0–499 pts, increments every 500 pts.
int computeLevel(int totalPoints) =>
    ((totalPoints / 500).floor() + 1).clamp(1, 99);

/// Maps total_points to the text rank stored in user_profile_rank.rank_level.
/// Mirrors the Postgres calculate_rank_level() trigger function.
String rankFromPoints(int totalPoints) {
  if (totalPoints >= 4000) return 'master';
  if (totalPoints >= 2000) return 'expert';
  if (totalPoints >= 1000) return 'advanced';
  if (totalPoints >= 500)  return 'intermediate';
  return 'beginner';
}

/// Returns 0–4 for beginner–master.  Useful for rank-gate comparisons in UI.
int rankTierIndex(String rank) {
  const order = ['beginner', 'intermediate', 'advanced', 'expert', 'master'];
  final idx = order.indexOf(rank.toLowerCase());
  return idx < 0 ? 0 : idx;
}

/// Points required for each rank boundary.
const Map<String, int> kRankMinPoints = {
  'beginner':     0,
  'intermediate': 500,
  'advanced':     1000,
  'expert':       2000,
  'master':       4000,
};

/// Returns 0.0–1.0 progress toward the next rank boundary.
double rankProgress(int totalPoints) {
  if (totalPoints >= 4000) return 1.0;
  if (totalPoints >= 2000) return ((totalPoints - 2000) / 2000).clamp(0.0, 1.0);
  if (totalPoints >= 1000) return ((totalPoints - 1000) / 1000).clamp(0.0, 1.0);
  if (totalPoints >= 500)  return ((totalPoints - 500)  / 500 ).clamp(0.0, 1.0);
  return (totalPoints / 500).clamp(0.0, 1.0);
}

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
    for (final e in allMilestones) {
      if (e.key > current) return e;
    }
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
    for (final m in after) {
      if (!beforeDays.contains(m.milestoneDays)) return m;
    }
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

  Future<void> _logAndRefresh(Future<void> Function() logFn) async {
    try {
      await logFn();
    } catch (e) {
      debugPrint('[StreakNotifier] log error (non-fatal): $e');
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

// ── NEW: rank/level convenience providers ─────────────────────

/// Numeric level 1–99 based on live Plaro points.
final userLevelProvider = Provider<int>((ref) {
  final pts = ref.watch(plaroPointsProvider);
  return computeLevel(pts);
});

/// Text rank based on live Plaro points (matches DB trigger output).
final userRankFromPointsProvider = Provider<String>((ref) {
  final pts = ref.watch(plaroPointsProvider);
  return rankFromPoints(pts);
});

/// Progress 0.0–1.0 toward the next rank tier.
final userRankProgressProvider = Provider<double>((ref) {
  final pts = ref.watch(plaroPointsProvider);
  return rankProgress(pts);
});


// ================================================================
// PlaroPointsService
// ================================================================

class PlaroPointsService {
  final _supabase = Supabase.instance.client;

  // ── READ: total points live in streak state via get_user_consistency ──
  // Use ref.watch(plaroPointsProvider) in widgets.

  // ── WRITE: educator_rating and content-creation paths. ────────────────

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
      return;
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

  Future<void> awardPointsForContent({
    required String userId,
    required String contentType,
    required dynamic contentId,
  }) async {
    final String? source;
    switch (contentType) {
      case 'post':
        source = 'post_published';
        break;
      case 'taiken':
        source = 'taiken_created';
        break;
      default:
        debugPrint('[PlaroPoints] no DB source for contentType=$contentType, skipping');
        return;
    }

    debugPrint('[PlaroPoints] awardPointsForContent source=$source contentType=$contentType');
    await _insertTransaction(
      userId:      userId,
      source:      source,
      points:      10,
      contentType: contentType,
      contentId:   contentId,
      reason:      'Created new $contentType',
    );
  }

  Future<void> awardPointsForCompletion({
    required String userId,
    required String contentType,
    required dynamic contentId,
  }) async {
    final String? source;
    switch (contentType) {
      case 'taiken':
        source = 'taiken_completed';
        break;
      case 'module':
        source = 'module_completed';
        break;
      case 'course':
        source = 'course_completed';
        break;
      default:
        debugPrint('[PlaroPoints] no DB source for completion contentType=$contentType, skipping');
        return;
    }

    debugPrint('[PlaroPoints] awardPointsForCompletion source=$source contentType=$contentType');
    await _insertTransaction(
      userId:      userId,
      source:      source,
      points:      20,
      contentType: contentType,
      contentId:   contentId,
      reason:      'Completed $contentType',
    );
  }

  Future<void> awardConsistencyBonus({
    required String userId,
    required int streakDays,
  }) async {
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