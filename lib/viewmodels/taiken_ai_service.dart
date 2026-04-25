// =============================================================================
// taiken_ai_service.dart
//
// Calls the Gemini 1.5 Flash API with a structured prompt and returns a
// fully-typed TaikenAiOutput that maps directly onto the existing
// TaikenCreateState / StageData / DialogueData / QuestionData / CharacterData
// data classes.
//
// NO images are generated.  All character / background / music / sfx values
// are validated against the predefined asset lists before being returned.
// =============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/taiken.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Predefined asset lists  — single source of truth
// ─────────────────────────────────────────────────────────────────────────────

class TaikenAssets {
  static const List<String> characters = [
    'alex', 'maya', 'ken', 'sara', 'leo', 'nina', 'arjun', 'emma', 'ryan', 'zoe',
  ];

  static const List<String> backgrounds = [
    'classroom', 'office', 'library', 'city', 'tech_lab',
    'startup_office', 'study_room', 'conference_room',
  ];

  static const List<String> backgroundMusic = [
    'ambient', 'study', 'focus',
  ];

  static const List<String> soundEffects = [
    'click', 'success', 'wrong',
  ];

  static String validateCharacter(String? v) =>
      characters.contains(v) ? v! : characters.first;

  static String validateBackground(String? v) =>
      backgrounds.contains(v) ? v! : backgrounds.first;

  static String validateMusic(String? v) =>
      backgroundMusic.contains(v) ? v! : backgroundMusic.first;
}

// ─────────────────────────────────────────────────────────────────────────────
// Output model — parsed Gemini response
// ─────────────────────────────────────────────────────────────────────────────

class TaikenAiOutput {
  final String title;
  final String description;
  final String domain;
  final String difficulty;
  final String introScript;
  final String outroSuccessScript;
  final String outroFailureScript;
  final List<AiCharacterOutput> characters;
  final List<AiStageOutput> stages;

  TaikenAiOutput({
    required this.title,
    required this.description,
    required this.domain,
    required this.difficulty,
    required this.introScript,
    required this.outroSuccessScript,
    required this.outroFailureScript,
    required this.characters,
    required this.stages,
  });
}

class AiCharacterOutput {
  final String name;
  final String description;
  final String assetKey;       // from TaikenAssets.characters
  final PortraitSide side;
  final bool isPlayer;

  AiCharacterOutput({
    required this.name,
    required this.description,
    required this.assetKey,
    required this.side,
    required this.isPlayer,
  });
}

class AiStageOutput {
  final String title;
  final String backgroundKey;  // from TaikenAssets.backgrounds
  final StageMood mood;
  final StageType stageType;
  final String? musicCue;
  final List<AiDialogueOutput> dialogues;
  final List<AiQuestionOutput> questions;

  AiStageOutput({
    required this.title,
    required this.backgroundKey,
    required this.mood,
    required this.stageType,
    this.musicCue,
    required this.dialogues,
    required this.questions,
  });
}

class AiDialogueOutput {
  final String characterName;  // matched back to AiCharacterOutput by name
  final String text;
  final DialogueEmotion emotion;
  final TypewriterSpeed typewriterSpeed;
  final int pauseAfterMs;

  AiDialogueOutput({
    required this.characterName,
    required this.text,
    required this.emotion,
    required this.typewriterSpeed,
    required this.pauseAfterMs,
  });
}

class AiQuestionOutput {
  final String questionText;
  final String questionType;
  final List<String> options;
  final int correctOptionIndex;
  final String explanation;
  final bool hasLearningGate;
  final String? gateContentDomain;

  AiQuestionOutput({
    required this.questionText,
    required this.questionType,
    required this.options,
    required this.correctOptionIndex,
    required this.explanation,
    required this.hasLearningGate,
    this.gateContentDomain,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class TaikenAiService {
  // Key is injected at build time via --dart-define-from-file=.env
  // NEVER hardcode the real key here — .env is gitignored.
  static const String _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '', // empty → fails fast; real key comes from .env
  );
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.5-flash:generateContent';

  // ── Public entry point ─────────────────────────────────────────────────────

  Future<TaikenAiOutput> generateTaiken({
    required String topic,
    required String learningObjective,
    required String keyQuestions,
    required String difficulty,
    required String domain,
    int stageCount = 2,
  }) async {
    final prompt = _buildPrompt(
      topic: topic,
      learningObjective: learningObjective,
      keyQuestions: keyQuestions,
      difficulty: difficulty,
      domain: domain,
      stageCount: stageCount,
    );

    final raw = await _callGemini(prompt);
    return _parseResponse(raw);
  }

  // ── Gemini HTTP call (with exponential backoff retry) ─────────────────────

  static const _retryableStatuses = {503, 429};
  static const _maxAttempts = 4;

  Future<String> _callGemini(String prompt) async {
    final uri = Uri.parse('$_baseUrl?key=$_apiKey');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.7,
        'maxOutputTokens': 8192,
        'responseMimeType': 'application/json',
      },
    });

    for (int attempt = 1; attempt <= _maxAttempts; attempt++) {
      final response = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = decoded['candidates'] as List?;
        if (candidates == null || candidates.isEmpty) {
          throw Exception('Gemini returned no candidates');
        }
        final content = candidates.first['content'] as Map<String, dynamic>;
        final parts = content['parts'] as List;
        return parts.first['text'] as String;
      }

      // Retryable: 503 Service Unavailable / 429 Rate Limited
      if (_retryableStatuses.contains(response.statusCode) &&
          attempt < _maxAttempts) {
        final backoffSeconds = 1 << (attempt - 1); // 1s, 2s, 4s
        // Add small jitter (0–500 ms) to avoid thundering herd
        final jitterMs = (backoffSeconds * 100) % 500;
        await Future.delayed(
            Duration(seconds: backoffSeconds, milliseconds: jitterMs));
        continue;
      }

      throw Exception(
          'Gemini API error ${response.statusCode}: ${response.body}');
    }

    throw Exception('Gemini API failed after $_maxAttempts attempts');
  }

  // ── Prompt construction ────────────────────────────────────────────────────

  String _buildPrompt({
    required String topic,
    required String learningObjective,
    required String keyQuestions,
    required String difficulty,
    required String domain,
    required int stageCount,
  }) {
    final charList  = TaikenAssets.characters.join(', ');
    final bgList    = TaikenAssets.backgrounds.join(', ');
    final musicList = TaikenAssets.backgroundMusic.join(', ');

    return '''
You are a creative educational game designer building a "Taiken" — an interactive story-based learning experience.

TASK  
Generate a complete Taiken structure as a single JSON object (no markdown, no code fences, raw JSON only).

INPUTS
- Topic: $topic
- Learning objective: $learningObjective
- Key questions: $keyQuestions
- Difficulty: $difficulty  (must be one of: beginner, intermediate, advanced)
- Domain: $domain
- Number of stages: $stageCount

ASSET CONSTRAINTS — you MUST only use values from these lists:
- characters.assetKey: $charList
- stages.backgroundKey: $bgList
- stages.musicCue: $musicList
- dialogue.emotion: neutral, happy, angry, surprised, sad, thinking, determined
- dialogue.typewriterSpeed: slow, normal, fast, instant
- stage.mood: neutral, tense, happy, dramatic, mysterious, urgent
- stage.stageType: story, challenge, mixed
- question.questionType: multiple_choice, true_false

RULES
1. Generate exactly $stageCount stages.
2. Each stage must have 2–4 dialogues and 2–3 questions.
3. Choose 2–3 characters from the assetKey list.  At least one must be isPlayer:true.
4. Dialogues must reference character names that appear in the characters array.
5. For multiple_choice questions provide exactly 4 options; for true_false provide exactly 2 options ("True", "False").
6. correctOptionIndex is 0-based.
7. Set hasLearningGate:true for at most 1 question per stage when the concept is hard.
8. Make intro/outro scripts vivid, 2–3 sentences each.
9. All text must be educational, accurate, and engaging.
10. Do NOT generate any image URLs, audio URLs, or binary data.

OUTPUT FORMAT (strict — no extra keys, no comments):
{
  "title": "string",
  "description": "string (1–2 sentences)",
  "domain": "string",
  "difficulty": "beginner|intermediate|advanced",
  "introScript": "string",
  "outroSuccessScript": "string",
  "outroFailureScript": "string",
  "characters": [
    {
      "name": "string",
      "description": "string",
      "assetKey": "one of the character asset keys above",
      "side": "left|right",
      "isPlayer": true|false
    }
  ],
  "stages": [
    {
      "title": "string",
      "backgroundKey": "one of the background keys above",
      "mood": "neutral|tense|happy|dramatic|mysterious|urgent",
      "stageType": "story|challenge|mixed",
      "musicCue": "ambient|study|focus",
      "dialogues": [
        {
          "characterName": "must match a name in characters array",
          "text": "string",
          "emotion": "neutral|happy|angry|surprised|sad|thinking|determined",
          "typewriterSpeed": "slow|normal|fast|instant",
          "pauseAfterMs": 0
        }
      ],
      "questions": [
        {
          "questionText": "string",
          "questionType": "multiple_choice|true_false",
          "options": ["string", "string", "string", "string"],
          "correctOptionIndex": 0,
          "explanation": "string",
          "hasLearningGate": false,
          "gateContentDomain": null
        }
      ]
    }
  ]
}
''';
  }

  // ── JSON parsing & validation ──────────────────────────────────────────────

  TaikenAiOutput _parseResponse(String raw) {
    // Strip any accidental markdown code fences.
    final cleaned = raw
        .replaceAll(RegExp(r'```json\s*'), '')
        .replaceAll(RegExp(r'```\s*'), '')
        .trim();

    late Map<String, dynamic> json;
    try {
      json = jsonDecode(cleaned) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to parse Gemini JSON: $e\n\nRaw:\n$cleaned');
    }

    // ── Characters ────────────────────────────────────────────────────────────
    final rawChars = (json['characters'] as List?) ?? [];
    final characters = rawChars.map((c) {
      final m = c as Map<String, dynamic>;
      return AiCharacterOutput(
        name:        _str(m, 'name', 'Character'),
        description: _str(m, 'description', ''),
        assetKey:    TaikenAssets.validateCharacter(m['assetKey'] as String?),
        side:        (m['side'] as String?) == 'right'
            ? PortraitSide.right
            : PortraitSide.left,
        isPlayer:    (m['isPlayer'] as bool?) ?? false,
      );
    }).toList();

    if (characters.isEmpty) {
      characters.add(AiCharacterOutput(
        name: 'Alex', description: 'Your guide',
        assetKey: 'alex', side: PortraitSide.left, isPlayer: true,
      ));
    }

    // ── Stages ────────────────────────────────────────────────────────────────
    final rawStages = (json['stages'] as List?) ?? [];
    final stages = rawStages.map((s) {
      final sm = s as Map<String, dynamic>;

      final dialogues = ((sm['dialogues'] as List?) ?? []).map((d) {
        final dm = d as Map<String, dynamic>;
        return AiDialogueOutput(
          characterName:  _str(dm, 'characterName', characters.first.name),
          text:           _str(dm, 'text', ''),
          emotion:        DialogueEmotion.fromString(dm['emotion'] as String?),
          typewriterSpeed: TypewriterSpeed.fromString(
              dm['typewriterSpeed'] as String?),
          pauseAfterMs:   (dm['pauseAfterMs'] as num?)?.toInt() ?? 0,
        );
      }).toList();

      final questions = ((sm['questions'] as List?) ?? []).map((q) {
        final qm = q as Map<String, dynamic>;
        final rawOptions = (qm['options'] as List?)?.cast<String>() ?? [];
        final options = rawOptions.isEmpty
            ? ['Option A', 'Option B', 'Option C', 'Option D']
            : rawOptions;
        final correctIdx =
        ((qm['correctOptionIndex'] as num?)?.toInt() ?? 0)
            .clamp(0, options.length - 1);

        return AiQuestionOutput(
          questionText:      _str(qm, 'questionText', 'Question'),
          questionType:      _validateQType(qm['questionType'] as String?),
          options:           options,
          correctOptionIndex: correctIdx,
          explanation:       _str(qm, 'explanation', ''),
          hasLearningGate:   (qm['hasLearningGate'] as bool?) ?? false,
          gateContentDomain: qm['gateContentDomain'] as String?,
        );
      }).toList();

      return AiStageOutput(
        title:         _str(sm, 'title', 'Stage'),
        backgroundKey: TaikenAssets.validateBackground(
            sm['backgroundKey'] as String?),
        mood:          StageMood.fromString(sm['mood'] as String?),
        stageType:     StageType.fromString(sm['stageType'] as String?),
        musicCue:      TaikenAssets.validateMusic(sm['musicCue'] as String?),
        dialogues:     dialogues,
        questions:     questions,
      );
    }).toList();

    return TaikenAiOutput(
      title:               _str(json, 'title', 'Untitled Taiken'),
      description:         _str(json, 'description', ''),
      domain:              _str(json, 'domain', 'General'),
      difficulty:          _validateDifficulty(json['difficulty'] as String?),
      introScript:         _str(json, 'introScript', ''),
      outroSuccessScript:  _str(json, 'outroSuccessScript', ''),
      outroFailureScript:  _str(json, 'outroFailureScript', ''),
      characters:          characters,
      stages:              stages,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _str(Map<String, dynamic> m, String key, String fallback) =>
      (m[key] as String?)?.trim().isEmpty == false
          ? m[key] as String
          : fallback;

  String _validateDifficulty(String? v) =>
      ['beginner', 'intermediate', 'advanced'].contains(v) ? v! : 'beginner';

  String _validateQType(String? v) =>
      ['multiple_choice', 'true_false', 'decision'].contains(v)
          ? v!
          : 'multiple_choice';
}