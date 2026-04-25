// =============================================================================
// taiken_ai_provider.dart
//
// Changes from previous version:
//   _normaliseDomain() — rewrote to map AI-generated domain strings to the
//   actual snake_case values used by DomainConstants (e.g. 'technology',
//   'business_finance', 'science_research') instead of the old capitalised
//   list ['Science', 'Business', 'History', 'Technology', 'Arts'] which no
//   longer matches DomainConstants.domains.
//   The function now also tries subdomain values (e.g. 'ai_ml', 'data_science')
//   so the AI can produce specific domain strings that survive round-trips.
//   All other logic is unchanged.
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../Viewmodels/taiken_create_provider.dart';
import '../constants/domain_constants.dart';
import 'taiken_ai_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Input model (from the AI prompt sheet)
// ─────────────────────────────────────────────────────────────────────────────

class TaikenAiInput {
  final String topic;
  final String learningObjective;
  final String keyQuestions;
  final String difficulty;
  final String domain;
  final int stageCount;

  const TaikenAiInput({
    required this.topic,
    required this.learningObjective,
    required this.keyQuestions,
    required this.difficulty,
    required this.domain,
    this.stageCount = 2,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class TaikenAiState {
  final bool isGenerating;
  final String? error;
  final TaikenAiOutput? lastOutput;
  final bool wasApplied;

  const TaikenAiState({
    this.isGenerating = false,
    this.error,
    this.lastOutput,
    this.wasApplied = false,
  });

  TaikenAiState copyWith({
    bool? isGenerating,
    String? error,
    bool clearError = false,
    TaikenAiOutput? lastOutput,
    bool? wasApplied,
  }) {
    return TaikenAiState(
      isGenerating: isGenerating ?? this.isGenerating,
      error:        clearError ? null : (error ?? this.error),
      lastOutput:   lastOutput ?? this.lastOutput,
      wasApplied:   wasApplied ?? this.wasApplied,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class TaikenAiNotifier extends StateNotifier<TaikenAiState> {
  TaikenAiNotifier(this._ref) : super(const TaikenAiState());

  final Ref _ref;
  final _service = TaikenAiService();
  final _uuid    = const Uuid();

  /// Generate a Taiken via Gemini and then push it into the create provider.
  Future<void> generate(TaikenAiInput input) async {
    state = state.copyWith(isGenerating: true, clearError: true, wasApplied: false);
    try {
      final output = await _service.generateTaiken(
        topic:             input.topic,
        learningObjective: input.learningObjective,
        keyQuestions:      input.keyQuestions,
        difficulty:        input.difficulty,
        domain:            input.domain,
        stageCount:        input.stageCount,
      );

      state = state.copyWith(
        isGenerating: false,
        lastOutput:   output,
      );

      // Auto-apply to the create provider
      _applyToCreateProvider(output);
      state = state.copyWith(wasApplied: true);
    } catch (e) {
      debugPrint('[TaikenAiNotifier] generation error: $e');
      state = state.copyWith(
        isGenerating: false,
        error: 'AI generation failed. Please try again.\n$e',
      );
    }
  }

  void clearError() => state = state.copyWith(clearError: true);

  // ── Map AI output → TaikenCreateState ─────────────────────────────────────

  void _applyToCreateProvider(TaikenAiOutput output) {
    final notifier = _ref.read(taikenCreateProvider.notifier);

    // ── Basic fields ─────────────────────────────────────────────────────────
    notifier.updateTitle(output.title);
    notifier.updateDescription(output.description);
    notifier.updateDomain(_normaliseDomain(output.domain));
    notifier.updateDifficulty(output.difficulty);
    notifier.updateIntroScript(output.introScript);
    notifier.updateOutroSuccessScript(output.outroSuccessScript);
    notifier.updateOutroFailureScript(output.outroFailureScript);

    // ── Characters ───────────────────────────────────────────────────────────
    final createState = _ref.read(taikenCreateProvider);

    // Remove all current characters first.
    // FIX #9 — iterate by re-reading length each time so we never hold
    // a stale count while removeCharacter mutates the underlying list.
    final currentCharCount = _ref.read(taikenCreateProvider).characters.length;
    for (int i = currentCharCount - 1; i >= 0; i--) {
      notifier.removeCharacter(0); // always remove index 0 after the first is gone
    }

    // Add AI-generated characters.
    for (final aiChar in output.characters) {
      notifier.addCharacter();
    }

    // Update each character's details.
    final afterAdd = _ref.read(taikenCreateProvider);
    for (int i = 0;
    i < output.characters.length && i < afterAdd.characters.length;
    i++) {
      final aiChar  = output.characters[i];
      final current = afterAdd.characters[i];
      notifier.updateCharacter(
        i,
        CharacterData(
          tempId:               current.tempId,
          characterName:        aiChar.name,
          characterDescription: aiChar.description,
          portraitSide:         aiChar.side,
          isPlayer:             aiChar.isPlayer,
          assetKey:             aiChar.assetKey,
        ),
      );
    }

    // ── Stages ───────────────────────────────────────────────────────────────
    notifier.setTotalStages(output.stages.length);

    // Build a name → tempId map for character assignment in dialogues.
    final stateAfterChars = _ref.read(taikenCreateProvider);
    final charNameToTempId = <String, String>{};
    for (int i = 0; i < stateAfterChars.characters.length; i++) {
      charNameToTempId[stateAfterChars.characters[i].characterName] =
          stateAfterChars.characters[i].tempId;
    }

    final stateAfterStages = _ref.read(taikenCreateProvider);

    for (int si = 0; si < output.stages.length; si++) {
      final aiStage = output.stages[si];
      if (si >= stateAfterStages.stages.length) break;
      final stageData = stateAfterStages.stages[si];

      // Update stage title / mood / type.
      notifier.updateStage(
        si,
        stageData.copyWith(
          stageTitle:    aiStage.title,
          mood:          aiStage.mood,
          stageType:     aiStage.stageType,
          backgroundKey: aiStage.backgroundKey,
          musicCue:      aiStage.musicCue,
        ),
      );

      // Add dialogues (stage was freshly created — no existing dialogues).
      for (final aiDlg in aiStage.dialogues) {
        notifier.addDialogue(si);
        final freshState  = _ref.read(taikenCreateProvider);
        final dialogues   = freshState.stages[si].dialogues;
        final newDlgIndex = dialogues.length - 1;
        final charTempId  = charNameToTempId[aiDlg.characterName];

        notifier.updateDialogue(
          si,
          newDlgIndex,
          DialogueData(
            tempId:          dialogues[newDlgIndex].tempId,
            characterTempId: charTempId,
            dialogueText:    aiDlg.text,
            emotion:         aiDlg.emotion,
            typewriterSpeed: aiDlg.typewriterSpeed,
            pauseAfterMs:    aiDlg.pauseAfterMs,
          ),
        );
      }

      // Add questions.
      for (final aiQ in aiStage.questions) {
        notifier.addQuestion(si);
        final freshState = _ref.read(taikenCreateProvider);
        final questions  = freshState.stages[si].questions;
        final newQIndex  = questions.length - 1;

        notifier.updateQuestion(
          si,
          newQIndex,
          QuestionData(
            tempId:               questions[newQIndex].tempId,
            questionText:         aiQ.questionText,
            questionType:         aiQ.questionType,
            options:              aiQ.options,
            correctOptionIndex:   aiQ.correctOptionIndex,
            explanation:          aiQ.explanation,
            hasLearningGate:      aiQ.hasLearningGate,
            gateContentDomain:    aiQ.gateContentDomain,
            gateSkipDelaySeconds: 5,
          ),
        );
      }
    }
  }

  // ── Domain normalisation ───────────────────────────────────────────────────
  //
  // Maps whatever free-text domain string the AI returns to a valid
  // DomainConstants value (top-level or subdomain).
  //
  // Strategy:
  //   1. Exact match against every domain / subdomain value (fastest path for
  //      well-behaved AI output).
  //   2. Substring match against domain labels (catches "Technology" → 'technology',
  //      "Business & Finance" → 'business_finance', etc.).
  //   3. Keyword heuristics as a last resort.
  //   4. Default to 'technology' (first domain in the list) if nothing matches.

  String _normaliseDomain(String raw) {
    final lower = raw.toLowerCase().trim();

    // 1. Exact value match — top-level domains
    for (final d in DomainConstants.domains) {
      if (lower == d['value']!.toLowerCase()) return d['value']!;
    }

    // 1b. Exact value match — subdomains
    for (final subs in DomainConstants.subdomains.values) {
      for (final s in subs) {
        if (lower == s['value']!.toLowerCase()) return s['value']!;
      }
    }

    // 2. Label substring match — top-level domains
    //    e.g. AI returns "Technology" or "Business & Finance"
    for (final d in DomainConstants.domains) {
      if (lower.contains(d['label']!.toLowerCase()) ||
          d['label']!.toLowerCase().contains(lower)) {
        return d['value']!;
      }
    }

    // 2b. Label substring match — subdomains
    for (final subs in DomainConstants.subdomains.values) {
      for (final s in subs) {
        if (lower.contains(s['label']!.toLowerCase()) ||
            s['label']!.toLowerCase().contains(lower)) {
          return s['value']!;
        }
      }
    }

    // 3. Keyword heuristics
    if (_any(lower, ['tech', 'software', 'code', 'program', 'web', 'app',
      'mobile', 'ai', 'ml', 'data', 'cloud', 'cyber',
      'blockchain', 'game', 'devops', 'cs', 'computing'])) {
      return 'technology';
    }
    if (_any(lower, ['design', 'ui', 'ux', 'graphic', '3d', 'anim',
      'video', 'motion', 'illustrat', 'creativ', 'art'])) {
      return 'design_creativity';
    }
    if (_any(lower, ['business', 'finance', 'market', 'sales', 'invest',
      'stock', 'entrepreneur', 'product', 'econ', 'biz'])) {
      return 'business_finance';
    }
    if (_any(lower, ['science', 'physics', 'chem', 'bio', 'astro',
      'environ', 'research', 'lab'])) {
      return 'science_research';
    }
    if (_any(lower, ['engineer', 'mechanic', 'electric', 'civil',
      'robot', 'iot'])) {
      return 'engineering';
    }
    if (_any(lower, ['language', 'english', 'spanish', 'french',
      'japanese', 'communicat', 'speak', 'writ'])) {
      return 'languages_communication';
    }
    if (_any(lower, ['educat', 'learn', 'study', 'memory', 'note',
      'critical think'])) {
      return 'education_learning';
    }
    if (_any(lower, ['career', 'interview', 'resume', 'cv', 'portfolio',
      'network', 'job', 'work'])) {
      return 'career_growth';
    }
    if (_any(lower, ['health', 'psych', 'mental', 'productiv', 'focus',
      'wellbeing', 'wellness'])) {
      return 'health_psychology';
    }
    if (_any(lower, ['art', 'culture', 'history', 'philosoph', 'music',
      'photo'])) {
      return 'arts_culture';
    }

    // 4. Default
    return DomainConstants.domains.first['value']!; // 'technology'
  }

  /// Returns true if [text] contains any of the [keywords].
  bool _any(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final taikenAiProvider =
StateNotifierProvider<TaikenAiNotifier, TaikenAiState>(
        (ref) => TaikenAiNotifier(ref));