// =============================================================================
// taiken_list_provider.dart  — FINAL
//
// Changes from previous version:
//   • TaikenListState
//       + userProgressMap  — taikenId → TaikenProgress  (shows completion on cards)
//       + lockedTaikenIds  — Set of taikenIds the user hasn't unlocked yet
//       + clearError flag  — same pattern as experience provider
//
//   • TaikenListNotifier.loadTaikens()
//       After fetching taikens, fetches the current user's progress rows in one
//       batch query and builds the map.
//
//   • TaikenListNotifier._checkDomainLocks()
//       For each taiken that has a domainUnlockRequirement, checks whether the
//       user has completed enough taikens in that domain.  Locked taiken IDs are
//       stored in lockedTaikenIds so the list page can show an overlay.
//
//   • All existing methods (search, filter, clear) are unchanged.
// =============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Model/taiken.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class TaikenListState {
  final List<Taiken> taikens;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final bool hasMore;
  final String? searchQuery;
  final String? filterDomain;
  final String? filterDifficulty;

  /// taikenId → the current user's saved progress for that taiken.
  /// Empty map = progress not yet loaded or user has no progress.
  final Map<String, TaikenProgress> userProgressMap;

  /// Set of taikenIds that are locked for the current user due to domain
  /// gate requirements they haven't met yet.
  final Set<String> lockedTaikenIds;

  const TaikenListState({
    this.taikens = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.hasMore = true,
    this.searchQuery,
    this.filterDomain,
    this.filterDifficulty,
    this.userProgressMap = const {},
    this.lockedTaikenIds = const {},
  });

  TaikenListState copyWith({
    List<Taiken>? taikens,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    bool clearError = false,
    bool? hasMore,
    String? searchQuery,
    String? filterDomain,
    String? filterDifficulty,
    Map<String, TaikenProgress>? userProgressMap,
    Set<String>? lockedTaikenIds,
  }) {
    return TaikenListState(
      taikens:          taikens          ?? this.taikens,
      isLoading:        isLoading        ?? this.isLoading,
      isLoadingMore:    isLoadingMore    ?? this.isLoadingMore,
      error:            clearError ? null : (error ?? this.error),
      hasMore:          hasMore          ?? this.hasMore,
      searchQuery:      searchQuery      ?? this.searchQuery,
      filterDomain:     filterDomain     ?? this.filterDomain,
      filterDifficulty: filterDifficulty ?? this.filterDifficulty,
      userProgressMap:  userProgressMap  ?? this.userProgressMap,
      lockedTaikenIds:  lockedTaikenIds  ?? this.lockedTaikenIds,
    );
  }

  // Convenience getters used by the list page.
  bool isCompleted(String taikenId) =>
      userProgressMap[taikenId]?.status == 'completed';

  bool isInProgress(String taikenId) =>
      userProgressMap[taikenId]?.status == 'in_progress';

  bool isLocked(String taikenId) => lockedTaikenIds.contains(taikenId);
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class TaikenListNotifier extends StateNotifier<TaikenListState> {
  TaikenListNotifier() : super(const TaikenListState());

  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _pageSize = 10;

  // ── Main load ──────────────────────────────────────────────────────────────

  Future<void> loadTaikens({bool refresh = false}) async {
    if (!refresh && (state.isLoading || state.isLoadingMore)) return;

    if (refresh) {
      state = const TaikenListState(isLoading: true);
    } else {
      state = state.copyWith(
        isLoadingMore: state.taikens.isNotEmpty,
      );
    }

    try {
      // ── 1. Fetch taikens page ──────────────────────────────────────────────
      dynamic query = _supabase.from('taikens').select();
      query = query.eq('is_published', true);

      if (state.searchQuery != null && state.searchQuery!.isNotEmpty) {
        query = query.ilike('title', '%${state.searchQuery}%');
      }
      if (state.filterDomain != null) {
        query = query.eq('domain', state.filterDomain!);
      }
      if (state.filterDifficulty != null) {
        query = query.eq('difficulty', state.filterDifficulty!);
      }

      query = query
          .order('created_at', ascending: false)
          .range(
        refresh ? 0 : state.taikens.length,
        refresh
            ? _pageSize - 1
            : state.taikens.length + _pageSize - 1,
      );

      final response      = await query;
      final newTaikens    = (response as List)
          .map((j) => Taiken.fromJson(j as Map<String, dynamic>))
          .toList();
      final allTaikens    = refresh
          ? newTaikens
          : [...state.taikens, ...newTaikens];

      // ── 2. Fetch user progress for this page batch ─────────────────────────
      final progressMap   = await _fetchProgressMap(newTaikens);
      final mergedProgress = {
        ...state.userProgressMap,
        ...progressMap,
      };

      // ── 3. Check domain locks for taikens that have requirements ──────────
      final locked = await _checkDomainLocks(allTaikens);

      state = state.copyWith(
        taikens:         allTaikens,
        isLoading:       false,
        isLoadingMore:   false,
        hasMore:         newTaikens.length == _pageSize,
        clearError:      true,
        userProgressMap: mergedProgress,
        lockedTaikenIds: locked,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading:     false,
        isLoadingMore: false,
        error:         'Failed to load Taikens: $e',
      );
    }
  }

  // ── Progress batch fetch ───────────────────────────────────────────────────

  Future<Map<String, TaikenProgress>> _fetchProgressMap(
      List<Taiken> taikens) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || taikens.isEmpty) return {};

    try {
      final ids     = taikens.map((t) => t.taikenId).toList();
      final rows    = await _supabase
          .from('taiken_progress')
          .select()
          .eq('user_id', userId)
          .inFilter('taiken_id', ids);

      return {
        for (final row in rows as List)
          (row['taiken_id'] as String):
          TaikenProgress.fromJson(row as Map<String, dynamic>),
      };
    } catch (_) {
      return {};
    }
  }

  // ── Domain lock check ──────────────────────────────────────────────────────
  //
  // For each taiken with a domainUnlockRequirement like:
  //   {"domain": "data_analysis", "min_taikens_passed": 2}
  // we check how many taikens the user has completed in that domain.
  // If they haven't met the minimum, the taiken ID goes into lockedTaikenIds.

  Future<Set<String>> _checkDomainLocks(List<Taiken> taikens) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return {};

    final gated = taikens
        .where((t) => t.domainUnlockRequirement != null)
        .toList();
    if (gated.isEmpty) return {};

    // Collect all unique domains we need to check.
    final domains = gated
        .map((t) =>
    t.domainUnlockRequirement!['domain'] as String?)
        .whereType<String>()
        .toSet();

    // One query per domain (usually just 1-2 domains).
    final Map<String, int> completedPerDomain = {};
    for (final domain in domains) {
      try {
        // Count completed taikens in this domain for the current user.
        // We join via taikens to get the domain.
        final rows = await _supabase
            .from('taiken_progress')
            .select('taiken_id, taikens!inner(domain)')
            .eq('user_id', userId)
            .eq('status', 'completed')
            .eq('taikens.domain', domain);
        completedPerDomain[domain] = (rows as List).length;
      } catch (_) {
        completedPerDomain[domain] = 0;
      }
    }

    final locked = <String>{};
    for (final taiken in gated) {
      final req = taiken.domainUnlockRequirement!;
      final reqDomain = req['domain'] as String?;
      final minPassed = (req['min_taikens_passed'] as num?)?.toInt() ?? 1;
      if (reqDomain == null) continue;
      final completed = completedPerDomain[reqDomain] ?? 0;
      if (completed < minPassed) {
        locked.add(taiken.taikenId);
      }
    }
    return locked;
  }

  // ── Filters / search (unchanged signatures) ────────────────────────────────

  Future<void> searchTaikens(String query) async {
    state = state.copyWith(searchQuery: query);
    await loadTaikens(refresh: true);
  }

  Future<void> filterByDomain(String? domain) async {
    state = state.copyWith(filterDomain: domain);
    await loadTaikens(refresh: true);
  }

  Future<void> filterByDifficulty(String? difficulty) async {
    state = state.copyWith(filterDifficulty: difficulty);
    await loadTaikens(refresh: true);
  }

  void clearFilters() {
    state = const TaikenListState();
    loadTaikens(refresh: true);
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final taikenListProvider =
StateNotifierProvider<TaikenListNotifier, TaikenListState>(
        (_) => TaikenListNotifier());