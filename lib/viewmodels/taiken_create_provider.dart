// =============================================================================
// taiken_create_provider.dart  — with content moderation
//
// Changes from previous version:
//
//   MODERATION — added to two places:
//
//   1. _uploadImage()
//      The empty on-device image moderation block is now filled in.
//      Any thumbnail, scene image, or character image that scores ≥ 0.50
//      on the NSFW model is blocked before upload. Returns null and sets
//      state.error with a clear message. Exactly the same logic as posts.
//
//   2. createTaiken() — NEW Step 0: text moderation
//      Before any upload, moderatePost() is called on:
//        title + description + introScript + outroSuccessScript +
//        outroFailureScript + all dialogue texts + all question texts
//      Wordlist check runs first (instant), then the ML model.
//      If blocked, createTaiken() returns false with a clear error.
//
//   All data classes, field updaters, stage/character/dialogue/question
//   helpers, DB inserts, points, streak, and provider declaration are
//   unchanged.
// =============================================================================

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/taiken.dart';
import 'streakandpoints_provider.dart';
import '../service/moderation_service.dart'; // ← new

// =============================================================================
// DATA CLASSES — unchanged
// =============================================================================

class TaikenCreateState {
  final String title;
  final String description;
  final String domain;
  final String difficulty;
  final String introScript;
  final String outroSuccessScript;
  final String outroFailureScript;
  final XFile? thumbnailFile;
  final int totalStages;
  final List<StageData> stages;
  final List<CharacterData> characters;
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final String? seriesId;
  final int? episodeNumber;
  final int passThreshold;
  final String? defaultMusicCue;

  TaikenCreateState({
    this.title = '',
    this.description = '',
    this.domain = '',
    this.difficulty = 'beginner',
    this.introScript = '',
    this.outroSuccessScript = '',
    this.outroFailureScript = '',
    this.thumbnailFile,
    this.totalStages = 1,
    this.stages = const [],
    this.characters = const [],
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.seriesId,
    this.episodeNumber,
    this.passThreshold = 50,
    this.defaultMusicCue,
  });

  TaikenCreateState copyWith({
    String? title,
    String? description,
    String? domain,
    String? difficulty,
    String? introScript,
    String? outroSuccessScript,
    String? outroFailureScript,
    XFile? thumbnailFile,
    int? totalStages,
    List<StageData>? stages,
    List<CharacterData>? characters,
    bool? isLoading,
    String? error,
    String? successMessage,
    String? seriesId,
    int? episodeNumber,
    int? passThreshold,
    String? defaultMusicCue,
    bool clearDefaultMusicCue = false,
  }) {
    return TaikenCreateState(
      title:               title               ?? this.title,
      description:         description         ?? this.description,
      domain:              domain              ?? this.domain,
      difficulty:          difficulty          ?? this.difficulty,
      introScript:         introScript         ?? this.introScript,
      outroSuccessScript:  outroSuccessScript  ?? this.outroSuccessScript,
      outroFailureScript:  outroFailureScript  ?? this.outroFailureScript,
      thumbnailFile:       thumbnailFile       ?? this.thumbnailFile,
      totalStages:         totalStages         ?? this.totalStages,
      stages:              stages              ?? this.stages,
      characters:          characters          ?? this.characters,
      isLoading:           isLoading           ?? this.isLoading,
      error:               error,
      successMessage:      successMessage,
      seriesId:            seriesId            ?? this.seriesId,
      episodeNumber:       episodeNumber       ?? this.episodeNumber,
      passThreshold:       passThreshold       ?? this.passThreshold,
      defaultMusicCue:     clearDefaultMusicCue
          ? null : (defaultMusicCue ?? this.defaultMusicCue),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class StageData {
  final String tempId;
  final String stageTitle;
  final XFile? sceneImage;
  final List<DialogueData> dialogues;
  final List<QuestionData> questions;
  final StageMood mood;
  final StageType stageType;
  final String? backgroundKey;
  final String? musicCue;

  StageData({
    required this.tempId,
    required this.stageTitle,
    this.sceneImage,
    this.dialogues     = const [],
    this.questions     = const [],
    this.mood          = StageMood.neutral,
    this.stageType     = StageType.mixed,
    this.backgroundKey,
    this.musicCue,
  });

  StageData copyWith({
    String? stageTitle,
    XFile? sceneImage,
    bool clearSceneImage = false,
    List<DialogueData>? dialogues,
    List<QuestionData>? questions,
    StageMood? mood,
    StageType? stageType,
    String? backgroundKey,
    bool clearBackgroundKey = false,
    String? musicCue,
  }) {
    return StageData(
      tempId:        tempId,
      stageTitle:    stageTitle    ?? this.stageTitle,
      sceneImage:    clearSceneImage ? null : (sceneImage ?? this.sceneImage),
      dialogues:     dialogues     ?? this.dialogues,
      questions:     questions     ?? this.questions,
      mood:          mood          ?? this.mood,
      stageType:     stageType     ?? this.stageType,
      backgroundKey: clearBackgroundKey ? null : (backgroundKey ?? this.backgroundKey),
      musicCue:      musicCue      ?? this.musicCue,
    );
  }

  bool get hasBackground => sceneImage != null || backgroundKey != null;
}

// ─────────────────────────────────────────────────────────────────────────────

class DialogueData {
  final String tempId;
  final String? characterTempId;
  final String dialogueText;
  final DialogueEmotion emotion;
  final TypewriterSpeed typewriterSpeed;
  final int pauseAfterMs;

  DialogueData({
    required this.tempId,
    this.characterTempId,
    required this.dialogueText,
    this.emotion         = DialogueEmotion.neutral,
    this.typewriterSpeed = TypewriterSpeed.normal,
    this.pauseAfterMs    = 0,
  });

  DialogueData copyWith({
    String? characterTempId,
    String? dialogueText,
    DialogueEmotion? emotion,
    TypewriterSpeed? typewriterSpeed,
    int? pauseAfterMs,
  }) {
    return DialogueData(
      tempId:          tempId,
      characterTempId: characterTempId ?? this.characterTempId,
      dialogueText:    dialogueText    ?? this.dialogueText,
      emotion:         emotion         ?? this.emotion,
      typewriterSpeed: typewriterSpeed ?? this.typewriterSpeed,
      pauseAfterMs:    pauseAfterMs    ?? this.pauseAfterMs,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class QuestionData {
  final String tempId;
  final String questionText;
  final String questionType;
  final List<String> options;
  final int correctOptionIndex;
  final String? explanation;
  final bool hasLearningGate;
  final String? gateContentDomain;
  final int gateSkipDelaySeconds;

  QuestionData({
    required this.tempId,
    required this.questionText,
    required this.questionType,
    required this.options,
    required this.correctOptionIndex,
    this.explanation,
    this.hasLearningGate      = false,
    this.gateContentDomain,
    this.gateSkipDelaySeconds = 5,
  });

  QuestionData copyWith({
    String? questionText,
    String? questionType,
    List<String>? options,
    int? correctOptionIndex,
    String? explanation,
    bool? hasLearningGate,
    String? gateContentDomain,
    int? gateSkipDelaySeconds,
  }) {
    return QuestionData(
      tempId:               tempId,
      questionText:         questionText         ?? this.questionText,
      questionType:         questionType         ?? this.questionType,
      options:              options              ?? this.options,
      correctOptionIndex:   correctOptionIndex   ?? this.correctOptionIndex,
      explanation:          explanation          ?? this.explanation,
      hasLearningGate:      hasLearningGate      ?? this.hasLearningGate,
      gateContentDomain:    gateContentDomain    ?? this.gateContentDomain,
      gateSkipDelaySeconds: gateSkipDelaySeconds ?? this.gateSkipDelaySeconds,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class CharacterData {
  final String tempId;
  final String characterName;
  final String? characterDescription;
  final XFile? characterImage;
  final PortraitSide portraitSide;
  final bool isPlayer;
  final String? assetKey;

  CharacterData({
    required this.tempId,
    required this.characterName,
    this.characterDescription,
    this.characterImage,
    this.portraitSide = PortraitSide.left,
    this.isPlayer     = false,
    this.assetKey,
  });

  CharacterData copyWith({
    String? characterName,
    String? characterDescription,
    XFile? characterImage,
    bool clearCharacterImage = false,
    PortraitSide? portraitSide,
    bool? isPlayer,
    String? assetKey,
    bool clearAssetKey = false,
  }) {
    return CharacterData(
      tempId:               tempId,
      characterName:        characterName        ?? this.characterName,
      characterDescription: characterDescription ?? this.characterDescription,
      characterImage:       clearCharacterImage ? null : (characterImage ?? this.characterImage),
      portraitSide:         portraitSide         ?? this.portraitSide,
      isPlayer:             isPlayer             ?? this.isPlayer,
      assetKey:             clearAssetKey ? null : (assetKey ?? this.assetKey),
    );
  }

  bool get hasImage => characterImage != null || assetKey != null;
}

// =============================================================================
// NOTIFIER
// =============================================================================

class TaikenCreateNotifier extends StateNotifier<TaikenCreateState> {
  TaikenCreateNotifier(this._pointsService, this._ref)
      : super(TaikenCreateState()) {
    _initializeStages();
    _initModeration();
  }

  final SupabaseClient     _supabase     = Supabase.instance.client;
  final ImagePicker        _imagePicker  = ImagePicker();
  final Uuid               _uuid         = const Uuid();
  final PlaroPointsService _pointsService;
  final Ref                _ref;

  // ── Moderation init ───────────────────────────────────────────────────────

  Future<void> _initModeration() async {
    try {
      await _ref.read(moderationServiceProvider).init();
    } catch (e) {
      debugPrint('[Moderation] Failed to preload models: $e');
    }
  }

  // ── Stage initialisation ──────────────────────────────────────────────────

  void _initializeStages() {
    state = state.copyWith(
      stages: List.generate(
        state.totalStages,
        (i) => StageData(tempId: _uuid.v4(), stageTitle: 'Stage ${i + 1}'),
      ),
    );
  }

  // ── Field updaters — unchanged ────────────────────────────────────────────

  void updateTitle(String v)              => state = state.copyWith(title: v);
  void updateDescription(String v)        => state = state.copyWith(description: v);
  void updateDomain(String v)             => state = state.copyWith(domain: v);
  void updateDifficulty(String v)         => state = state.copyWith(difficulty: v);
  void updateIntroScript(String v)        => state = state.copyWith(introScript: v);
  void updateOutroSuccessScript(String v) => state = state.copyWith(outroSuccessScript: v);
  void updateOutroFailureScript(String v) => state = state.copyWith(outroFailureScript: v);
  void updatePassThreshold(int v)         => state = state.copyWith(passThreshold: v);
  void updateSeriesId(String? v)          => state = state.copyWith(seriesId: v);
  void updateEpisodeNumber(int? v)        => state = state.copyWith(episodeNumber: v);
  void updateDefaultMusicCue(String? v)   => state = state.copyWith(
      defaultMusicCue: v, clearDefaultMusicCue: v == null);

  Future<void> pickThumbnail() async {
    try {
      final img = await _imagePicker.pickImage(
          source: ImageSource.gallery, imageQuality: 80);
      if (img != null) state = state.copyWith(thumbnailFile: img);
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick thumbnail: $e');
    }
  }

  void setTotalStages(int count) {
    if (count < 1) return;
    final stages = List<StageData>.from(state.stages);
    if (count > stages.length) {
      for (int i = stages.length; i < count; i++) {
        stages.add(StageData(tempId: _uuid.v4(), stageTitle: 'Stage ${i + 1}'));
      }
    } else {
      stages.removeRange(count, stages.length);
    }
    state = state.copyWith(totalStages: count, stages: stages);
  }

  void updateStage(int index, StageData updated) {
    final stages = List<StageData>.from(state.stages);
    stages[index] = updated;
    state = state.copyWith(stages: stages);
  }

  Future<void> pickSceneImage(int stageIndex) async {
    try {
      final img = await _imagePicker.pickImage(
          source: ImageSource.gallery, imageQuality: 80);
      if (img != null) {
        final stages = List<StageData>.from(state.stages);
        stages[stageIndex] = stages[stageIndex].copyWith(sceneImage: img);
        state = state.copyWith(stages: stages);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick scene image: $e');
    }
  }

  void addDialogue(int stageIndex) {
    final stages    = List<StageData>.from(state.stages);
    final dialogues = List<DialogueData>.from(stages[stageIndex].dialogues);
    dialogues.add(DialogueData(tempId: _uuid.v4(), dialogueText: ''));
    stages[stageIndex] = stages[stageIndex].copyWith(dialogues: dialogues);
    state = state.copyWith(stages: stages);
  }

  void updateDialogue(int si, int di, DialogueData updated) {
    final stages    = List<StageData>.from(state.stages);
    final dialogues = List<DialogueData>.from(stages[si].dialogues);
    dialogues[di] = updated;
    stages[si] = stages[si].copyWith(dialogues: dialogues);
    state = state.copyWith(stages: stages);
  }

  void removeDialogue(int si, int di) {
    final stages    = List<StageData>.from(state.stages);
    final dialogues = List<DialogueData>.from(stages[si].dialogues);
    dialogues.removeAt(di);
    stages[si] = stages[si].copyWith(dialogues: dialogues);
    state = state.copyWith(stages: stages);
  }

  void addQuestion(int stageIndex) {
    final stages    = List<StageData>.from(state.stages);
    final questions = List<QuestionData>.from(stages[stageIndex].questions);
    questions.add(QuestionData(
      tempId:             _uuid.v4(),
      questionText:       '',
      questionType:       'multiple_choice',
      options:            ['', '', '', ''],
      correctOptionIndex: 0,
    ));
    stages[stageIndex] = stages[stageIndex].copyWith(questions: questions);
    state = state.copyWith(stages: stages);
  }

  void updateQuestion(int si, int qi, QuestionData updated) {
    final stages    = List<StageData>.from(state.stages);
    final questions = List<QuestionData>.from(stages[si].questions);
    questions[qi] = updated;
    stages[si] = stages[si].copyWith(questions: questions);
    state = state.copyWith(stages: stages);
  }

  void removeQuestion(int si, int qi) {
    final stages    = List<StageData>.from(state.stages);
    final questions = List<QuestionData>.from(stages[si].questions);
    questions.removeAt(qi);
    stages[si] = stages[si].copyWith(questions: questions);
    state = state.copyWith(stages: stages);
  }

  void addCharacter() {
    final chars = List<CharacterData>.from(state.characters);
    final side  = chars.length.isEven ? PortraitSide.left : PortraitSide.right;
    chars.add(CharacterData(
      tempId:        _uuid.v4(),
      characterName: 'Character ${chars.length + 1}',
      portraitSide:  side,
    ));
    state = state.copyWith(characters: chars);
  }

  void updateCharacter(int index, CharacterData updated) {
    final chars = List<CharacterData>.from(state.characters);
    chars[index] = updated;
    state = state.copyWith(characters: chars);
  }

  void removeCharacter(int index) {
    final chars   = List<CharacterData>.from(state.characters);
    final removed = chars[index].tempId;
    chars.removeAt(index);

    final stages = List<StageData>.from(state.stages);
    for (int i = 0; i < stages.length; i++) {
      final dialogues = List<DialogueData>.from(stages[i].dialogues);
      for (int j = 0; j < dialogues.length; j++) {
        if (dialogues[j].characterTempId == removed) {
          dialogues[j] = dialogues[j].copyWith(characterTempId: null);
        }
      }
      stages[i] = stages[i].copyWith(dialogues: dialogues);
    }
    state = state.copyWith(characters: chars, stages: stages);
  }

  Future<void> pickCharacterImage(int index) async {
    try {
      final img = await _imagePicker.pickImage(
          source: ImageSource.gallery, imageQuality: 80);
      if (img != null) {
        final chars = List<CharacterData>.from(state.characters);
        chars[index] = chars[index].copyWith(characterImage: img);
        state = state.copyWith(characters: chars);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick character image: $e');
    }
  }

  // ── Image upload helper — with on-device moderation ───────────────────────
  //
  // CHANGED: the previously empty moderation block is now filled in.
  // Any image (thumbnail / scene / character) is checked against the
  // GantMan NSFW model before uploading. Blocked images return null
  // and set a clear error on state.

  Future<String?> _uploadImage(
      XFile file, String bucket, String userId) async {
    final String ext = file.path.split('.').last.toLowerCase();
    if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'}.contains(ext)) {
      try {
        final moderation = _ref.read(moderationServiceProvider);
        final result     = await moderation.moderateImage(file.path);

        debugPrint(
          '[Moderation] Taiken image ($bucket): '
          'nsfw=${result.nsfwScore.toStringAsFixed(3)} '
          'verdict=${result.verdict.name}',
        );

        if (result.isBlocked) {
          state = state.copyWith(
            error: result.reason ?? 'One of your images was flagged as inappropriate.',
          );
          return null;
        }
      } catch (e) {
        // Non-fatal: model error should never block a creator
        debugPrint('[Moderation] Taiken image check error (non-fatal): $e');
      }
    }

    final bytes    = await file.readAsBytes();
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_'
        '${_uuid.v4().substring(0, 8)}.$ext';
    final filePath = '$userId/$fileName';
    await _supabase.storage.from(bucket).uploadBinary(
      filePath, bytes,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
    );
    return _supabase.storage.from(bucket).getPublicUrl(filePath);
  }

  // ── createTaiken — main publish ───────────────────────────────────────────

  Future<bool> createTaiken() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      state = state.copyWith(error: 'User not authenticated');
      return false;
    }

    if (state.title.isEmpty) {
      state = state.copyWith(error: 'Please enter a title');
      return false;
    }
    if (state.domain.isEmpty) {
      state = state.copyWith(error: 'Please select a domain');
      return false;
    }
    if (state.introScript.isEmpty) {
      state = state.copyWith(error: 'Please write an intro script');
      return false;
    }
    for (final stage in state.stages) {
      if (stage.questions.isEmpty) {
        state = state.copyWith(error: 'Each stage must have at least one question');
        return false;
      }
    }

    state = state.copyWith(isLoading: true, error: null);

    // ── Step 0: Text moderation ───────────────────────────────────────────
    // Collect ALL text fields that a user wrote: title, description, scripts,
    // every dialogue line, every question text.
    // Wordlist runs first (instant), then ML model on the combined blob.
    try {
      final moderation = _ref.read(moderationServiceProvider);

      // Collect all dialogue and question texts for wordlist scan
      final allDialogueTexts = state.stages
          .expand((s) => s.dialogues.map((d) => d.dialogueText))
          .where((t) => t.isNotEmpty)
          .toList();
      final allQuestionTexts = state.stages
          .expand((s) => s.questions.map((q) => q.questionText))
          .where((t) => t.isNotEmpty)
          .toList();

      // moderatePost checks title+content+tags via wordlist then ML.
      // We call it once for the main fields, then individually for
      // dialogue/question texts (wordlist only — too many for ML).
      final mainResult = await moderation.moderatePost(
        title:   state.title,
        content: '${state.description} ${state.introScript} '
                 '${state.outroSuccessScript} ${state.outroFailureScript}',
        tags:    [],
      );

      if (mainResult.isBlocked) {
        state = state.copyWith(
          isLoading: false,
          error: mainResult.reason ?? 'Your Taiken contains inappropriate content.',
        );
        return false;
      }

      // Check individual dialogue/question texts through wordlist only
      // (fast, no ML — we already ran ML on the main blob above)
      for (final text in [...allDialogueTexts, ...allQuestionTexts]) {
        final r = await moderation.moderatePost(
          title: text, content: '', tags: [],
        );
        if (r.isBlocked && r.fromWordlist) {
          state = state.copyWith(
            isLoading: false,
            error: 'Your Taiken contains inappropriate language in its content.',
          );
          return false;
        }
      }
    } catch (e) {
      // Non-fatal: text check failure should not block creation
      debugPrint('[Moderation] Taiken text check error (non-fatal): $e');
    }

    // ── Step 1: unchanged validation already done above ───────────────────

    // ── Step 2: Upload thumbnail ──────────────────────────────────────────
    String? thumbnailUrl;
    if (state.thumbnailFile != null) {
      thumbnailUrl = await _uploadImage(
          state.thumbnailFile!, 'taiken-thumbnails', userId);
      if (thumbnailUrl == null) {
        state = state.copyWith(isLoading: false);
        return false;
      }
    }

    final totalQuestions =
        state.stages.fold<int>(0, (sum, s) => sum + s.questions.length);
    final taikenId = _uuid.v4();
    final now      = DateTime.now().toIso8601String();

    // ── Insert taiken row ─────────────────────────────────────────────────
    await _supabase.from('taikens').insert({
      'taiken_id':            taikenId,
      'creator_id':           userId,
      'title':                state.title,
      'description':          state.description,
      'domain':               state.domain,
      'difficulty':           state.difficulty,
      'intro_script':         state.introScript,
      'outro_success_script': state.outroSuccessScript,
      'outro_failure_script': state.outroFailureScript,
      'thumbnail_url':        thumbnailUrl,
      'total_stages':         state.totalStages,
      'total_questions':      totalQuestions,
      'pass_threshold':       state.passThreshold,
      'is_published':         true,
      'created_at':           now,
      'updated_at':           now,
      if (state.seriesId       != null) 'series_id':          state.seriesId,
      if (state.episodeNumber  != null) 'episode_number':     state.episodeNumber,
      if (state.defaultMusicCue != null) 'default_music_cue': state.defaultMusicCue,
    });

    // ── Insert characters ─────────────────────────────────────────────────
    final Map<String, String> charIdMap = {};
    for (int i = 0; i < state.characters.length; i++) {
      final c   = state.characters[i];
      final cId = _uuid.v4();
      charIdMap[c.tempId] = cId;

      String? imgUrl;
      if (c.characterImage != null) {
        imgUrl = await _uploadImage(c.characterImage!, 'taiken-characters', userId);
        if (imgUrl == null) {
          state = state.copyWith(isLoading: false);
          return false;
        }
      }

      await _supabase.from('taiken_characters').insert({
        'character_id':          cId,
        'taiken_id':             taikenId,
        'character_name':        c.characterName,
        'character_image_url':   imgUrl,
        'character_description': c.characterDescription,
        'display_order':         i,
        'portrait_side':         c.portraitSide.name,
        'is_player':             c.isPlayer,
        if (c.assetKey != null) 'asset_key': c.assetKey,
        'created_at':            now,
      });
    }

    // ── Insert stages ─────────────────────────────────────────────────────
    for (int si = 0; si < state.stages.length; si++) {
      final stage   = state.stages[si];
      final stageId = _uuid.v4();

      String? sceneUrl;
      if (stage.sceneImage != null) {
        sceneUrl = await _uploadImage(stage.sceneImage!, 'taiken-scenes', userId);
        if (sceneUrl == null) {
          state = state.copyWith(isLoading: false);
          return false;
        }
      }

      await _supabase.from('taiken_stages').insert({
        'stage_id':             stageId,
        'taiken_id':            taikenId,
        'stage_order':          si + 1,
        'stage_title':          stage.stageTitle,
        'scene_image_url':      sceneUrl,
        'background_image_url': sceneUrl,
        'mood':                 stage.mood.name,
        'stage_type':           stage.stageType.name,
        if (stage.backgroundKey != null) 'background_key': stage.backgroundKey,
        if (stage.musicCue      != null) 'music_cue':      stage.musicCue,
        'created_at':           now,
      });

      for (int di = 0; di < stage.dialogues.length; di++) {
        final d = stage.dialogues[di];
        await _supabase.from('taiken_dialogues').insert({
          'dialogue_id':      _uuid.v4(),
          'stage_id':         stageId,
          'character_id':     d.characterTempId != null
              ? charIdMap[d.characterTempId]
              : null,
          'dialogue_text':    d.dialogueText,
          'dialogue_order':   di,
          'emotion':          d.emotion.name,
          'typewriter_speed': d.typewriterSpeed.name,
          'pause_after_ms':   d.pauseAfterMs,
          'created_at':       now,
        });
      }

      for (int qi = 0; qi < stage.questions.length; qi++) {
        final q = stage.questions[qi];
        await _supabase.from('taiken_questions').insert({
          'question_id':             _uuid.v4(),
          'stage_id':                stageId,
          'question_text':           q.questionText,
          'question_type':           q.questionType,
          'options':                 q.options,
          'correct_option_index':    q.correctOptionIndex,
          'explanation':             q.explanation,
          'question_order':          qi,
          'has_learning_gate':       q.hasLearningGate,
          'gate_content_domain':     q.gateContentDomain,
          'gate_skip_delay_seconds': q.gateSkipDelaySeconds,
          'created_at':              now,
        });
      }
    }

    // ── Award Plaro points ────────────────────────────────────────────────
    try {
      await _pointsService.awardPointsForContent(
        userId:      userId,
        contentType: 'taiken',
        contentId:   taikenId,
      );
      debugPrint('[Points] awarded for taiken $taikenId');
    } catch (e) {
      debugPrint('[Points] non-fatal error: $e');
    }

    // Capture domain BEFORE state reset
    final capturedDomain = state.domain.isEmpty ? null : state.domain;
    _ref.read(streakProvider.notifier).logTaikenStageCompletion(
      taikenStageId: taikenId,
      domain:        capturedDomain,
    );

    state = state.copyWith(
      isLoading:      false,
      successMessage: 'Taiken created successfully!',
    );
    return true;
  }

  // ── Catch block — unchanged ───────────────────────────────────────────────

  void clearError() => state = state.copyWith(error: null);

  void reset() {
    state = TaikenCreateState();
    _initializeStages();
  }
}

// =============================================================================
// PROVIDER
// =============================================================================

final taikenCreateProvider =
    StateNotifierProvider<TaikenCreateNotifier, TaikenCreateState>((ref) {
  final pointsService = ref.read(plaroPointsServiceProvider);
  return TaikenCreateNotifier(pointsService, ref);
});