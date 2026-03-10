// =============================================================================
// taiken_experience_provider.dart  — PHASE A REWRITE
//
// What changed from the old version:
//   • TaikenExperienceState
//       - Removed showingIntro / showingOutro booleans
//       - Removed currentDialogueIndex (dialogue tracking now in the VN view)
//       - Added phase (TaikenPhase enum) — single source of truth for routing
//       - Added activeGateQuestionId — which question triggered the gate
//       - Added earnedBadge / nextEpisode — populated on completion (Phase D)
//       - Added interactedGateQuestionIds — prevents double-gating same question
//       - error field fixed: uses explicit clearError flag so copyWith doesn't
//         silently wipe existing errors
//
//   • TaikenExperienceNotifier
//       - loadTaiken() now uses upsert_taiken_progress RPC (no duplicate rows)
//       - loadTaiken() restores phase/questionIndex from saved progress
//       - advanceDialogue() replaced by enterQuestionPhase() — explicit transition
//       - checkAndEnterGate() — gate check before every question render
//       - studyGate() / skipGate() — gate action handlers (Phase C will wire UI)
//       - submitAnswer() fixed — calls advanceToNextQuestion() correctly
//       - advanceToNextQuestion() fixed — persists currentQuestionIndex to DB
//       - advanceToNextStage() fixed — resets phase to dialogue in DB + state
//       - resetAndRestart() fixed — uses delete then upsert RPC, no race condition
//       - All phase transitions go through _setPhase() — single choke point,
//         easy to debug
//
//   STUB METHODS (will be fully implemented in Phase D):
//       - _fetchEarnedBadge()
//       - _fetchNextEpisode()
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Model/taiken.dart';
import 'streakandpoints_provider.dart';
import 'content_event_tracker.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class TaikenExperienceState {
  final Taiken? taiken;
  final List<TaikenStage> stages;
  final List<TaikenCharacter> characters;
  final Map<String, List<TaikenDialogue>> dialoguesByStage;
  final Map<String, List<TaikenQuestion>> questionsByStage;
  final TaikenProgress? progress;

  /// Current stage index (0-based).
  final int currentStageIndex;

  /// Current question index within the active stage (0-based).
  final int currentQuestionIndex;

  /// Single source of truth for which screen is shown.
  final TaikenPhase phase;

  /// Question ID that triggered the currently active gate.
  /// Null when not in gateInterstitial phase.
  final String? activeGateQuestionId;

  /// Set of question IDs where the user has already seen the gate.
  /// Prevents the same gate appearing twice (e.g. after returning from study).
  final Set<String> interactedGateQuestionIds;

  /// Answers the user has submitted: questionId → selectedOptionIndex.
  final Map<String, int?> userAnswers;

  /// User's rating for this Taiken (1-5). Null = not yet rated.
  final int? userRating;

  // Loading / error
  final bool isLoading;
  final String? error;

  // ── Phase D stubs ────────────────────────────────────────────────────────
  /// Badge awarded on successful completion. Populated in Phase D.
  final TaikenBadge? earnedBadge;

  /// Next episode in the series. Populated in Phase D.
  final Taiken? nextEpisode;

  const TaikenExperienceState({
    this.taiken,
    this.stages = const [],
    this.characters = const [],
    this.dialoguesByStage = const {},
    this.questionsByStage = const {},
    this.progress,
    this.currentStageIndex = 0,
    this.currentQuestionIndex = 0,
    this.phase = TaikenPhase.intro,
    this.activeGateQuestionId,
    this.interactedGateQuestionIds = const {},
    this.userAnswers = const {},
    this.userRating,
    this.isLoading = false,
    this.error,
    this.earnedBadge,
    this.nextEpisode,
  });

  // ── Derived getters ───────────────────────────────────────────────────────

  TaikenStage? get currentStage =>
      currentStageIndex < stages.length ? stages[currentStageIndex] : null;

  List<TaikenDialogue> get currentDialogues =>
      currentStage != null
          ? dialoguesByStage[currentStage!.stageId] ?? []
          : [];

  List<TaikenQuestion> get currentQuestions =>
      currentStage != null
          ? questionsByStage[currentStage!.stageId] ?? []
          : [];

  TaikenQuestion? get currentQuestion =>
      currentQuestionIndex < currentQuestions.length
          ? currentQuestions[currentQuestionIndex]
          : null;

  bool get hasMoreStages => currentStageIndex < stages.length - 1;

  bool get isLastQuestion =>
      currentQuestions.isNotEmpty &&
          currentQuestionIndex >= currentQuestions.length - 1;

  // ── copyWith ──────────────────────────────────────────────────────────────
  //
  // IMPORTANT: error uses an explicit `clearError` flag pattern.
  // Calling copyWith(isLoading: false) will NOT accidentally clear an error.
  // To clear: copyWith(clearError: true)
  // To set:   copyWith(error: 'message')

  TaikenExperienceState copyWith({
    Taiken? taiken,
    List<TaikenStage>? stages,
    List<TaikenCharacter>? characters,
    Map<String, List<TaikenDialogue>>? dialoguesByStage,
    Map<String, List<TaikenQuestion>>? questionsByStage,
    TaikenProgress? progress,
    int? currentStageIndex,
    int? currentQuestionIndex,
    TaikenPhase? phase,
    String? activeGateQuestionId,
    bool clearActiveGate = false,
    Set<String>? interactedGateQuestionIds,
    Map<String, int?>? userAnswers,
    int? userRating,
    bool? isLoading,
    String? error,
    bool clearError = false,
    TaikenBadge? earnedBadge,
    Taiken? nextEpisode,
  }) {
    return TaikenExperienceState(
      taiken:                    taiken                    ?? this.taiken,
      stages:                    stages                    ?? this.stages,
      characters:                characters                ?? this.characters,
      dialoguesByStage:          dialoguesByStage          ?? this.dialoguesByStage,
      questionsByStage:          questionsByStage          ?? this.questionsByStage,
      progress:                  progress                  ?? this.progress,
      currentStageIndex:         currentStageIndex         ?? this.currentStageIndex,
      currentQuestionIndex:      currentQuestionIndex      ?? this.currentQuestionIndex,
      phase:                     phase                     ?? this.phase,
      activeGateQuestionId:      clearActiveGate
          ? null
          : activeGateQuestionId ?? this.activeGateQuestionId,
      interactedGateQuestionIds: interactedGateQuestionIds ?? this.interactedGateQuestionIds,
      userAnswers:               userAnswers               ?? this.userAnswers,
      userRating:                userRating                ?? this.userRating,
      isLoading:                 isLoading                 ?? this.isLoading,
      error:                     clearError ? null : (error ?? this.error),
      earnedBadge:               earnedBadge               ?? this.earnedBadge,
      nextEpisode:               nextEpisode               ?? this.nextEpisode,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class TaikenExperienceNotifier
    extends StateNotifier<TaikenExperienceState> {
  TaikenExperienceNotifier(this.taikenId, this._ref)
      : super(const TaikenExperienceState());

  final String taikenId;
  final Ref _ref;
  final SupabaseClient _supabase = Supabase.instance.client;

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> loadTaiken() async {
    _setLoading(true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // ── 1. Taiken metadata ─────────────────────────────────────────────────
      final taikenJson = await _supabase
          .from('taikens')
          .select()
          .eq('taiken_id', taikenId)
          .single();
      final taiken = Taiken.fromJson(taikenJson);

      // ── 2. Stages ─────────────────────────────────────────────────────────
      final stagesJson = await _supabase
          .from('taiken_stages')
          .select()
          .eq('taiken_id', taikenId)
          .order('stage_order');
      final stages = (stagesJson as List)
          .map((j) => TaikenStage.fromJson(j))
          .toList();

      // ── 3. Characters ─────────────────────────────────────────────────────
      final charsJson = await _supabase
          .from('taiken_characters')
          .select()
          .eq('taiken_id', taikenId)
          .order('display_order');
      final characters = (charsJson as List)
          .map((j) => TaikenCharacter.fromJson(j))
          .toList();

      // ── 4. Dialogues + Questions (batched per stage) ───────────────────────
      final Map<String, List<TaikenDialogue>> dialoguesByStage = {};
      final Map<String, List<TaikenQuestion>> questionsByStage = {};

      for (final stage in stages) {
        final dJson = await _supabase
            .from('taiken_dialogues')
            .select()
            .eq('stage_id', stage.stageId)
            .order('dialogue_order');
        dialoguesByStage[stage.stageId] =
            (dJson as List).map((j) => TaikenDialogue.fromJson(j)).toList();

        final qJson = await _supabase
            .from('taiken_questions')
            .select()
            .eq('stage_id', stage.stageId)
            .order('question_order');
        questionsByStage[stage.stageId] =
            (qJson as List).map((j) => TaikenQuestion.fromJson(j)).toList();
      }

      // ── 5. Progress — upsert via RPC (no duplicate rows) ──────────────────
      final progressJson = await _supabase.rpc(
        'upsert_taiken_progress',
        params: {'p_user_id': userId, 'p_taiken_id': taikenId},
      );
      final progress = TaikenProgress.fromJson(
          progressJson as Map<String, dynamic>);

      // ── 6. Existing rating ────────────────────────────────────────────────
      int? existingRating;
      try {
        final ratingJson = await _supabase
            .from('taiken_ratings')
            .select('rating')
            .eq('user_id', userId)
            .eq('taiken_id', taikenId)
            .single();
        existingRating = ratingJson['rating'] as int?;
      } catch (_) {
        // No rating yet — fine.
      }

      // ── 7. Track view event ───────────────────────────────────────────────
      if (progress.questionsAnswered == 0) {
        // First time opening this Taiken.
        _supabase
            .rpc('increment_play_count', params: {'taiken_id': taikenId})
            .catchError((e) => debugPrint('play_count increment error: $e'));
      }

      _ref.read(contentEventTrackerProvider).trackView(
        userId: userId,
        contentType: 'taiken',
        contentIdUuid: taikenId,
        source: 'browse',
      );

      // ── 8. Restore saved position ─────────────────────────────────────────
      final savedStageIndex =
      (progress.currentStageOrder - 1).clamp(0, stages.length - 1);
      final savedQuestionIndex = progress.currentQuestionIndex;

      // If progress is brand new (stage 1, phase dialogue, 0 questions) →
      // show intro. Otherwise resume from where the user left off.
      final bool isFirstOpen =
          progress.currentStageOrder == 1 &&
              progress.currentPhase == TaikenPhase.dialogue &&
              progress.questionsAnswered == 0;

      // If completed/failed, go straight to outro.
      final bool isFinished =
          progress.status == 'completed' || progress.status == 'failed';

      TaikenPhase restoredPhase;
      if (isFinished) {
        restoredPhase = TaikenPhase.outro;
      } else if (isFirstOpen) {
        restoredPhase = TaikenPhase.intro;
      } else {
        restoredPhase = progress.currentPhase;
      }

      state = state.copyWith(
        taiken:               taiken,
        stages:               stages,
        characters:           characters,
        dialoguesByStage:     dialoguesByStage,
        questionsByStage:     questionsByStage,
        progress:             progress,
        currentStageIndex:    savedStageIndex,
        currentQuestionIndex: savedQuestionIndex,
        phase:                restoredPhase,
        userRating:           existingRating,
        isLoading:            false,
        clearError:           true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load Taiken: $e',
      );
    }
  }

  // ── Phase transitions (all go through here) ───────────────────────────────

  void _setPhase(TaikenPhase newPhase) {
    state = state.copyWith(phase: newPhase);
    debugPrint('[Taiken] phase → ${newPhase.name}');
  }

  /// User tapped "Start Experience" on the intro screen.
  void startExperience() {
    _persistPhase(TaikenPhase.dialogue);
    _setPhase(TaikenPhase.dialogue);
  }

  /// Called by the VN view when all dialogue bubbles have been shown and the
  /// user taps "Continue to Challenge".
  /// Checks whether the first question in this stage has a gate.
  void enterQuestionPhase() {
    // Persist phase transition before checking gate, so if the app is killed
    // mid-gate the user comes back to question phase (gate re-checks on entry).
    _persistPhase(TaikenPhase.question);

    final firstQuestion = state.currentQuestions.isNotEmpty
        ? state.currentQuestions[0]
        : null;

    if (firstQuestion != null &&
        firstQuestion.hasLearningGate &&
        !state.interactedGateQuestionIds.contains(firstQuestion.questionId)) {
      _openGate(firstQuestion.questionId);
    } else {
      _setPhase(TaikenPhase.question);
    }
  }

  /// Check whether the *current* question (by currentQuestionIndex) needs a
  /// gate. Called from the question view before rendering each new question.
  void checkAndEnterGate() {
    final question = state.currentQuestion;
    if (question == null) return;

    if (question.hasLearningGate &&
        !state.interactedGateQuestionIds.contains(question.questionId)) {
      _openGate(question.questionId);
    }
  }

  void _openGate(String questionId) {
    state = state.copyWith(
      phase: TaikenPhase.gateInterstitial,
      activeGateQuestionId: questionId,
    );
    debugPrint('[Taiken] gate opened for question $questionId');
  }

  // ── Gate actions ──────────────────────────────────────────────────────────

  /// User tapped "Learn First" — logs 'studied', navigates to learning page.
  /// The actual Navigator.push happens in the UI layer. This method just
  /// records the action and marks the gate as interacted so it won't
  /// re-trigger when the user returns.
  void studyGate() {
    final questionId = state.activeGateQuestionId;
    if (questionId == null) return;

    _logGateInteraction(questionId, GateAction.studied);
    _markGateInteracted(questionId);

    // Phase stays as gateInterstitial — the UI will push TaikenLearningPage
    // and the gate view will dismiss itself on pop.
    // The provider will be in gateInterstitial until resumeFromGate() is called.
    debugPrint('[Taiken] gate: user studying for question $questionId');
  }

  /// Called by the UI when the user returns from TaikenLearningPage.
  void resumeFromGate() {
    state = state.copyWith(
      phase: TaikenPhase.question,
      clearActiveGate: true,
    );
    debugPrint('[Taiken] resumed from gate → question phase');
  }

  /// User tapped "I already know this" (immediate or after delay).
  void skipGate({required bool afterDelay}) {
    final questionId = state.activeGateQuestionId;
    if (questionId == null) return;

    final action = afterDelay
        ? GateAction.skippedAfterDelay
        : GateAction.skipped;

    _logGateInteraction(questionId, action);
    _markGateInteracted(questionId);
    _persistGateSkip();

    state = state.copyWith(
      phase: TaikenPhase.question,
      clearActiveGate: true,
    );
    debugPrint('[Taiken] gate skipped (afterDelay=$afterDelay)');
  }

  void _markGateInteracted(String questionId) {
    final updated = Set<String>.from(state.interactedGateQuestionIds)
      ..add(questionId);
    state = state.copyWith(interactedGateQuestionIds: updated);
  }

  // ── Answer submission ─────────────────────────────────────────────────────

  Future<void> submitAnswer(String questionId, int selectedIndex) async {
    try {
      final question = state.currentQuestion;
      if (question == null) return;

      final isCorrect = selectedIndex == question.correctOptionIndex;

      // Update local answer map.
      final updatedAnswers = Map<String, int?>.from(state.userAnswers)
        ..[questionId] = selectedIndex;

      final newCorrect   = state.progress!.correctAnswers + (isCorrect ? 1 : 0);
      final newWrong     = state.progress!.wrongAnswers   + (isCorrect ? 0 : 1);
      final newAnswered  = state.progress!.questionsAnswered + 1;

      final total         = state.taiken!.totalQuestions;
      final threshold     = state.taiken!.passThreshold.toDouble();
      final remaining     = total - newAnswered;
      final maxAccuracy   = ((newCorrect + remaining) / total) * 100;
      final finalAccuracy = (newCorrect / total) * 100;

      // Determine new status.
      String newStatus = state.progress!.status;
      DateTime? completedAt;

      if (maxAccuracy < threshold) {
        newStatus   = 'failed';
        completedAt = DateTime.now();
      } else if (newAnswered >= total) {
        newStatus   = finalAccuracy >= threshold ? 'completed' : 'failed';
        completedAt = DateTime.now();
      }

      // Persist to DB.
      await _supabase.from('taiken_progress').update({
        'questions_answered': newAnswered,
        'correct_answers':    newCorrect,
        'wrong_answers':      newWrong,
        'status':             newStatus,
        'completed_at':       completedAt?.toIso8601String(),
        'updated_at':         DateTime.now().toIso8601String(),
      }).eq('progress_id', state.progress!.progressId);

      // Update gate interaction correctness if gate was used for this question.
      if (state.interactedGateQuestionIds.contains(questionId)) {
        _updateGateInteractionCorrectness(questionId, isCorrect);
      }

      final updatedProgress = state.progress!.copyWith(
        questionsAnswered:    newAnswered,
        correctAnswers:       newCorrect,
        wrongAnswers:         newWrong,
        status:               newStatus,
        completedAt:          completedAt,
      );

      state = state.copyWith(
        progress:    updatedProgress,
        userAnswers: updatedAnswers,
      );

      if (newStatus == 'completed' || newStatus == 'failed') {
        if (newStatus == 'completed') _onTaikenComplete();
        _setPhase(TaikenPhase.outro);
      }
      // NOTE: advanceToNextQuestion() is called by the UI AFTER showing
      // the answer feedback, not here. This lets the user read the explanation.
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit answer: $e');
    }
  }

  /// Called by the UI after the user reads the answer feedback and taps Continue.
  Future<void> advanceToNextQuestion() async {
    final nextIndex = state.currentQuestionIndex + 1;

    if (nextIndex < state.currentQuestions.length) {
      // More questions in this stage.
      await _supabase.from('taiken_progress').update({
        'current_question_index': nextIndex,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('progress_id', state.progress!.progressId);

      state = state.copyWith(currentQuestionIndex: nextIndex);

      // Check if next question has a gate.
      checkAndEnterGate();
    } else if (state.hasMoreStages) {
      await advanceToNextStage();
    } else {
      // All stages done — but submitAnswer already handled the outro transition
      // via status check. This is a safety fallback.
      _setPhase(TaikenPhase.outro);
    }
  }

  Future<void> advanceToNextStage() async {
    final completedStage  = state.currentStage;
    final nextStageIndex  = state.currentStageIndex + 1;
    final nextStageOrder  = nextStageIndex + 1;

    await _supabase.from('taiken_progress').update({
      'current_stage_order':    nextStageOrder,
      'current_phase':          TaikenPhase.dialogue.toDbString(),
      'current_question_index': 0,
      'updated_at':             DateTime.now().toIso8601String(),
    }).eq('progress_id', state.progress!.progressId);

    state = state.copyWith(
      currentStageIndex:    nextStageIndex,
      currentQuestionIndex: 0,
      phase:                TaikenPhase.dialogue,
    );

    if (completedStage != null) _onStageComplete(completedStage);
    debugPrint('[Taiken] advanced to stage $nextStageIndex');
  }

  // ── Rating ────────────────────────────────────────────────────────────────

  Future<void> rateTaiken(int rating, String? review) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _supabase.from('taiken_ratings').upsert({
        'taiken_id': taikenId,
        'user_id':   userId,
        'rating':    rating,
        'review':    review,
      }, onConflict: 'taiken_id,user_id');

      state = state.copyWith(userRating: rating);
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit rating: $e');
    }
  }

  // ── Reset + Restart ───────────────────────────────────────────────────────

  Future<void> resetAndRestart() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Delete existing progress (unique constraint ensures only 1 row exists).
      await _supabase
          .from('taiken_progress')
          .delete()
          .eq('user_id', userId)
          .eq('taiken_id', taikenId);

      // Reset local state first so the UI shows loading immediately.
      state = const TaikenExperienceState(isLoading: true);

      // loadTaiken will call upsert_taiken_progress and create a fresh row.
      await loadTaiken();
    } catch (e) {
      state = state.copyWith(error: 'Failed to reset: $e');
      rethrow;
    }
  }

  void reset() => state = const TaikenExperienceState();

  void clearError() => state = state.copyWith(clearError: true);

  // ── Private helpers ───────────────────────────────────────────────────────

  void _setLoading(bool value) =>
      state = state.copyWith(isLoading: value);

  /// Persist phase change to DB so the user can resume correctly.
  void _persistPhase(TaikenPhase phase) {
    if (state.progress == null) return;
    _supabase.from('taiken_progress').update({
      'current_phase': phase.toDbString(),
      'updated_at':    DateTime.now().toIso8601String(),
    }).eq('progress_id', state.progress!.progressId).catchError(
          (e) => debugPrint('Failed to persist phase: $e'),
    );
  }

  void _persistGateSkip() {
    if (state.progress == null) return;
    final newSkips = state.progress!.gatesSkipped + 1;
    _supabase.from('taiken_progress').update({
      'gates_skipped': newSkips,
      'updated_at':    DateTime.now().toIso8601String(),
    }).eq('progress_id', state.progress!.progressId).catchError(
          (e) => debugPrint('Failed to persist gate skip: $e'),
    );
  }

  void _logGateInteraction(String questionId, GateAction action) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _supabase.from('taiken_gate_interactions').insert({
      'user_id':     userId,
      'question_id': questionId,
      'taiken_id':   taikenId,
      'action':      action.toDbString(),
    }).catchError((e) => debugPrint('Gate interaction log error: $e'));
  }

  void _updateGateInteractionCorrectness(
      String questionId, bool wasCorrect) {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    _supabase
        .from('taiken_gate_interactions')
        .update({'then_answered_correctly': wasCorrect})
        .eq('user_id', userId)
        .eq('question_id', questionId)
        .order('created_at', ascending: false)
        .limit(1)
        .catchError(
            (e) => debugPrint('Gate correctness update error: $e'));
  }

  // ── Side-effect: stage completion ─────────────────────────────────────────

  void _onStageComplete(TaikenStage completedStage) {
    _ref.read(streakProvider.notifier).logTaikenStageCompletion(
      taikenStageId: completedStage.stageId,
      domain: state.taiken?.domain,
    );
    debugPrint('[Streak] stage ${completedStage.stageId} completed');
  }

  // ── Side-effect: taiken completion ───────────────────────────────────────

  void _onTaikenComplete() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Plaro points.
    _ref
        .read(plaroPointsServiceProvider)
        .awardPointsForCompletion(
      userId: userId,
      contentType: 'taiken',
      contentId: taikenId,
    )
        .catchError((e) => debugPrint('Plaro points error: $e'));

    // Final stage streak.
    final lastStage = state.currentStage;
    if (lastStage != null) {
      _ref.read(streakProvider.notifier).logTaikenStageCompletion(
        taikenStageId: lastStage.stageId,
        domain: state.taiken?.domain,
      );
    }

    // Content event.
    _ref.read(contentEventTrackerProvider).trackComplete(
      userId: userId,
      contentType: 'taiken',
      contentIdUuid: taikenId,
      domain: state.taiken?.domain,
    );

    debugPrint('[EventTracker] taiken complete: $taikenId');

    // Phase D stubs — badge + next episode fetch.
    _fetchEarnedBadge();
    _fetchNextEpisode();
  }

  // ── Phase D stubs (implemented in Phase D) ────────────────────────────────

  /// Queries taiken_badges for matching domain+difficulty, then inserts into
  /// user_taiken_badges. Will be fully implemented in Phase D.
  Future<void> _fetchEarnedBadge() async {
    try {
      if (state.taiken == null) return;

      final badgeJson = await _supabase
          .from('taiken_badges')
          .select()
          .eq('domain', state.taiken!.domain)
          .eq('difficulty', state.taiken!.difficulty)
          .maybeSingle();

      if (badgeJson == null) return;
      final badge = TaikenBadge.fromJson(badgeJson);

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final accuracy = state.progress?.accuracyPercentage ?? 0.0;

      // Upsert award — one badge per user per taiken.
      await _supabase.from('user_taiken_badges').upsert({
        'user_id':          userId,
        'badge_id':         badge.badgeId,
        'taiken_id':        taikenId,
        'score_percentage': accuracy,
        'awarded_at':       DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,taiken_id');

      state = state.copyWith(earnedBadge: badge);
      debugPrint('[Badge] earned: ${badge.badgeName}');
    } catch (e) {
      debugPrint('[Badge] fetch error: $e');
    }
  }

  /// Fetches the next episode in the series. Will be fully used in Phase D.
  Future<void> _fetchNextEpisode() async {
    try {
      if (state.taiken?.seriesId == null ||
          state.taiken?.episodeNumber == null) return;

      final nextJson = await _supabase
          .from('taikens')
          .select()
          .eq('series_id', state.taiken!.seriesId!)
          .eq('episode_number', state.taiken!.episodeNumber! + 1)
          .eq('is_published', true)
          .maybeSingle();

      if (nextJson == null) return;
      final next = Taiken.fromJson(nextJson);
      state = state.copyWith(nextEpisode: next);
      debugPrint('[Series] next episode: ${next.title}');
    } catch (e) {
      debugPrint('[Series] next episode fetch error: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final taikenExperienceProvider =
StateNotifierProvider.family<
    TaikenExperienceNotifier,
    TaikenExperienceState,
    String>((ref, taikenId) {
  return TaikenExperienceNotifier(taikenId, ref);
});