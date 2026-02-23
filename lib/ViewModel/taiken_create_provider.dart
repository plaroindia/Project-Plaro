import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../Model/taiken.dart';
import 'plaro_points_service.dart'; // ✅ NEW
import 'streak_provider.dart';      // ✅ NEW

// =============================================================================
// STATE + DATA CLASSES (unchanged from original)
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
  }) {
    return TaikenCreateState(
      title: title ?? this.title,
      description: description ?? this.description,
      domain: domain ?? this.domain,
      difficulty: difficulty ?? this.difficulty,
      introScript: introScript ?? this.introScript,
      outroSuccessScript: outroSuccessScript ?? this.outroSuccessScript,
      outroFailureScript: outroFailureScript ?? this.outroFailureScript,
      thumbnailFile: thumbnailFile ?? this.thumbnailFile,
      totalStages: totalStages ?? this.totalStages,
      stages: stages ?? this.stages,
      characters: characters ?? this.characters,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      successMessage: successMessage,
    );
  }
}

class StageData {
  final String tempId;
  final String stageTitle;
  final XFile? sceneImage;
  final List<DialogueData> dialogues;
  final List<QuestionData> questions;

  StageData({
    required this.tempId,
    required this.stageTitle,
    this.sceneImage,
    this.dialogues = const [],
    this.questions = const [],
  });

  StageData copyWith({
    String? stageTitle,
    XFile? sceneImage,
    List<DialogueData>? dialogues,
    List<QuestionData>? questions,
  }) {
    return StageData(
      tempId: tempId,
      stageTitle: stageTitle ?? this.stageTitle,
      sceneImage: sceneImage ?? this.sceneImage,
      dialogues: dialogues ?? this.dialogues,
      questions: questions ?? this.questions,
    );
  }
}

class DialogueData {
  final String tempId;
  final String? characterTempId;
  final String dialogueText;

  DialogueData({
    required this.tempId,
    this.characterTempId,
    required this.dialogueText,
  });

  DialogueData copyWith({
    String? characterTempId,
    String? dialogueText,
  }) {
    return DialogueData(
      tempId: tempId,
      characterTempId: characterTempId ?? this.characterTempId,
      dialogueText: dialogueText ?? this.dialogueText,
    );
  }
}

class QuestionData {
  final String tempId;
  final String questionText;
  final String questionType;
  final List<String> options;
  final int correctOptionIndex;
  final String? explanation;

  QuestionData({
    required this.tempId,
    required this.questionText,
    required this.questionType,
    required this.options,
    required this.correctOptionIndex,
    this.explanation,
  });

  QuestionData copyWith({
    String? questionText,
    String? questionType,
    List<String>? options,
    int? correctOptionIndex,
    String? explanation,
  }) {
    return QuestionData(
      tempId: tempId,
      questionText: questionText ?? this.questionText,
      questionType: questionType ?? this.questionType,
      options: options ?? this.options,
      correctOptionIndex: correctOptionIndex ?? this.correctOptionIndex,
      explanation: explanation ?? this.explanation,
    );
  }
}

class CharacterData {
  final String tempId;
  final String characterName;
  final String? characterDescription;
  final XFile? characterImage;

  CharacterData({
    required this.tempId,
    required this.characterName,
    this.characterDescription,
    this.characterImage,
  });

  CharacterData copyWith({
    String? characterName,
    String? characterDescription,
    XFile? characterImage,
  }) {
    return CharacterData(
      tempId: tempId,
      characterName: characterName ?? this.characterName,
      characterDescription: characterDescription ?? this.characterDescription,
      characterImage: characterImage ?? this.characterImage,
    );
  }
}

// =============================================================================
// NOTIFIER
// =============================================================================

class TaikenCreateNotifier extends StateNotifier<TaikenCreateState> {
  // ✅ UPDATED: accepts PlaroPointsService and Ref
  TaikenCreateNotifier(this._pointsService, this._ref)
      : super(TaikenCreateState()) {
    _initializeStages();
  }

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();
  final Uuid _uuid = const Uuid();
  final PlaroPointsService _pointsService; // ✅ NEW
  final Ref _ref;                          // ✅ NEW

  // ---------------------------------------------------------------------------
  // Stage initialisation (unchanged)
  // ---------------------------------------------------------------------------

  void _initializeStages() {
    state = state.copyWith(
      stages: List.generate(
        state.totalStages,
            (index) => StageData(
          tempId: _uuid.v4(),
          stageTitle: 'Stage ${index + 1}',
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Field updaters (unchanged)
  // ---------------------------------------------------------------------------

  void updateTitle(String title)                     => state = state.copyWith(title: title);
  void updateDescription(String description)         => state = state.copyWith(description: description);
  void updateDomain(String domain)                   => state = state.copyWith(domain: domain);
  void updateDifficulty(String difficulty)           => state = state.copyWith(difficulty: difficulty);
  void updateIntroScript(String script)              => state = state.copyWith(introScript: script);
  void updateOutroSuccessScript(String script)       => state = state.copyWith(outroSuccessScript: script);
  void updateOutroFailureScript(String script)       => state = state.copyWith(outroFailureScript: script);

  Future<void> pickThumbnail() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) state = state.copyWith(thumbnailFile: image);
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick thumbnail: $e');
    }
  }

  void setTotalStages(int count) {
    if (count < 1) return;
    final currentStages = List<StageData>.from(state.stages);
    if (count > currentStages.length) {
      for (int i = currentStages.length; i < count; i++) {
        currentStages.add(StageData(
          tempId: _uuid.v4(),
          stageTitle: 'Stage ${i + 1}',
        ));
      }
    } else {
      currentStages.removeRange(count, currentStages.length);
    }
    state = state.copyWith(totalStages: count, stages: currentStages);
  }

  void updateStage(int index, StageData updatedStage) {
    final stages = List<StageData>.from(state.stages);
    stages[index] = updatedStage;
    state = state.copyWith(stages: stages);
  }

  Future<void> pickSceneImage(int stageIndex) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        final stages = List<StageData>.from(state.stages);
        stages[stageIndex] = stages[stageIndex].copyWith(sceneImage: image);
        state = state.copyWith(stages: stages);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick scene image: $e');
    }
  }

  void addDialogue(int stageIndex) {
    final stages = List<StageData>.from(state.stages);
    final dialogues = List<DialogueData>.from(stages[stageIndex].dialogues);
    dialogues.add(DialogueData(tempId: _uuid.v4(), dialogueText: ''));
    stages[stageIndex] = stages[stageIndex].copyWith(dialogues: dialogues);
    state = state.copyWith(stages: stages);
  }

  void updateDialogue(int stageIndex, int dialogueIndex, DialogueData updated) {
    final stages = List<StageData>.from(state.stages);
    final dialogues = List<DialogueData>.from(stages[stageIndex].dialogues);
    dialogues[dialogueIndex] = updated;
    stages[stageIndex] = stages[stageIndex].copyWith(dialogues: dialogues);
    state = state.copyWith(stages: stages);
  }

  void removeDialogue(int stageIndex, int dialogueIndex) {
    final stages = List<StageData>.from(state.stages);
    final dialogues = List<DialogueData>.from(stages[stageIndex].dialogues);
    dialogues.removeAt(dialogueIndex);
    stages[stageIndex] = stages[stageIndex].copyWith(dialogues: dialogues);
    state = state.copyWith(stages: stages);
  }

  void addQuestion(int stageIndex) {
    final stages = List<StageData>.from(state.stages);
    final questions = List<QuestionData>.from(stages[stageIndex].questions);
    questions.add(QuestionData(
      tempId: _uuid.v4(),
      questionText: '',
      questionType: 'multiple_choice',
      options: ['', '', '', ''],
      correctOptionIndex: 0,
    ));
    stages[stageIndex] = stages[stageIndex].copyWith(questions: questions);
    state = state.copyWith(stages: stages);
  }

  void updateQuestion(int stageIndex, int questionIndex, QuestionData updated) {
    final stages = List<StageData>.from(state.stages);
    final questions = List<QuestionData>.from(stages[stageIndex].questions);
    questions[questionIndex] = updated;
    stages[stageIndex] = stages[stageIndex].copyWith(questions: questions);
    state = state.copyWith(stages: stages);
  }

  void removeQuestion(int stageIndex, int questionIndex) {
    final stages = List<StageData>.from(state.stages);
    final questions = List<QuestionData>.from(stages[stageIndex].questions);
    questions.removeAt(questionIndex);
    stages[stageIndex] = stages[stageIndex].copyWith(questions: questions);
    state = state.copyWith(stages: stages);
  }

  void addCharacter() {
    final characters = List<CharacterData>.from(state.characters);
    characters.add(CharacterData(
      tempId: _uuid.v4(),
      characterName: 'Character ${characters.length + 1}',
    ));
    state = state.copyWith(characters: characters);
  }

  void updateCharacter(int index, CharacterData updatedCharacter) {
    final characters = List<CharacterData>.from(state.characters);
    characters[index] = updatedCharacter;
    state = state.copyWith(characters: characters);
  }

  void removeCharacter(int index) {
    final characters = List<CharacterData>.from(state.characters);
    final removedTempId = characters[index].tempId;
    characters.removeAt(index);
    // Clear references in dialogues
    final stages = List<StageData>.from(state.stages);
    for (int i = 0; i < stages.length; i++) {
      final dialogues = List<DialogueData>.from(stages[i].dialogues);
      for (int j = 0; j < dialogues.length; j++) {
        if (dialogues[j].characterTempId == removedTempId) {
          dialogues[j] = dialogues[j].copyWith(characterTempId: null);
        }
      }
      stages[i] = stages[i].copyWith(dialogues: dialogues);
    }
    state = state.copyWith(characters: characters, stages: stages);
  }

  Future<void> pickCharacterImage(int index) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        final characters = List<CharacterData>.from(state.characters);
        characters[index] = characters[index].copyWith(characterImage: image);
        state = state.copyWith(characters: characters);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick character image: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Image upload helper (unchanged)
  // ---------------------------------------------------------------------------

  Future<String?> _uploadImage(
      XFile file, String bucketName, String userId) async {
    try {
      final bytes = await file.readAsBytes();
      final fileExtension = file.path.split('.').last.toLowerCase();
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}.$fileExtension';
      final filePath = '$userId/$fileName';
      await _supabase.storage.from(bucketName).uploadBinary(
        filePath,
        bytes,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
      );
      return _supabase.storage.from(bucketName).getPublicUrl(filePath);
    } catch (e) {
      throw Exception('Failed to upload image: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // createTaiken — main publish method
  // ✅ UPDATED: awards Plaro points + logs streak event after success
  // ---------------------------------------------------------------------------

  Future<bool> createTaiken() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) {
      state = state.copyWith(error: 'User not authenticated');
      return false;
    }

    // Validation
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
        state = state.copyWith(
            error: 'Each stage must have at least one question');
        return false;
      }
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      // Upload thumbnail
      String? thumbnailUrl;
      if (state.thumbnailFile != null) {
        thumbnailUrl = await _uploadImage(
            state.thumbnailFile!, 'taiken-thumbnails', currentUserId);
      }

      // Total questions count
      final totalQuestions =
      state.stages.fold<int>(0, (sum, s) => sum + s.questions.length);

      // Insert taiken row
      final taikenId = _uuid.v4();
      await _supabase.from('taikens').insert({
        'taiken_id': taikenId,
        'creator_id': currentUserId,
        'title': state.title,
        'description': state.description,
        'domain': state.domain,
        'difficulty': state.difficulty,
        'intro_script': state.introScript,
        'outro_success_script': state.outroSuccessScript,
        'outro_failure_script': state.outroFailureScript,
        'thumbnail_url': thumbnailUrl,
        'total_stages': state.totalStages,
        'total_questions': totalQuestions,
        'is_published': true,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Insert characters
      final Map<String, String> characterIdMap = {};
      for (int i = 0; i < state.characters.length; i++) {
        final character = state.characters[i];
        String? characterImageUrl;
        if (character.characterImage != null) {
          characterImageUrl = await _uploadImage(
              character.characterImage!, 'taiken-characters', currentUserId);
        }
        final characterId = _uuid.v4();
        characterIdMap[character.tempId] = characterId;
        await _supabase.from('taiken_characters').insert({
          'character_id': characterId,
          'taiken_id': taikenId,
          'character_name': character.characterName,
          'character_image_url': characterImageUrl,
          'character_description': character.characterDescription,
          'display_order': i,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      // Insert stages, dialogues, questions
      for (int stageIndex = 0;
      stageIndex < state.stages.length;
      stageIndex++) {
        final stage = state.stages[stageIndex];
        String? sceneImageUrl;
        if (stage.sceneImage != null) {
          sceneImageUrl = await _uploadImage(
              stage.sceneImage!, 'taiken-scenes', currentUserId);
        }
        final stageId = _uuid.v4();
        await _supabase.from('taiken_stages').insert({
          'stage_id': stageId,
          'taiken_id': taikenId,
          'stage_order': stageIndex + 1,
          'stage_title': stage.stageTitle,
          'scene_image_url': sceneImageUrl,
          'created_at': DateTime.now().toIso8601String(),
        });

        for (int di = 0; di < stage.dialogues.length; di++) {
          final dialogue = stage.dialogues[di];
          await _supabase.from('taiken_dialogues').insert({
            'dialogue_id': _uuid.v4(),
            'stage_id': stageId,
            'character_id': dialogue.characterTempId != null
                ? characterIdMap[dialogue.characterTempId]
                : null,
            'dialogue_text': dialogue.dialogueText,
            'dialogue_order': di,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        for (int qi = 0; qi < stage.questions.length; qi++) {
          final question = stage.questions[qi];
          await _supabase.from('taiken_questions').insert({
            'question_id': _uuid.v4(),
            'stage_id': stageId,
            'question_text': question.questionText,
            'question_type': question.questionType,
            'options': question.options,
            'correct_option_index': question.correctOptionIndex,
            'explanation': question.explanation,
            'question_order': qi,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      // ── Award Plaro content-creation points ──────────────────────────────
      // Taiken creation = 10 pts (see plaro_points_service.dart pointsMap).
      try {
        await _pointsService.awardPointsForContent(
          userId: currentUserId,
          contentType: 'taiken',
          contentId: taikenId,
        );
        debugPrint('✅ Plaro points awarded for taiken $taikenId');
      } catch (pointsError) {
        // Non-fatal — never block publish on points failure
        debugPrint('❌ Failed to award Plaro points: $pointsError');
      }

      // ── Log streak event (creator published educational content) ─────────
      // Taiken creation does NOT itself count as a streak event in the current
      // SQL trigger (which only matches 'post' and 'byte' creates, and
      // 'taiken_stage' completes).  If you later decide taiken creation should
      // extend the streak, add 'taiken' to the trigger's IN clause and
      // uncomment the call below.
      //
      // _ref.read(streakProvider.notifier).logPostCreated(
      //   postId: 0, // taiken uses a uuid — adapt StreakService if needed
      //   domain: state.domain,
      // );

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Taiken created successfully!',
      );
      return true;
    } catch (e) {
      debugPrint('❌ createTaiken error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to create Taiken: $e',
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);

  void reset() {
    state = TaikenCreateState();
    _initializeStages();
  }
}

// =============================================================================
// PROVIDER
// ✅ UPDATED: passes PlaroPointsService and Ref into the notifier
// =============================================================================

final taikenCreateProvider =
StateNotifierProvider<TaikenCreateNotifier, TaikenCreateState>((ref) {
  final pointsService = ref.read(plaroPointsServiceProvider);
  return TaikenCreateNotifier(pointsService, ref);
});