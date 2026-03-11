// =============================================================================
// taiken.dart  — PHASE A REWRITE
//
// Changes from previous version:
//   • Taiken           — added seriesId, episodeNumber, domainUnlockRequirement
//   • TaikenStage      — added backgroundImageUrl, mood, musicCue, stageType
//   • TaikenCharacter  — added portraitUrl, portraitUrlTalking, portraitSide,
//                        isPlayer
//   • TaikenDialogue   — added emotion, typewriterSpeed, pauseAfterMs
//   • TaikenQuestion   — added hasLearningGate, gateContentDomain,
//                        gateSkipDelaySeconds
//   • TaikenProgress   — added currentPhase, currentQuestionIndex,
//                        gatesStudied, gatesSkipped
//   • TaikenBadge      — NEW model
//   • TaikenSeries     — NEW model
//   • TaikenGateInteraction — NEW model
//   All fromJson / copyWith / toJson kept backward-compatible with DB defaults.
// =============================================================================

// ─────────────────────────────────────────────────────────────────────────────
// Enums  (replaces raw strings everywhere in the codebase)
// ─────────────────────────────────────────────────────────────────────────────

enum TaikenPhase {
  intro,
  dialogue,
  gateInterstitial,
  question,
  outro;

  static TaikenPhase fromString(String? value) {
    switch (value) {
      case 'dialogue':       return TaikenPhase.dialogue;
      case 'gateInterstitial': return TaikenPhase.gateInterstitial;
      case 'question':       return TaikenPhase.question;
      case 'outro':          return TaikenPhase.outro;
      default:               return TaikenPhase.intro;
    }
  }

  String toDbString() {
    switch (this) {
      case TaikenPhase.intro:            return 'intro';
      case TaikenPhase.dialogue:         return 'dialogue';
      case TaikenPhase.gateInterstitial: return 'gateInterstitial';
      case TaikenPhase.question:         return 'question';
      case TaikenPhase.outro:            return 'outro';
    }
  }
}

enum StageMood {
  neutral, tense, happy, dramatic, mysterious, urgent;

  static StageMood fromString(String? value) {
    return StageMood.values.firstWhere(
          (e) => e.name == value,
      orElse: () => StageMood.neutral,
    );
  }
}

enum DialogueEmotion {
  neutral, happy, angry, surprised, sad, thinking, determined;

  static DialogueEmotion fromString(String? value) {
    return DialogueEmotion.values.firstWhere(
          (e) => e.name == value,
      orElse: () => DialogueEmotion.neutral,
    );
  }
}

enum TypewriterSpeed {
  slow, normal, fast, instant;

  static TypewriterSpeed fromString(String? value) {
    return TypewriterSpeed.values.firstWhere(
          (e) => e.name == value,
      orElse: () => TypewriterSpeed.normal,
    );
  }

  /// Characters per second for typewriter animation.
  int get charsPerSecond {
    switch (this) {
      case TypewriterSpeed.slow:    return 20;
      case TypewriterSpeed.normal:  return 40;
      case TypewriterSpeed.fast:    return 80;
      case TypewriterSpeed.instant: return 99999;
    }
  }
}

enum PortraitSide {
  left, right;

  static PortraitSide fromString(String? value) =>
      value == 'right' ? PortraitSide.right : PortraitSide.left;
}

enum StageType {
  story,     // dialogues only
  challenge, // questions only
  mixed;     // dialogues → then questions

  static StageType fromString(String? value) {
    return StageType.values.firstWhere(
          (e) => e.name == value,
      orElse: () => StageType.mixed,
    );
  }
}

enum GateAction {
  studied,
  skipped,
  skippedAfterDelay;

  String toDbString() {
    switch (this) {
      case GateAction.studied:           return 'studied';
      case GateAction.skipped:           return 'skipped';
      case GateAction.skippedAfterDelay: return 'skipped_after_delay';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Taiken  (top-level entity)
// ─────────────────────────────────────────────────────────────────────────────

class Taiken {
  final String taikenId;
  final String creatorId;
  final String title;
  final String description;
  final String domain;
  final String difficulty;
  final String introScript;
  final String outroSuccessScript;
  final String outroFailureScript;
  final String? thumbnailUrl;
  final int totalStages;
  final int totalQuestions;
  final int passThreshold;
  final int playCount;
  final double averageRating;
  final int ratingCount;
  final bool isPublished;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── NEW Phase A fields ────────────────────────────────────────────────────
  /// UUID of the series this Taiken belongs to. Null = standalone.
  final String? seriesId;

  /// Episode number within the series (1-based). Null = standalone.
  final int? episodeNumber;

  /// JSON blob: {"domain": "data_analysis", "min_taikens_passed": 2}
  /// Null = no domain gate, always accessible.
  final Map<String, dynamic>? domainUnlockRequirement;

  const Taiken({
    required this.taikenId,
    required this.creatorId,
    required this.title,
    required this.description,
    required this.domain,
    required this.difficulty,
    required this.introScript,
    required this.outroSuccessScript,
    required this.outroFailureScript,
    this.thumbnailUrl,
    required this.totalStages,
    required this.totalQuestions,
    required this.passThreshold,
    required this.playCount,
    required this.averageRating,
    required this.ratingCount,
    required this.isPublished,
    required this.createdAt,
    required this.updatedAt,
    this.seriesId,
    this.episodeNumber,
    this.domainUnlockRequirement,
  });

  factory Taiken.fromJson(Map<String, dynamic> json) => Taiken(
    taikenId:            json['taiken_id'] as String,
    creatorId:           json['creator_id'] as String,
    title:               json['title'] as String,
    description:         json['description'] as String? ?? '',
    domain:              json['domain'] as String,
    difficulty:          json['difficulty'] as String,
    introScript:         json['intro_script'] as String,
    outroSuccessScript:  json['outro_success_script'] as String,
    outroFailureScript:  json['outro_failure_script'] as String,
    thumbnailUrl:        json['thumbnail_url'] as String?,
    totalStages:         (json['total_stages'] as num).toInt(),
    totalQuestions:      (json['total_questions'] as num? ?? 0).toInt(),
    passThreshold:       (json['pass_threshold'] as num? ?? 50).toInt(),
    playCount:           (json['play_count'] as num? ?? 0).toInt(),
    averageRating:       (json['average_rating'] as num? ?? 0.0).toDouble(),
    ratingCount:         (json['rating_count'] as num? ?? 0).toInt(),
    isPublished:         json['is_published'] as bool? ?? false,
    createdAt:           DateTime.parse(json['created_at'] as String),
    updatedAt:           DateTime.parse(json['updated_at'] as String),
    seriesId:            json['series_id'] as String?,
    episodeNumber:       (json['episode_number'] as num?)?.toInt(),
    domainUnlockRequirement:
    json['domain_unlock_requirement'] as Map<String, dynamic>?,
  );

  Taiken copyWith({
    String? title,
    String? description,
    String? domain,
    String? difficulty,
    String? introScript,
    String? outroSuccessScript,
    String? outroFailureScript,
    String? thumbnailUrl,
    int? totalStages,
    int? totalQuestions,
    int? passThreshold,
    int? playCount,
    double? averageRating,
    int? ratingCount,
    bool? isPublished,
    String? seriesId,
    int? episodeNumber,
    Map<String, dynamic>? domainUnlockRequirement,
  }) =>
      Taiken(
        taikenId:               taikenId,
        creatorId:              creatorId,
        title:                  title               ?? this.title,
        description:            description         ?? this.description,
        domain:                 domain              ?? this.domain,
        difficulty:             difficulty          ?? this.difficulty,
        introScript:            introScript         ?? this.introScript,
        outroSuccessScript:     outroSuccessScript  ?? this.outroSuccessScript,
        outroFailureScript:     outroFailureScript  ?? this.outroFailureScript,
        thumbnailUrl:           thumbnailUrl        ?? this.thumbnailUrl,
        totalStages:            totalStages         ?? this.totalStages,
        totalQuestions:         totalQuestions      ?? this.totalQuestions,
        passThreshold:          passThreshold       ?? this.passThreshold,
        playCount:              playCount           ?? this.playCount,
        averageRating:          averageRating       ?? this.averageRating,
        ratingCount:            ratingCount         ?? this.ratingCount,
        isPublished:            isPublished         ?? this.isPublished,
        createdAt:              createdAt,
        updatedAt:              updatedAt,
        seriesId:               seriesId            ?? this.seriesId,
        episodeNumber:          episodeNumber       ?? this.episodeNumber,
        domainUnlockRequirement: domainUnlockRequirement ?? this.domainUnlockRequirement,
      );

  /// True when this Taiken is part of a series.
  bool get isPartOfSeries => seriesId != null;

  /// True if this Taiken has a domain-based prerequisite.
  bool get hasDomainGate => domainUnlockRequirement != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenSeries  — NEW
// ─────────────────────────────────────────────────────────────────────────────

class TaikenSeries {
  final String seriesId;
  final String creatorId;
  final String title;
  final String description;
  final String domain;
  final String? thumbnailUrl;
  final int totalEpisodes;
  final bool isPublished;
  final DateTime createdAt;

  const TaikenSeries({
    required this.seriesId,
    required this.creatorId,
    required this.title,
    required this.description,
    required this.domain,
    this.thumbnailUrl,
    required this.totalEpisodes,
    required this.isPublished,
    required this.createdAt,
  });

  factory TaikenSeries.fromJson(Map<String, dynamic> json) => TaikenSeries(
    seriesId:      json['series_id'] as String,
    creatorId:     json['creator_id'] as String,
    title:         json['title'] as String,
    description:   json['description'] as String? ?? '',
    domain:        json['domain'] as String,
    thumbnailUrl:  json['thumbnail_url'] as String?,
    totalEpisodes: (json['total_episodes'] as num? ?? 1).toInt(),
    isPublished:   json['is_published'] as bool? ?? false,
    createdAt:     DateTime.parse(json['created_at'] as String),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenStage
// ─────────────────────────────────────────────────────────────────────────────

class TaikenStage {
  final String stageId;
  final String taikenId;
  final int stageOrder;
  final String stageTitle;

  // Legacy field — kept for backward compat, prefer backgroundImageUrl.
  final String? sceneImageUrl;

  // ── NEW Phase A fields ────────────────────────────────────────────────────
  final String? backgroundImageUrl;
  final StageMood mood;
  final String? musicCue;
  final StageType stageType;

  final DateTime createdAt;

  const TaikenStage({
    required this.stageId,
    required this.taikenId,
    required this.stageOrder,
    required this.stageTitle,
    this.sceneImageUrl,
    this.backgroundImageUrl,
    this.mood = StageMood.neutral,
    this.musicCue,
    this.stageType = StageType.mixed,
    required this.createdAt,
  });

  factory TaikenStage.fromJson(Map<String, dynamic> json) => TaikenStage(
    stageId:            json['stage_id'] as String,
    taikenId:           json['taiken_id'] as String,
    stageOrder:         (json['stage_order'] as num).toInt(),
    stageTitle:         json['stage_title'] as String,
    sceneImageUrl:      json['scene_image_url'] as String?,
    backgroundImageUrl: json['background_image_url'] as String?,
    mood:               StageMood.fromString(json['mood'] as String?),
    musicCue:           json['music_cue'] as String?,
    stageType:          StageType.fromString(json['stage_type'] as String?),
    createdAt:          DateTime.parse(json['created_at'] as String),
  );

  /// Returns the best available background image URL.
  /// Prefers the new backgroundImageUrl, falls back to legacy sceneImageUrl.
  String? get effectiveBackgroundUrl => backgroundImageUrl ?? sceneImageUrl;
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenCharacter
// ─────────────────────────────────────────────────────────────────────────────

class TaikenCharacter {
  final String characterId;
  final String taikenId;
  final String characterName;

  // Legacy avatar image — kept for backward compat.
  final String? characterImageUrl;
  final String? characterDescription;
  final int displayOrder;

  // ── NEW Phase A fields ────────────────────────────────────────────────────
  /// Full bust/half-body portrait shown during dialogue.
  final String? portraitUrl;

  /// Slightly different expression used when this character is actively speaking.
  final String? portraitUrlTalking;

  /// Which side of the screen this character stands on.
  final PortraitSide portraitSide;

  /// True = this is the "You" / player character.
  final bool isPlayer;

  final DateTime createdAt;

  const TaikenCharacter({
    required this.characterId,
    required this.taikenId,
    required this.characterName,
    this.characterImageUrl,
    this.characterDescription,
    required this.displayOrder,
    this.portraitUrl,
    this.portraitUrlTalking,
    this.portraitSide = PortraitSide.left,
    this.isPlayer = false,
    required this.createdAt,
  });

  factory TaikenCharacter.fromJson(Map<String, dynamic> json) =>
      TaikenCharacter(
        characterId:        json['character_id'] as String,
        taikenId:           json['taiken_id'] as String,
        characterName:      json['character_name'] as String,
        characterImageUrl:  json['character_image_url'] as String?,
        characterDescription: json['character_description'] as String?,
        displayOrder:       (json['display_order'] as num).toInt(),
        portraitUrl:        json['portrait_url'] as String?,
        portraitUrlTalking: json['portrait_url_talking'] as String?,
        portraitSide:       PortraitSide.fromString(
            json['portrait_side'] as String?),
        isPlayer:           json['is_player'] as bool? ?? false,
        createdAt:          DateTime.parse(json['created_at'] as String),
      );

  /// Best available portrait URL for this character (prefers portrait over legacy avatar).
  String? get effectivePortraitUrl => portraitUrl ?? characterImageUrl;

  /// Portrait URL to show when this character is actively speaking.
  String? get effectiveTalkingPortraitUrl =>
      portraitUrlTalking ?? portraitUrl ?? characterImageUrl;
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenDialogue
// ─────────────────────────────────────────────────────────────────────────────

class TaikenDialogue {
  final String dialogueId;
  final String stageId;
  final String? characterId;
  final String dialogueText;
  final int dialogueOrder;

  // ── NEW Phase A fields ────────────────────────────────────────────────────
  final DialogueEmotion emotion;
  final TypewriterSpeed typewriterSpeed;

  /// Milliseconds to wait after this bubble is fully shown before allowing
  /// the next tap. Used for dramatic pauses (e.g. a revelation moment).
  final int pauseAfterMs;

  final DateTime createdAt;

  const TaikenDialogue({
    required this.dialogueId,
    required this.stageId,
    this.characterId,
    required this.dialogueText,
    required this.dialogueOrder,
    this.emotion = DialogueEmotion.neutral,
    this.typewriterSpeed = TypewriterSpeed.normal,
    this.pauseAfterMs = 0,
    required this.createdAt,
  });

  factory TaikenDialogue.fromJson(Map<String, dynamic> json) => TaikenDialogue(
    dialogueId:      json['dialogue_id'] as String,
    stageId:         json['stage_id'] as String,
    characterId:     json['character_id'] as String?,
    dialogueText:    json['dialogue_text'] as String,
    dialogueOrder:   (json['dialogue_order'] as num).toInt(),
    emotion:         DialogueEmotion.fromString(json['emotion'] as String?),
    typewriterSpeed: TypewriterSpeed.fromString(
        json['typewriter_speed'] as String?),
    pauseAfterMs:    (json['pause_after_ms'] as num? ?? 0).toInt(),
    createdAt:       DateTime.parse(json['created_at'] as String),
  );

  /// Whether this dialogue line belongs to the narrator (no character assigned).
  bool get isNarrator => characterId == null || characterId!.isEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenQuestion
// ─────────────────────────────────────────────────────────────────────────────

class TaikenQuestion {
  final String questionId;
  final String stageId;
  final String questionText;
  final String questionType;
  final List<String> options;
  final int correctOptionIndex;
  final String? explanation;
  final int questionOrder;

  // ── NEW Phase A fields ────────────────────────────────────────────────────
  /// Whether this question has a learning gate interstitial before it.
  final bool hasLearningGate;

  /// Domain used to pull relevant Bytes/Posts for the gate.
  /// Falls back to the Taiken's domain if null.
  final String? gateContentDomain;

  /// Seconds before the "I already know this" skip button becomes active.
  final int gateSkipDelaySeconds;

  final DateTime createdAt;

  const TaikenQuestion({
    required this.questionId,
    required this.stageId,
    required this.questionText,
    required this.questionType,
    required this.options,
    required this.correctOptionIndex,
    this.explanation,
    required this.questionOrder,
    this.hasLearningGate = false,
    this.gateContentDomain,
    this.gateSkipDelaySeconds = 5,
    required this.createdAt,
  });

  factory TaikenQuestion.fromJson(Map<String, dynamic> json) => TaikenQuestion(
    questionId:           json['question_id'] as String,
    stageId:              json['stage_id'] as String,
    questionText:         json['question_text'] as String,
    questionType:         json['question_type'] as String,
    options:              (json['options'] as List).cast<String>(),
    correctOptionIndex:   (json['correct_option_index'] as num).toInt(),
    explanation:          json['explanation'] as String?,
    questionOrder:        (json['question_order'] as num).toInt(),
    hasLearningGate:      json['has_learning_gate'] as bool? ?? false,
    gateContentDomain:    json['gate_content_domain'] as String?,
    gateSkipDelaySeconds: (json['gate_skip_delay_seconds'] as num? ?? 5)
        .toInt(),
    createdAt:            DateTime.parse(json['created_at'] as String),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenProgress
// ─────────────────────────────────────────────────────────────────────────────

class TaikenProgress {
  final String progressId;
  final String userId;
  final String taikenId;
  final int currentStageOrder;
  final int questionsAnswered;
  final int correctAnswers;
  final int wrongAnswers;
  final String status; // 'in_progress' | 'completed' | 'failed'
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // ── NEW Phase A fields ────────────────────────────────────────────────────
  /// Current phase within the active stage.
  final TaikenPhase currentPhase;

  /// 0-based index of the current question within the current stage.
  final int currentQuestionIndex;

  /// How many learning gates the user studied before answering.
  final int gatesStudied;

  /// How many learning gates the user skipped.
  final int gatesSkipped;

  const TaikenProgress({
    required this.progressId,
    required this.userId,
    required this.taikenId,
    required this.currentStageOrder,
    required this.questionsAnswered,
    required this.correctAnswers,
    required this.wrongAnswers,
    required this.status,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.currentPhase = TaikenPhase.dialogue,
    this.currentQuestionIndex = 0,
    this.gatesStudied = 0,
    this.gatesSkipped = 0,
  });

  factory TaikenProgress.fromJson(Map<String, dynamic> json) => TaikenProgress(
    progressId:           json['progress_id'] as String,
    userId:               json['user_id'] as String,
    taikenId:             json['taiken_id'] as String,
    currentStageOrder:    (json['current_stage_order'] as num).toInt(),
    questionsAnswered:    (json['questions_answered'] as num? ?? 0).toInt(),
    correctAnswers:       (json['correct_answers'] as num? ?? 0).toInt(),
    wrongAnswers:         (json['wrong_answers'] as num? ?? 0).toInt(),
    status:               json['status'] as String? ?? 'in_progress',
    completedAt:          json['completed_at'] != null
        ? DateTime.parse(json['completed_at'] as String)
        : null,
    createdAt:            DateTime.parse(json['created_at'] as String),
    updatedAt:            DateTime.parse(json['updated_at'] as String),
    currentPhase:         TaikenPhase.fromString(
        json['current_phase'] as String?),
    currentQuestionIndex: (json['current_question_index'] as num? ?? 0)
        .toInt(),
    gatesStudied:         (json['gates_studied'] as num? ?? 0).toInt(),
    gatesSkipped:         (json['gates_skipped'] as num? ?? 0).toInt(),
  );

  TaikenProgress copyWith({
    int? currentStageOrder,
    int? questionsAnswered,
    int? correctAnswers,
    int? wrongAnswers,
    String? status,
    DateTime? completedAt,
    TaikenPhase? currentPhase,
    int? currentQuestionIndex,
    int? gatesStudied,
    int? gatesSkipped,
  }) =>
      TaikenProgress(
        progressId:           progressId,
        userId:               userId,
        taikenId:             taikenId,
        currentStageOrder:    currentStageOrder    ?? this.currentStageOrder,
        questionsAnswered:    questionsAnswered    ?? this.questionsAnswered,
        correctAnswers:       correctAnswers       ?? this.correctAnswers,
        wrongAnswers:         wrongAnswers         ?? this.wrongAnswers,
        status:               status              ?? this.status,
        completedAt:          completedAt         ?? this.completedAt,
        createdAt:            createdAt,
        updatedAt:            updatedAt,
        currentPhase:         currentPhase        ?? this.currentPhase,
        currentQuestionIndex: currentQuestionIndex ?? this.currentQuestionIndex,
        gatesStudied:         gatesStudied        ?? this.gatesStudied,
        gatesSkipped:         gatesSkipped        ?? this.gatesSkipped,
      );

  double get accuracyPercentage {
    if (questionsAnswered == 0) return 0.0;
    return (correctAnswers / questionsAnswered) * 100;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenBadge  — NEW
// ─────────────────────────────────────────────────────────────────────────────

class TaikenBadge {
  final String badgeId;
  final String domain;
  final String difficulty;
  final String badgeName;
  final String badgeIconUrl;
  final String badgeColorHex;
  final String? description;

  const TaikenBadge({
    required this.badgeId,
    required this.domain,
    required this.difficulty,
    required this.badgeName,
    required this.badgeIconUrl,
    required this.badgeColorHex,
    this.description,
  });

  factory TaikenBadge.fromJson(Map<String, dynamic> json) => TaikenBadge(
    badgeId:        json['badge_id'] as String,
    domain:         json['domain'] as String,
    difficulty:     json['difficulty'] as String,
    badgeName:      json['badge_name'] as String,
    badgeIconUrl:   json['badge_icon_url'] as String,
    badgeColorHex:  json['badge_color_hex'] as String? ?? '#6C63FF',
    description:    json['description'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// UserTaikenBadge  — NEW  (awarded badge instance)
// ─────────────────────────────────────────────────────────────────────────────

class UserTaikenBadge {
  final String id;
  final String userId;
  final String badgeId;
  final String taikenId;
  final DateTime awardedAt;
  final double scorePercentage;

  /// The full badge details, joined after fetch.
  final TaikenBadge? badge;

  const UserTaikenBadge({
    required this.id,
    required this.userId,
    required this.badgeId,
    required this.taikenId,
    required this.awardedAt,
    required this.scorePercentage,
    this.badge,
  });

  factory UserTaikenBadge.fromJson(Map<String, dynamic> json) =>
      UserTaikenBadge(
        id:              json['id'] as String,
        userId:          json['user_id'] as String,
        badgeId:         json['badge_id'] as String,
        taikenId:        json['taiken_id'] as String,
        awardedAt:       DateTime.parse(json['awarded_at'] as String),
        scorePercentage: (json['score_percentage'] as num).toDouble(),
        badge: json['taiken_badges'] != null
            ? TaikenBadge.fromJson(
            json['taiken_badges'] as Map<String, dynamic>)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// TaikenGateInteraction  — NEW
// ─────────────────────────────────────────────────────────────────────────────

class TaikenGateInteraction {
  final String id;
  final String userId;
  final String questionId;
  final String taikenId;
  final GateAction action;
  final bool? thenAnsweredCorrectly;
  final DateTime createdAt;

  const TaikenGateInteraction({
    required this.id,
    required this.userId,
    required this.questionId,
    required this.taikenId,
    required this.action,
    this.thenAnsweredCorrectly,
    required this.createdAt,
  });

  factory TaikenGateInteraction.fromJson(Map<String, dynamic> json) =>
      TaikenGateInteraction(
        id:                    json['id'] as String,
        userId:                json['user_id'] as String,
        questionId:            json['question_id'] as String,
        taikenId:              json['taiken_id'] as String,
        action:                _parseAction(json['action'] as String),
        thenAnsweredCorrectly: json['then_answered_correctly'] as bool?,
        createdAt:             DateTime.parse(json['created_at'] as String),
      );

  static GateAction _parseAction(String value) {
    switch (value) {
      case 'studied':             return GateAction.studied;
      case 'skipped_after_delay': return GateAction.skippedAfterDelay;
      default:                    return GateAction.skipped;
    }
  }
}



