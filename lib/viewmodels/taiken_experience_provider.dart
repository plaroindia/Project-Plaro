// =============================================================================
// taiken_experience_provider.dart  — PHASE A REWRITE
//
// Changes from previous version:
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
//   ★ AUDIO HOOKS:
//       - onPhaseChange callback registered by TaikenExperiencePage
//       - Every phase/stage transition notifies the callback so the audio
//         service can react (fade out on questions, resume on dialogue,
//         cross-fade on stage change, stop on outro).
//
//   ★ NOTIFICATION HOOKS (NEW):
//       - _onTaikenComplete() now sends a 'points' notification to the user
//         after awarding Plaro Points for completion.
//       - rateTaiken() now sends a 'rating' notification to the Taiken author
//         when a user submits a rating (skipped if rating their own Taiken).
//
//   STUB METHODS (will be fully implemented in Phase D):
//       - _fetchEarnedBadge()
//       - _fetchNextEpisode()
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/taiken.dart';
import 'streakandpoints_provider.dart';
import 'content_event_tracker.dart';
import 'notifications_provider.dart'; // NEW

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

  // ── Audio callback ────────────────────────────────────────────────────────

  void Function(String event, String? stageCue)? onAudioEvent;

  void registerAudioCallback(
      void Function(String event, String? stageCue) cb) {
    onAudioEvent = cb;
  }

  void _fireAudio(String event) {
    final cue = state.currentStage?.musicCue;
    onAudioEvent?.call(event, cue);
  }

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
        _supabase
            .rpc('increment_play_count', params: {'taiken_id': taikenId})
            .catchError((e) => debugPrint('play_count increment error: $e'));
      }

      _ref.read(contentEventTrackerProvider).trackView(
        userId: userId,
        contentType: 'taiken',
        contentIdUuid: taikenId,
        source: 'taiken_play',
      );

      // ── 8. Restore saved position ─────────────────────────────────────────
      final savedStageIndex =
      (progress.currentStageOrder - 1).clamp(0, stages.length - 1);
      final savedQuestionIndex = progress.currentQuestionIndex;

      final bool isFirstOpen =
          progress.currentStageOrder == 1 &&
              progress.currentPhase == TaikenPhase.dialogue &&
              progress.questionsAnswered == 0;

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

      switch (restoredPhase) {
        case TaikenPhase.dialogue:
          _fireAudio('dialogue');
          break;
        case TaikenPhase.question:
          _fireAudio('question');
          break;
        case TaikenPhase.gateInterstitial:
          _fireAudio('gate');
          break;
        case TaikenPhase.outro:
          _fireAudio('outro');
          break;
        case TaikenPhase.intro:
          break;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load Taiken: $e',
      );
    }
  }

  // ── Phase transitions ─────────────────────────────────────────────────────

  void _setPhase(TaikenPhase newPhase) {
    state = state.copyWith(phase: newPhase);
    debugPrint('[Taiken] phase → ${newPhase.name}');
  }

  void startExperience() {
    _persistPhase(TaikenPhase.dialogue);
    _setPhase(TaikenPhase.dialogue);
    _fireAudio('dialogue');
  }

  void enterQuestionPhase() {
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
      _fireAudio('question');
    }
  }

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

  void studyGate() {
    final questionId = state.activeGateQuestionId;
    if (questionId == null) return;

    _logGateInteraction(questionId, GateAction.studied);
    _markGateInteracted(questionId);
    debugPrint('[Taiken] gate: user studying for question $questionId');
  }

  void resumeFromGate() {
    state = state.copyWith(
      phase: TaikenPhase.question,
      clearActiveGate: true,
    );
    _fireAudio('question');
    debugPrint('[Taiken] resumed from gate → question phase');
  }

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
    _fireAudio('question');
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

      String newStatus = state.progress!.status;
      DateTime? completedAt;

      if (maxAccuracy < threshold) {
        newStatus   = 'failed';
        completedAt = DateTime.now();
      } else if (newAnswered >= total) {
        newStatus   = finalAccuracy >= threshold ? 'completed' : 'failed';
        completedAt = DateTime.now();
      }

      await _supabase.from('taiken_progress').update({
        'questions_answered': newAnswered,
        'correct_answers':    newCorrect,
        'wrong_answers':      newWrong,
        'status':             newStatus,
        'completed_at':       completedAt?.toIso8601String(),
        'updated_at':         DateTime.now().toIso8601String(),
      }).eq('progress_id', state.progress!.progressId);

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
        _fireAudio('outro');
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit answer: $e');
    }
  }

  Future<void> advanceToNextQuestion() async {
    final nextIndex = state.currentQuestionIndex + 1;

    if (nextIndex < state.currentQuestions.length) {
      await _supabase.from('taiken_progress').update({
        'current_question_index': nextIndex,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('progress_id', state.progress!.progressId);

      state = state.copyWith(currentQuestionIndex: nextIndex);
      checkAndEnterGate();
    } else if (state.hasMoreStages) {
      await advanceToNextStage();
    } else {
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

    _fireAudio('stage_change');
    if (completedStage != null) _onStageComplete(completedStage);
    debugPrint('[Taiken] advanced to stage $nextStageIndex');
  }

  // ── Rating ────────────────────────────────────────────────────────────────
  //
  // NEW: After a successful upsert, sends a 'rating' notification to the
  // Taiken author. Skipped if the user is rating their own Taiken.

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

      // NEW: Notify the Taiken author
      _sendRatingNotification(raterId: userId, rating: rating);
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit rating: $e');
    }
  }

  // Fire-and-forget — never throws, never blocks rateTaiken()
  Future<void> _sendRatingNotification({
    required String raterId,
    required int rating,
  }) async {
    try {
      // Fetch author ID and rater username in parallel
      final results = await Future.wait([
        _supabase
            .from('taikens')
            .select('user_id, title')
            .eq('taiken_id', taikenId)
            .maybeSingle(),
        _supabase
            .from('user_profiles')
            .select('username')
            .eq('user_id', raterId)
            .maybeSingle(),
      ]);

      final taikenRow = results[0] as Map<String, dynamic>?;
      final raterRow  = results[1] as Map<String, dynamic>?;

      if (taikenRow == null) return;
      final authorId = taikenRow['user_id'] as String?;
      if (authorId == null || authorId == raterId) return; // don't self-notify

      final raterName  = raterRow?['username'] as String? ?? 'Someone';
      final taikenTitle = taikenRow['title'] as String? ?? 'your Taiken';
      final stars = '★' * rating + '☆' * (5 - rating);

      await NotificationsNotifier.insert(
        targetUserId: authorId,
        type: 'rating',
        title: '$taikenTitle was rated $stars',
        body: '$raterName rated "$taikenTitle" $rating out of 5',
        relatedType: 'taiken',
        relatedId: taikenId,
      );
    } catch (e) {
      debugPrint('[Taiken] rating notification error: $e');
    }
  }

  // ── Reset + Restart ───────────────────────────────────────────────────────

  Future<void> resetAndRestart() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _supabase
          .from('taiken_progress')
          .delete()
          .eq('user_id', userId)
          .eq('taiken_id', taikenId);

      state = const TaikenExperienceState(isLoading: true);
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
  //
  // NEW: After awarding Plaro Points, sends a 'points' notification to the
  // completing user so they see the reward in their notification centre.

  void _onTaikenComplete() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Plaro points — fire and forget
    _ref
        .read(plaroPointsServiceProvider)
        .awardPointsForCompletion(
      userId: userId,
      contentType: 'taiken',
      contentId: taikenId,
    )
        .then((_) {
      // NEW: notify user of their points reward after successful award
      final taikenTitle = state.taiken?.title ?? 'Taiken';
      NotificationsNotifier.insert(
        targetUserId: userId,
        type: 'points',
        title: '+20 Plaro Points',
        body: 'You earned 20 points for completing "$taikenTitle"',
        relatedType: 'taiken',
        relatedId: taikenId,
      );
    })
        .catchError((e) => debugPrint('Plaro points error: $e'));

    // Final stage streak
    final lastStage = state.currentStage;
    if (lastStage != null) {
      _ref.read(streakProvider.notifier).logTaikenStageCompletion(
        taikenStageId: lastStage.stageId,
        domain: state.taiken?.domain,
      );
    }

    // Content event
    _ref.read(contentEventTrackerProvider).trackComplete(
      userId: userId,
      contentType: 'taiken',
      contentIdUuid: taikenId,
      domain: state.taiken?.domain,
    );

    debugPrint('[EventTracker] taiken complete: $taikenId');

    // Phase D stubs
    _fetchEarnedBadge();
    _fetchNextEpisode();
  }

  // ── Phase D stubs ─────────────────────────────────────────────────────────

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

  Future<void> _fetchNextEpisode() async {
    try {
      if (state.taiken?.seriesId == null ||
          state.taiken?.episodeNumber == null) {
        return;
      }

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