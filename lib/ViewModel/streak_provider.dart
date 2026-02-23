import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

// =============================================================================
// MODELS
// =============================================================================

/// Mirrors the public.user_streaks row.
class UserStreak {
  final String userId;
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityDate; // UTC date; null until first qualifying event
  final DateTime updatedAt;

  const UserStreak({
    required this.userId,
    required this.currentStreak,
    required this.longestStreak,
    required this.lastActivityDate,
    required this.updatedAt,
  });

  factory UserStreak.fromMap(Map<String, dynamic> m) {
    return UserStreak(
      userId: m['user_id'] as String,
      currentStreak: (m['current_streak'] as num).toInt(),
      longestStreak: (m['longest_streak'] as num).toInt(),
      lastActivityDate: m['last_activity_date'] == null
          ? null
          : DateTime.parse(m['last_activity_date'] as String),
      updatedAt: DateTime.parse(m['updated_at'] as String),
    );
  }

  /// Whether the user has already logged a qualifying event today (UTC).
  bool get isActiveToday {
    if (lastActivityDate == null) return false;
    final todayUtc = DateTime.now().toUtc();
    return lastActivityDate!.year == todayUtc.year &&
        lastActivityDate!.month == todayUtc.month &&
        lastActivityDate!.day == todayUtc.day;
  }

  UserStreak copyWith({
    int? currentStreak,
    int? longestStreak,
    DateTime? lastActivityDate,
    DateTime? updatedAt,
  }) {
    return UserStreak(
      userId: userId,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastActivityDate: lastActivityDate ?? this.lastActivityDate,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// A streak milestone that has been awarded to the user.
class MilestoneReward {
  final String userId;
  final int milestoneDays;
  final DateTime awardedAt;

  const MilestoneReward({
    required this.userId,
    required this.milestoneDays,
    required this.awardedAt,
  });

  factory MilestoneReward.fromMap(Map<String, dynamic> m) {
    return MilestoneReward(
      userId: m['user_id'] as String,
      milestoneDays: (m['milestone_days'] as num).toInt(),
      awardedAt: DateTime.parse(m['awarded_at'] as String),
    );
  }

  /// Points awarded at this milestone (mirrors the SQL CTE values).
  int get points => StreakService.milestonePoints(milestoneDays);
}

/// State for [StreakNotifier].
class StreakState {
  final UserStreak? streak;
  final List<MilestoneReward> milestones;
  final bool isLoading;
  final String? error;

  /// A just-earned milestone bubble to show in the UI.
  /// The notifier sets this immediately after an event is logged; the UI
  /// should clear it after displaying the toast/animation.
  final MilestoneReward? newMilestone;

  const StreakState({
    this.streak,
    this.milestones = const [],
    this.isLoading = false,
    this.error,
    this.newMilestone,
  });

  StreakState copyWith({
    UserStreak? streak,
    List<MilestoneReward>? milestones,
    bool? isLoading,
    String? error,
    MilestoneReward? newMilestone,
    bool clearNewMilestone = false,
    bool clearError = false,
  }) {
    return StreakState(
      streak: streak ?? this.streak,
      milestones: milestones ?? this.milestones,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      newMilestone: clearNewMilestone ? null : (newMilestone ?? this.newMilestone),
    );
  }
}

// =============================================================================
// SERVICE  (pure Supabase I/O — no Riverpod dependency)
// =============================================================================

/// Known milestone thresholds and their point values.
/// Must stay in sync with the SQL CTE in handle_consistency_event().
const Map<int, int> _milestoneTable = {
  3: 20,
  7: 50,
  14: 120,
  30: 300,
  60: 600,
  100: 1000,
  180: 1800,
  365: 3650,
  500: 5000,
  730: 7300,
};

class StreakService {
  final SupabaseClient _supabase;

  StreakService(this._supabase);

  // ---------------------------------------------------------------------------
  // Static helpers
  // ---------------------------------------------------------------------------

  /// Points for a given milestone day count. Returns 0 if not a milestone.
  static int milestonePoints(int days) => _milestoneTable[days] ?? 0;

  /// The full ordered milestone schedule (for progress display).
  static List<MapEntry<int, int>> get allMilestones =>
      _milestoneTable.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

  /// Next milestone above [currentStreak]. Returns null if beyond all defined milestones.
  static MapEntry<int, int>? nextMilestone(int currentStreak) {
    for (final entry in allMilestones) {
      if (entry.key > currentStreak) return entry;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<UserStreak?> fetchStreak(String userId) async {
    final data = await _supabase
        .from('user_streaks')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return UserStreak.fromMap(data);
  }

  Future<List<MilestoneReward>> fetchMilestones(String userId) async {
    final rows = await _supabase
        .from('streak_milestone_rewards')
        .select()
        .eq('user_id', userId)
        .order('milestone_days', ascending: true);
    return (rows as List)
        .map((r) => MilestoneReward.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Writes — insert into user_daily_activity (dedicated streak table).
  // user_content_events is analytics-only and must not be written to here.
  // The Postgres trigger (trg_streak_on_daily_activity) calls
  // handle_consistency_event() automatically on every INSERT.
  // ---------------------------------------------------------------------------

  /// Logs a taiken stage completion for streak purposes.
  Future<void> logTaikenStageCompletion({
    required String userId,
    required String taikenStageId,
    String? domain,
  }) async {
    await _supabase.from('user_daily_activity').insert({
      'user_id':       userId,
      'activity_type': 'taiken_stage_completed',
      'content_id':    taikenStageId,
      'domain':        domain,
    });
  }

  /// Logs a post creation for streak purposes.
  Future<void> logPostCreated({
    required String userId,
    required int postId,
    String? domain,
  }) async {
    debugPrint('[StreakService] logPostCreated userId="$userId" postId=$postId domain=$domain');
    try {
      final result = await _supabase.from('user_daily_activity').insert({
        'user_id':       userId,
        'activity_type': 'post_created',
        'content_id':    postId.toString(),
        'domain':        domain,
      }).select();
      debugPrint('[StreakService] INSERT ok: $result');
    } catch (e, st) {
      debugPrint('[StreakService] INSERT FAILED: $e');
      debugPrint('[StreakService] stack: $st');
      rethrow;
    }
  }

  /// Logs a byte creation for streak purposes.
  Future<void> logByteCreated({
    required String userId,
    required int byteId,
    String? domain,
  }) async {
    await _supabase.from('user_daily_activity').insert({
      'user_id':       userId,
      'activity_type': 'byte_created',
      'content_id':    byteId.toString(),
      'domain':        domain,
    });
  }

  // ---------------------------------------------------------------------------
  // Helper: detect a newly awarded milestone by diffing before/after
  // ---------------------------------------------------------------------------

  /// Returns any milestone that exists in [after] but not in [before].
  MilestoneReward? detectNewMilestone(
      List<MilestoneReward> before,
      List<MilestoneReward> after,
      ) {
    final beforeDays = before.map((m) => m.milestoneDays).toSet();
    for (final m in after) {
      if (!beforeDays.contains(m.milestoneDays)) return m;
    }
    return null;
  }
}

// =============================================================================
// NOTIFIER
// =============================================================================

class StreakNotifier extends StateNotifier<StreakState> {
  final StreakService _service;
  final String _userId;
  String get debugUserId => _userId;
  StreakNotifier(this._service, this._userId) : super(const StreakState()) {
    _init();
  }

  // ---------------------------------------------------------------------------
  // Initialisation
  // ---------------------------------------------------------------------------

  Future<void> _init() async {
    if (_userId.isEmpty) {
      debugPrint('[Streak] _init skipped — no authenticated user');
      return;
    }
    debugPrint('[Streak] _init for user $_userId');
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        _service.fetchStreak(_userId),
        _service.fetchMilestones(_userId),
      ]);
      state = state.copyWith(
        streak: results[0] as UserStreak?,
        milestones: results[1] as List<MilestoneReward>,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[StreakNotifier] init error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Force a full reload (e.g. on pull-to-refresh or app resume).
  Future<void> refresh() => _init();

  // ---------------------------------------------------------------------------
  // Event logging (called from other providers after content is created)
  // ---------------------------------------------------------------------------

  /// Generic internal method: logs event → waits briefly for trigger → refreshes.
  Future<void> _logAndRefresh(Future<void> Function() logFn) async {
    if (!mounted) return;
    // Guard: if the notifier was created before auth resolved, _userId will
    // be an empty string. Passing '' as a UUID to Postgres causes 22P02.
    if (_userId.isEmpty) {
      debugPrint('[Streak] _logAndRefresh skipped — userId not yet available');
      return;
    }
    final milestonesBeforeLog = List<MilestoneReward>.from(state.milestones);

    try {
      await logFn();

      // Give the Postgres trigger a moment to complete before we re-read.
      // 300 ms is generous; the trigger is synchronous within the INSERT
      // transaction but the Supabase client receives the INSERT ack first.
      await Future.delayed(const Duration(milliseconds: 300));

      if (!mounted) return;

      final newStreak = await _service.fetchStreak(_userId);
      final newMilestones = await _service.fetchMilestones(_userId);

      final earned = _service.detectNewMilestone(milestonesBeforeLog, newMilestones);

      state = state.copyWith(
        streak: newStreak,
        milestones: newMilestones,
        newMilestone: earned,
      );

      if (earned != null) {
        debugPrint('🏆 Streak milestone reached: ${earned.milestoneDays} days → ${earned.points} pts');
      }
    } catch (e) {
      debugPrint('[StreakNotifier] logAndRefresh error: $e');
      // Non-fatal: streak update failure should never block content creation.
    }
  }

  /// Call this after a taiken stage is successfully completed.
  Future<void> logTaikenStageCompletion({
    required String taikenStageId,
    String? domain,
  }) =>
      _logAndRefresh(
            () => _service.logTaikenStageCompletion(
          userId: _userId,
          taikenStageId: taikenStageId,
          domain: domain,
        ),
      );

  /// Call this after a post is successfully created.
  Future<void> logPostCreated({required int postId, String? domain}) =>
      _logAndRefresh(
            () => _service.logPostCreated(
          userId: _userId,
          postId: postId,
          domain: domain,
        ),
      );

  /// Call this after a byte is successfully created.
  Future<void> logByteCreated({required int byteId, String? domain}) =>
      _logAndRefresh(
            () => _service.logByteCreated(
          userId: _userId,
          byteId: byteId,
          domain: domain,
        ),
      );

  // ---------------------------------------------------------------------------
  // UI helpers
  // ---------------------------------------------------------------------------

  /// Call from the UI once the milestone toast/animation has been shown.
  void clearNewMilestone() {
    state = state.copyWith(clearNewMilestone: true);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// =============================================================================
// PROVIDERS
// =============================================================================

/// Low-level service provider — stable singleton, no auth dependency.
final streakServiceProvider = Provider<StreakService>((ref) {
  return StreakService(Supabase.instance.client);
});

/// The main streak provider, scoped to the currently authenticated user.
///
/// Re-creates whenever the auth session changes (login/logout) — same pattern
/// as [isVerifiedProfessionalProvider] in post_rating_provider.dart.
final streakProvider = StateNotifierProvider<StreakNotifier, StreakState>((ref) {
  // Watch the stream so the notifier re-creates on login/logout.
  // valueOrNull is null until the first stream event fires, so fall back to
  // the synchronously available currentSession which is always populated
  // when the user is already logged in at app start.
  final streamSession = ref.watch(authStateProvider).valueOrNull;
  final userId = streamSession?.user.id
      ?? Supabase.instance.client.auth.currentSession?.user.id
      ?? '';
  final service = ref.read(streakServiceProvider);
  return StreakNotifier(service, userId);
});

// ---------------------------------------------------------------------------
// Convenience derived providers
// ---------------------------------------------------------------------------

/// The current streak integer — useful for lightweight widgets that only need
/// the number and don't want to watch the whole StreakState.
final currentStreakProvider = Provider<int>((ref) {
  return ref.watch(streakProvider).streak?.currentStreak ?? 0;
});

/// The longest-ever streak — for profile display.
final longestStreakProvider = Provider<int>((ref) {
  return ref.watch(streakProvider).streak?.longestStreak ?? 0;
});

/// Whether the user has already completed a qualifying activity today (UTC).
/// Used to render a "✓ active today" indicator in the streak widget.
final isStreakActiveTodayProvider = Provider<bool>((ref) {
  return ref.watch(streakProvider).streak?.isActiveToday ?? false;
});

/// The next milestone the user is working towards.
/// Returns null if they are beyond all defined milestones.
final nextMilestoneProvider = Provider<MapEntry<int, int>?>((ref) {
  final current = ref.watch(currentStreakProvider);
  return StreakService.nextMilestone(current);
});

/// Progress (0.0–1.0) towards the next milestone.
/// E.g. at day 5 heading to milestone 7 → 5/7 ≈ 0.71.
final milestoneProgressProvider = Provider<double>((ref) {
  final current = ref.watch(currentStreakProvider);
  final next = ref.watch(nextMilestoneProvider);
  if (next == null) return 1.0; // beyond all milestones
  if (next.key == 0) return 0.0;

  // Find the previous milestone to calculate progress between two milestones
  final all = StreakService.allMilestones;
  final nextIndex = all.indexWhere((e) => e.key == next.key);
  final prevMilestone = nextIndex > 0 ? all[nextIndex - 1].key : 0;

  final range = next.key - prevMilestone;
  final progress = (current - prevMilestone) / range;
  return progress.clamp(0.0, 1.0);
});

/// A just-earned milestone (non-null only briefly after a qualifying event).
/// Widgets should watch this, show a celebration, then call clearNewMilestone().
final newMilestoneProvider = Provider<MilestoneReward?>((ref) {
  return ref.watch(streakProvider).newMilestone;
});

/// All milestones the user has ever earned, ascending.
final milestoneHistoryProvider = Provider<List<MilestoneReward>>((ref) {
  return ref.watch(streakProvider).milestones;
});