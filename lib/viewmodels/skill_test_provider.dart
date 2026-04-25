// =============================================================================
// skill_test_provider.dart
//
// Manages the entire skill-test flow:
//   1. Generates questions via SkillTestAiService (Gemini).
//   2. Tracks the user's answers as they progress.
//   3. On completion, scores each skill and upserts into user_skill_memory.
//
// Scoring model
// ─────────────
// For each skill the user answers N questions.  We compute:
//
//   raw_score       = correct / total               (0.0 – 1.0)
//   self_confidence = onboarding confidence field   (1-5 mapped to 0.2-1.0)
//   confidence_score = lerp(raw_score, self_confidence, 0.3)
//     → blends 70 % test performance with 30 % self-declared confidence
//
// The result is stored in user_skill_memory:
//   confidence_score   — blended 0-1 value
//   practice_count     — incremented by 1 (or set to 1 on first test)
//   last_practiced_at  — now()
//   evidence           — JSON with raw_score, questions_count, difficulty,
//                        test_type: 'initial_skill_test'
//
// The test CANNOT be failed.  All feedback is positive / constructive.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../service/skill_test_ai_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Enums & helpers
// ─────────────────────────────────────────────────────────────────────────────

enum SkillTestPhase {
  idle,
  generating,
  inProgress,
  submitting,
  completed,
  error,
}

// Maps the user's self-reported confidence (1-5) to a 0-1 float
double _mapSelfConfidence(int? raw) {
  if (raw == null) return 0.5;
  return ((raw.clamp(1, 5) - 1) / 4.0) * 0.8 + 0.2; // maps 1→0.2, 5→1.0
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class SkillTestState {
  final SkillTestPhase phase;
  final String? error;

  // Generated content
  final SkillTestOutput? testOutput;

  // Navigation: which skill group and question index we're on
  final int currentGroupIndex;
  final int currentQuestionIndex;

  // Per-question answer tracking: groupIndex → {questionIndex → selectedOptionIndex}
  final Map<int, Map<int, int>> answers;

  // Per-question "answered" flag (so we can show feedback before advancing)
  final bool hasAnsweredCurrent;

  // Results after completion
  final List<SkillResult>? results;

  const SkillTestState({
    this.phase = SkillTestPhase.idle,
    this.error,
    this.testOutput,
    this.currentGroupIndex = 0,
    this.currentQuestionIndex = 0,
    this.answers = const {},
    this.hasAnsweredCurrent = false,
    this.results,
  });

  SkillTestState copyWith({
    SkillTestPhase? phase,
    String? error,
    bool clearError = false,
    SkillTestOutput? testOutput,
    int? currentGroupIndex,
    int? currentQuestionIndex,
    Map<int, Map<int, int>>? answers,
    bool? hasAnsweredCurrent,
    List<SkillResult>? results,
  }) {
    return SkillTestState(
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      testOutput: testOutput ?? this.testOutput,
      currentGroupIndex: currentGroupIndex ?? this.currentGroupIndex,
      currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
      answers: answers ?? this.answers,
      hasAnsweredCurrent: hasAnsweredCurrent ?? this.hasAnsweredCurrent,
      results: results ?? this.results,
    );
  }

  // ── Derived helpers ────────────────────────────────────────────────────────

  bool get isLoading =>
      phase == SkillTestPhase.generating ||
      phase == SkillTestPhase.submitting;

  /// Total number of questions across all groups
  int get totalQuestions =>
      testOutput?.groups.fold(0, (sum, g) => sum! + g.questions.length) ?? 0;

  /// 1-based overall question number (for progress display)
  int get overallQuestionNumber {
    if (testOutput == null) return 0;
    int count = 0;
    for (int g = 0; g < currentGroupIndex; g++) {
      count += testOutput!.groups[g].questions.length;
    }
    return count + currentQuestionIndex + 1;
  }

  /// Currently displayed group (null when done)
  SkillQuestionGroup? get currentGroup =>
      testOutput != null && currentGroupIndex < testOutput!.groups.length
          ? testOutput!.groups[currentGroupIndex]
          : null;

  /// Currently displayed question
  SkillQuestion? get currentQuestion {
    final g = currentGroup;
    if (g == null) return null;
    if (currentQuestionIndex >= g.questions.length) return null;
    return g.questions[currentQuestionIndex];
  }

  /// Selected answer for current question (null = not answered yet)
  int? get selectedAnswerForCurrent =>
      answers[currentGroupIndex]?[currentQuestionIndex];

  bool get isLastQuestion {
    final g = currentGroup;
    if (g == null) return false;
    final isLastInGroup = currentQuestionIndex == g.questions.length - 1;
    final isLastGroup =
        currentGroupIndex == (testOutput?.groups.length ?? 0) - 1;
    return isLastInGroup && isLastGroup;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skill result model
// ─────────────────────────────────────────────────────────────────────────────

class SkillResult {
  final String skillName;
  final int correct;
  final int total;
  final double rawScore; // 0-1
  final double confidenceScore; // 0-1 (blended)
  final String label; // 'Beginner' / 'Developing' / 'Proficient' / 'Advanced'

  const SkillResult({
    required this.skillName,
    required this.correct,
    required this.total,
    required this.rawScore,
    required this.confidenceScore,
    required this.label,
  });

  static String _label(double score) {
    if (score >= 0.80) return 'Advanced';
    if (score >= 0.60) return 'Proficient';
    if (score >= 0.35) return 'Developing';
    return 'Beginner';
  }

  factory SkillResult.compute({
    required String skillName,
    required int correct,
    required int total,
    required int? selfConfidence, // 1-5
    required double blendRatio, // how much weight to give self-confidence
  }) {
    final rawScore = total == 0 ? 0.5 : correct / total;
    final selfScore = _mapSelfConfidence(selfConfidence);
    final confidenceScore = rawScore * (1 - blendRatio) + selfScore * blendRatio;
    return SkillResult(
      skillName: skillName,
      correct: correct,
      total: total,
      rawScore: rawScore,
      confidenceScore: confidenceScore.clamp(0.0, 1.0),
      label: _label(confidenceScore),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class SkillTestNotifier extends StateNotifier<SkillTestState> {
  SkillTestNotifier() : super(const SkillTestState());

  final _service = SkillTestAiService();
  final _supabase = Supabase.instance.client;

  // ── 1. Generate the test ──────────────────────────────────────────────────

  Future<void> generateTest({
    required List<String> skills,
    required String userRole, // 'Professional' | 'Student' | 'Learner'
    int questionsPerSkill = 4,
  }) async {
    if (skills.isEmpty) {
      state = state.copyWith(
        phase: SkillTestPhase.error,
        error: 'No skills to assess. Please add skills in your profile.',
      );
      return;
    }

    state = state.copyWith(phase: SkillTestPhase.generating, clearError: true);

    final difficulty = _difficultyForRole(userRole);

    try {
      final output = await _service.generateTest(
        skills: skills,
        difficulty: difficulty,
        questionsPerSkill: questionsPerSkill,
      );

      state = state.copyWith(
        phase: SkillTestPhase.inProgress,
        testOutput: output,
        currentGroupIndex: 0,
        currentQuestionIndex: 0,
        answers: {},
        hasAnsweredCurrent: false,
      );
    } catch (e) {
      debugPrint('[SkillTestNotifier] generate error: $e');
      state = state.copyWith(
        phase: SkillTestPhase.error,
        error: 'Could not generate questions. Please try again.\n$e',
      );
    }
  }

  // ── 2. User selects an answer ─────────────────────────────────────────────

  void selectAnswer(int optionIndex) {
    if (state.phase != SkillTestPhase.inProgress) return;
    if (state.hasAnsweredCurrent) return; // prevent re-answering

    final gIdx = state.currentGroupIndex;
    final qIdx = state.currentQuestionIndex;

    final updatedAnswers = Map<int, Map<int, int>>.from(
      state.answers.map((k, v) => MapEntry(k, Map<int, int>.from(v))),
    );
    updatedAnswers[gIdx] ??= {};
    updatedAnswers[gIdx]![qIdx] = optionIndex;

    state = state.copyWith(
      answers: updatedAnswers,
      hasAnsweredCurrent: true,
    );
  }

  // ── 3. Advance to next question ───────────────────────────────────────────

  void nextQuestion() {
    if (state.testOutput == null) return;

    final groups = state.testOutput!.groups;
    final gIdx = state.currentGroupIndex;
    final qIdx = state.currentQuestionIndex;
    final currentGroup = groups[gIdx];

    if (qIdx < currentGroup.questions.length - 1) {
      // Next question in same group
      state = state.copyWith(
        currentQuestionIndex: qIdx + 1,
        hasAnsweredCurrent: false,
      );
    } else if (gIdx < groups.length - 1) {
      // Move to next skill group
      state = state.copyWith(
        currentGroupIndex: gIdx + 1,
        currentQuestionIndex: 0,
        hasAnsweredCurrent: false,
      );
    } else {
      // All done — submit
      _submitResults();
    }
  }

  // ── 4. Score & save to Supabase ───────────────────────────────────────────

  Future<void> _submitResults() async {
    state = state.copyWith(phase: SkillTestPhase.submitting);

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      state = state.copyWith(
        phase: SkillTestPhase.error,
        error: 'Not authenticated',
      );
      return;
    }

    // Fetch onboarding data for self-confidence baseline
    final onboarding = await _fetchOnboarding(userId);
    final skillConfidenceMap = _buildSkillConfidenceMap(onboarding);
    final overallSelfConfidence = onboarding?['confidence_baseline'] as int?;

    // Fetch user role
    final profileRow = await _fetchProfile(userId);
    final userRole = (profileRow?['role'] as String?) ?? 'Learner';
    final difficulty = _difficultyForRole(userRole);

    // Calculate results
    final groups = state.testOutput!.groups;
    final results = <SkillResult>[];

    for (int gi = 0; gi < groups.length; gi++) {
      final group = groups[gi];
      final groupAnswers = state.answers[gi] ?? {};
      int correct = 0;

      for (int qi = 0; qi < group.questions.length; qi++) {
        final selected = groupAnswers[qi];
        if (selected != null &&
            selected == group.questions[qi].correctOptionIndex) {
          correct++;
        }
      }

      // Look up self-declared confidence for this exact skill
      final selfConf =
          skillConfidenceMap[group.skillName.toLowerCase()] ??
          overallSelfConfidence;

      results.add(SkillResult.compute(
        skillName: group.skillName,
        correct: correct,
        total: group.questions.length,
        selfConfidence: selfConf,
        blendRatio: 0.3,
      ));
    }

    // Persist to user_skill_memory
    try {
      for (final result in results) {
        await _upsertSkillMemory(
          userId: userId,
          result: result,
          difficulty: difficulty,
        );
      }

      state = state.copyWith(
        phase: SkillTestPhase.completed,
        results: results,
      );
    } catch (e) {
      debugPrint('[SkillTestNotifier] save error: $e');
      // Still show results even if save fails
      state = state.copyWith(
        phase: SkillTestPhase.completed,
        results: results,
        error: 'Results saved locally but could not sync: $e',
      );
    }
  }

  // ── DB helpers ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> _fetchOnboarding(String userId) async {
    try {
      return await _supabase
          .from('user_onboarding')
          .select('skills, confidence_baseline')
          .eq('user_id', userId)
          .maybeSingle();
    } catch (e) {
      debugPrint('[SkillTestNotifier] fetchOnboarding error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchProfile(String userId) async {
    try {
      return await _supabase
          .from('user_profiles')
          .select('role')
          .eq('user_id', userId)
          .maybeSingle();
    } catch (e) {
      return null;
    }
  }

  /// Builds a lowercase skill_name → confidence (1-5) map from onboarding data.
  Map<String, int> _buildSkillConfidenceMap(
      Map<String, dynamic>? onboarding) {
    if (onboarding == null) return {};
    try {
      final skillsRaw = onboarding['skills'];
      if (skillsRaw == null) return {};
      final skillsList = (skillsRaw is List)
          ? skillsRaw
          : (skillsRaw as Map)['skills'] as List? ?? [];

      final map = <String, int>{};
      for (final s in skillsList) {
        final name = (s['skill'] as String?)?.toLowerCase();
        final conf = (s['confidence'] as num?)?.toInt();
        if (name != null && conf != null) {
          map[name] = conf;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> _upsertSkillMemory({
    required String userId,
    required SkillResult result,
    required String difficulty,
  }) async {
    // Check if a row already exists
    final existing = await _supabase
        .from('user_skill_memory')
        .select('id, practice_count')
        .eq('user_id', userId)
        .eq('skill_name', result.skillName)
        .maybeSingle();

    final evidence = {
      'raw_score': result.rawScore,
      'correct': result.correct,
      'total': result.total,
      'difficulty': difficulty,
      'test_type': 'initial_skill_test',
      'tested_at': DateTime.now().toIso8601String(),
    };

    if (existing == null) {
      await _supabase.from('user_skill_memory').insert({
        'user_id': userId,
        'skill_name': result.skillName,
        'confidence_score': result.confidenceScore,
        'last_practiced_at': DateTime.now().toIso8601String(),
        'practice_count': 1,
        'evidence': evidence,
      });
    } else {
      final prevCount = (existing['practice_count'] as int?) ?? 0;
      await _supabase
          .from('user_skill_memory')
          .update({
            'confidence_score': result.confidenceScore,
            'last_practiced_at': DateTime.now().toIso8601String(),
            'practice_count': prevCount + 1,
            'evidence': evidence,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existing['id']);
    }
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  static String _difficultyForRole(String role) {
    switch (role.toLowerCase()) {
      case 'professional':
        return 'advanced';
      case 'student':
        return 'intermediate';
      default: // Learner
        return 'beginner';
    }
  }

  void reset() {
    state = const SkillTestState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final skillTestProvider =
    StateNotifierProvider<SkillTestNotifier, SkillTestState>(
  (ref) => SkillTestNotifier(),
);