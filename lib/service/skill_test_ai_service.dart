// =============================================================================
// skill_test_ai_service.dart
//
// Calls Gemini to generate a short skill-assessment quiz for the user's
// declared skills.  Uses the same HTTP+JSON pattern as TaikenAiService.
//
// Difficulty rules:
//   - Professional  → advanced
//   - Student       → intermediate
//   - Learner       → beginner (easy)
//
// Output: SkillTestOutput — one SkillQuestionGroup per skill, each containing
//   3-5 questions.  Questions are multiple_choice or true_false.
//
// Nothing here writes to the database; that is done by SkillTestNotifier.
// =============================================================================

import 'dart:convert';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Output model
// ─────────────────────────────────────────────────────────────────────────────

class SkillTestOutput {
  final List<SkillQuestionGroup> groups;
  const SkillTestOutput({required this.groups});
}

class SkillQuestionGroup {
  final String skillName;
  final List<SkillQuestion> questions;
  const SkillQuestionGroup({required this.skillName, required this.questions});
}

class SkillQuestion {
  final String questionText;
  final String questionType; // 'multiple_choice' | 'true_false'
  final List<String> options;
  final int correctOptionIndex;
  final String explanation;

  const SkillQuestion({
    required this.questionText,
    required this.questionType,
    required this.options,
    required this.correctOptionIndex,
    required this.explanation,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

class SkillTestAiService {
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

  Future<SkillTestOutput> generateTest({
    required List<String> skills,
    required String difficulty, // 'beginner' | 'intermediate' | 'advanced'
    int questionsPerSkill = 4,
  }) async {
    final prompt = _buildPrompt(
      skills: skills,
      difficulty: difficulty,
      questionsPerSkill: questionsPerSkill,
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
        'temperature': 0.6,
        'maxOutputTokens': 6000,
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
    required List<String> skills,
    required String difficulty,
    required int questionsPerSkill,
  }) {
    final skillList = skills.map((s) => '"$s"').join(', ');

    return '''
You are an expert skill assessor for an educational platform called Plaro.

TASK
Generate a skill assessment quiz as a single JSON object (raw JSON only, no markdown, no code fences).

INPUTS
- Skills to assess: [$skillList]
- Difficulty level: $difficulty  (must be one of: beginner, intermediate, advanced)
- Questions per skill: $questionsPerSkill

RULES
1. Generate exactly one group per skill, in the same order as the input skill list.
2. Each group must contain exactly $questionsPerSkill questions.
3. Mix question types: prefer multiple_choice (70 %) and true_false (30 %).
4. For multiple_choice: provide exactly 4 options.
5. For true_false: provide exactly 2 options — "True" and "False" (in that order).
6. correctOptionIndex is 0-based.
7. The difficulty MUST match "$difficulty":
   - beginner → basic definitions, recall questions, foundational concepts
   - intermediate → application, comparison, typical use-cases
   - advanced → edge-cases, tradeoffs, senior-level reasoning
8. Questions must be concise (max 2 sentences), accurate, and unambiguous.
9. Explanations must be 1-2 sentences and genuinely informative.
10. Do NOT repeat the same question across different skills.
11. Output MUST be raw JSON matching the schema below exactly.

OUTPUT SCHEMA (strict — no extra keys, no comments):
{
  "groups": [
    {
      "skillName": "string — must match the input skill name exactly",
      "questions": [
        {
          "questionText": "string",
          "questionType": "multiple_choice | true_false",
          "options": ["string", "string", "string", "string"],
          "correctOptionIndex": 0,
          "explanation": "string"
        }
      ]
    }
  ]
}
''';
  }

  // ── JSON parsing & validation ──────────────────────────────────────────────

  SkillTestOutput _parseResponse(String raw) {
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

    final rawGroups = (json['groups'] as List?) ?? [];
    final groups = rawGroups.map((g) {
      final gm = g as Map<String, dynamic>;
      final rawQuestions = (gm['questions'] as List?) ?? [];
      final questions = rawQuestions.map((q) {
        final qm = q as Map<String, dynamic>;
        final rawOptions = (qm['options'] as List?)?.cast<String>() ?? [];
        final options = rawOptions.isEmpty
            ? ['Option A', 'Option B', 'Option C', 'Option D']
            : rawOptions;
        final correctIdx =
            ((qm['correctOptionIndex'] as num?)?.toInt() ?? 0)
                .clamp(0, options.length - 1);
        return SkillQuestion(
          questionText: _str(qm, 'questionText', 'Question'),
          questionType: _validateQType(qm['questionType'] as String?),
          options: options,
          correctOptionIndex: correctIdx,
          explanation: _str(qm, 'explanation', ''),
        );
      }).toList();

      return SkillQuestionGroup(
        skillName: _str(gm, 'skillName', 'Skill'),
        questions: questions,
      );
    }).toList();

    return SkillTestOutput(groups: groups);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _str(Map<String, dynamic> m, String key, String fallback) =>
      (m[key] as String?)?.trim().isEmpty == false
          ? m[key] as String
          : fallback;

  String _validateQType(String? v) =>
      ['multiple_choice', 'true_false'].contains(v) ? v! : 'multiple_choice';
}