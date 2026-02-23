import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Model/taiken.dart';
import 'plaro_points_service.dart'; // ✅ NEW
import 'streak_provider.dart';      // ✅ NEW

// =============================================================================
// STATE  (unchanged)
// =============================================================================

class TaikenExperienceState {
  final Taiken? taiken;
  final List<TaikenStage> stages;
  final List<TaikenCharacter> characters;
  final Map<String, List<TaikenDialogue>> dialoguesByStage;
  final Map<String, List<TaikenQuestion>> questionsByStage;
  final TaikenProgress? progress;
  final int currentStageIndex;
  final int currentDialogueIndex;
  final int currentQuestionIndex;
  final bool isLoading;
  final String? error;
  final bool showingIntro;
  final bool showingOutro;
  final Map<String, int?> userAnswers;
  final int? userRating;

  TaikenExperienceState({
    this.taiken,
    this.stages = const [],
    this.characters = const [],
    this.dialoguesByStage = const {},
    this.questionsByStage = const {},
    this.progress,
    this.currentStageIndex = 0,
    this.currentDialogueIndex = 0,
    this.currentQuestionIndex = 0,
    this.isLoading = false,
    this.error,
    this.showingIntro = true,
    this.showingOutro = false,
    this.userAnswers = const {},
    this.userRating,
  });

  TaikenExperienceState copyWith({
    Taiken? taiken,
    List<TaikenStage>? stages,
    List<TaikenCharacter>? characters,
    Map<String, List<TaikenDialogue>>? dialoguesByStage,
    Map<String, List<TaikenQuestion>>? questionsByStage,
    TaikenProgress? progress,
    int? currentStageIndex,
    int? currentDialogueIndex,
    int? currentQuestionIndex,
    bool? isLoading,
    String? error,
    bool? showingIntro,
    bool? showingOutro,
    Map<String, int?>? userAnswers,
    int? userRating,
  }) {
    return TaikenExperienceState(
      taiken: taiken ?? this.taiken,
      stages: stages ?? this.stages,
      characters: characters ?? this.characters,
      dialoguesByStage: dialoguesByStage ?? this.dialoguesByStage,
      questionsByStage: questionsByStage ?? this.questionsByStage,
      progress: progress ?? this.progress,
      currentStageIndex: currentStageIndex ?? this.currentStageIndex,
      currentDialogueIndex: currentDialogueIndex ?? this.currentDialogueIndex,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      showingIntro: showingIntro ?? this.showingIntro,
      showingOutro: showingOutro ?? this.showingOutro,
      userAnswers: userAnswers ?? this.userAnswers,
      userRating: userRating ?? this.userRating,
    );
  }

  TaikenStage? get currentStage =>
      currentStageIndex < stages.length ? stages[currentStageIndex] : null;

  List<TaikenDialogue> get currentDialogues =>
      currentStage != null ? dialoguesByStage[currentStage!.stageId] ?? [] : [];

  List<TaikenQuestion> get currentQuestions =>
      currentStage != null ? questionsByStage[currentStage!.stageId] ?? [] : [];

  bool get hasMoreDialogues => currentDialogueIndex < currentDialogues.length;
  bool get hasMoreQuestions => currentQuestionIndex < currentQuestions.length;
  bool get hasMoreStages => currentStageIndex < stages.length - 1;
}

// =============================================================================
// NOTIFIER
// ✅ Two changes from original:
//   1. Constructor takes (taikenId, ref) instead of (taikenId)
//   2. advanceToNextStage() fires _onStageComplete(); submitAnswer() fires
//      _onTaikenComplete() on pass. Everything else is byte-for-byte identical.
// =============================================================================

class TaikenExperienceNotifier extends StateNotifier<TaikenExperienceState> {
  TaikenExperienceNotifier(this.taikenId, this._ref)  // ✅ added _ref
      : super(TaikenExperienceState());

  final String taikenId;
  final Ref _ref;                                       // ✅ NEW
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> loadTaiken() async {
    state = state.copyWith(isLoading: true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final taikenResponse = await _supabase
          .from('taikens')
          .select()
          .eq('taiken_id', taikenId)
          .single();
      final taiken = Taiken.fromJson(taikenResponse);

      final stagesResponse = await _supabase
          .from('taiken_stages')
          .select()
          .eq('taiken_id', taikenId)
          .order('stage_order');
      final stages = (stagesResponse as List)
          .map((json) => TaikenStage.fromJson(json))
          .toList();

      final charactersResponse = await _supabase
          .from('taiken_characters')
          .select()
          .eq('taiken_id', taikenId)
          .order('display_order');
      final characters = (charactersResponse as List)
          .map((json) => TaikenCharacter.fromJson(json))
          .toList();

      final Map<String, List<TaikenDialogue>> dialoguesByStage = {};
      for (final stage in stages) {
        final dialoguesResponse = await _supabase
            .from('taiken_dialogues')
            .select()
            .eq('stage_id', stage.stageId)
            .order('dialogue_order');
        dialoguesByStage[stage.stageId] = (dialoguesResponse as List)
            .map((json) => TaikenDialogue.fromJson(json))
            .toList();
      }

      final Map<String, List<TaikenQuestion>> questionsByStage = {};
      for (final stage in stages) {
        final questionsResponse = await _supabase
            .from('taiken_questions')
            .select()
            .eq('stage_id', stage.stageId)
            .order('question_order');
        questionsByStage[stage.stageId] = (questionsResponse as List)
            .map((json) => TaikenQuestion.fromJson(json))
            .toList();
      }

      TaikenProgress? progress;
      try {
        final progressResponse = await _supabase
            .from('taiken_progress')
            .select()
            .eq('user_id', userId)
            .eq('taiken_id', taikenId)
            .order('created_at', ascending: false)
            .limit(1)
            .single();
        progress = TaikenProgress.fromJson(progressResponse);
      } catch (e) {
        final newProgressData = {
          'user_id': userId,
          'taiken_id': taikenId,
          'current_stage_order': 1,
          'questions_answered': 0,
          'correct_answers': 0,
          'wrong_answers': 0,
          'status': 'in_progress',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        final createdProgress = await _supabase
            .from('taiken_progress')
            .insert(newProgressData)
            .select()
            .single();
        progress = TaikenProgress.fromJson(createdProgress);
      }

      int? existingRating;
      try {
        final ratingResponse = await _supabase
            .from('taiken_ratings')
            .select()
            .eq('user_id', userId)
            .eq('taiken_id', taikenId)
            .single();
        existingRating = ratingResponse['rating'] as int?;
      } catch (e) {
        // No rating yet
      }

      final showingIntro =
          progress.currentStageOrder == 1 && progress.questionsAnswered == 0;
      final currentStageIndex = progress.currentStageOrder - 1;

      state = state.copyWith(
        taiken: taiken,
        stages: stages,
        characters: characters,
        dialoguesByStage: dialoguesByStage,
        questionsByStage: questionsByStage,
        progress: progress,
        currentStageIndex: currentStageIndex,
        currentDialogueIndex: 0,
        currentQuestionIndex: 0,
        showingIntro: showingIntro,
        showingOutro: false,
        isLoading: false,
        error: null,
        userRating: existingRating,
        userAnswers: {},
      );

      if (progress.questionsAnswered == 0) {
        await _supabase
            .rpc('increment_play_count', params: {'taiken_id': taikenId});
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load Taiken: $e',
      );
    }
  }

  void startExperience() => state = state.copyWith(showingIntro: false);

  void advanceDialogue() {
    if (state.hasMoreDialogues) {
      state = state.copyWith(
          currentDialogueIndex: state.currentDialogueIndex + 1);
    } else {
      state = state.copyWith(currentQuestionIndex: 0);
    }
  }

  Future<void> submitAnswer(String questionId, int selectedIndex) async {
    try {
      final question = state.currentQuestions[state.currentQuestionIndex];
      final isCorrect = selectedIndex == question.correctOptionIndex;

      final updatedAnswers = Map<String, int?>.from(state.userAnswers);
      updatedAnswers[questionId] = selectedIndex;

      final newCorrectAnswers =
          state.progress!.correctAnswers + (isCorrect ? 1 : 0);
      final newWrongAnswers =
          state.progress!.wrongAnswers + (isCorrect ? 0 : 1);
      final newQuestionsAnswered = state.progress!.questionsAnswered + 1;

      final totalQuestions = state.taiken!.totalQuestions;
      final passThreshold = state.taiken!.passThreshold;

      final questionsRemaining = totalQuestions - newQuestionsAnswered;
      final maxPossibleCorrect = newCorrectAnswers + questionsRemaining;
      final maxPossibleAccuracy = (maxPossibleCorrect / totalQuestions) * 100;

      String newStatus = state.progress!.status;
      DateTime? completedAt;

      if (maxPossibleAccuracy < passThreshold) {
        newStatus = 'failed';
        completedAt = DateTime.now();
      } else if (newQuestionsAnswered >= totalQuestions) {
        final finalAccuracy = (newCorrectAnswers / totalQuestions) * 100;
        newStatus = finalAccuracy >= passThreshold ? 'completed' : 'failed';
        completedAt = DateTime.now();
      }

      await _supabase.from('taiken_progress').update({
        'questions_answered': newQuestionsAnswered,
        'correct_answers': newCorrectAnswers,
        'wrong_answers': newWrongAnswers,
        'status': newStatus,
        'completed_at': completedAt?.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('progress_id', state.progress!.progressId);

      final updatedProgress = state.progress!.copyWith(
        questionsAnswered: newQuestionsAnswered,
        correctAnswers: newCorrectAnswers,
        wrongAnswers: newWrongAnswers,
        status: newStatus,
        completedAt: completedAt,
      );

      state = state.copyWith(
        progress: updatedProgress,
        userAnswers: updatedAnswers,
      );

      if (newStatus == 'completed' || newStatus == 'failed') {
        // ✅ Award streak + Plaro points on a clean pass
        if (newStatus == 'completed') {
          _onTaikenComplete();
        }
        state = state.copyWith(showingOutro: true);
      } else {
        advanceToNextQuestion();
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit answer: $e');
    }
  }

  void advanceToNextQuestion() {
    if (state.currentQuestionIndex < state.currentQuestions.length - 1) {
      state = state.copyWith(
          currentQuestionIndex: state.currentQuestionIndex + 1);
    } else if (state.hasMoreStages) {
      advanceToNextStage();
    } else {
      state = state.copyWith(showingOutro: true);
    }
  }

  Future<void> advanceToNextStage() async {
    // ✅ Capture before advancing index
    final completedStage = state.currentStage;

    final nextStageIndex = state.currentStageIndex + 1;
    final nextStageOrder = nextStageIndex + 1;

    await _supabase.from('taiken_progress').update({
      'current_stage_order': nextStageOrder,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('progress_id', state.progress!.progressId);

    state = state.copyWith(
      currentStageIndex: nextStageIndex,
      currentDialogueIndex: 0,
      currentQuestionIndex: 0,
    );

    // ✅ Fire streak for the completed intermediate stage
    if (completedStage != null) {
      _onStageComplete(completedStage);
    }
  }

  Future<void> rateTaiken(int rating, String? review) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _supabase.from('taiken_ratings').upsert({
        'taiken_id': taikenId,
        'user_id': userId,
        'rating': rating,
        'review': review,
      }, onConflict: 'taiken_id,user_id');
    } catch (e) {
      state = state.copyWith(error: 'Failed to submit rating: $e');
    }
  }

  Future<void> resetAndRestart() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _supabase
          .from('taiken_progress')
          .delete()
          .eq('user_id', userId)
          .eq('taiken_id', taikenId);

      await Future.delayed(const Duration(milliseconds: 100));

      state = TaikenExperienceState(
        showingIntro: true,
        showingOutro: false,
        currentStageIndex: 0,
        currentDialogueIndex: 0,
        currentQuestionIndex: 0,
        userAnswers: {},
      );

      await loadTaiken();

      if (state.progress?.currentStageOrder != 1 ||
          state.progress?.questionsAnswered != 0) {
        throw Exception('Failed to reset progress properly');
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to reset progress: $e');
      rethrow;
    }
  }

  void reset() => state = TaikenExperienceState();

  // ---------------------------------------------------------------------------
  // ✅ NEW: side-effect helpers — fire-and-forget, never block UI
  // ---------------------------------------------------------------------------

  /// Player finished all questions in an intermediate stage → log streak.
  void _onStageComplete(TaikenStage completedStage) {
    _ref.read(streakProvider.notifier).logTaikenStageCompletion(
      taikenStageId: completedStage.stageId,
      domain: state.taiken?.domain,
    );
    debugPrint('🔥 Streak: stage ${completedStage.stageId} completed');
  }

  /// Player passed the whole taiken → award Plaro points + log final stage.
  void _onTaikenComplete() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Award 5 Plaro completion points (non-blocking)
    _ref
        .read(plaroPointsServiceProvider)
        .awardPointsForCompletion(
      userId: userId,
      contentType: 'taiken',
      contentId: taikenId,
    )
        .catchError((e) => debugPrint('❌ Plaro points error: $e'));

    // Log the final stage as a streak event (advanceToNextStage only fires
    // for intermediate stages, so the last one is handled here)
    final lastStage = state.currentStage;
    if (lastStage != null) {
      _ref.read(streakProvider.notifier).logTaikenStageCompletion(
        taikenStageId: lastStage.stageId,
        domain: state.taiken?.domain,
      );
      debugPrint('🔥 Streak: final stage ${lastStage.stageId} completed');
    }
  }
}

// =============================================================================
// PROVIDER  ✅ passes ref
// =============================================================================

final taikenExperienceProvider = StateNotifierProvider.family<
    TaikenExperienceNotifier,
    TaikenExperienceState,
    String>((ref, taikenId) {
  return TaikenExperienceNotifier(taikenId, ref);
});