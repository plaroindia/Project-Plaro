// =============================================================================
// skill_test_page.dart
//
// Full-screen skill assessment page.
//
// Entry point: SkillTestPage(skills: [...], userRole: '...')
//
// Flow:
//   1. Generating screen  — spinner while Gemini builds the quiz
//   2. Question screen    — one question at a time with animated feedback
//   3. Results screen     — per-skill confidence cards + overall summary
//
// The test cannot be failed.  Feedback is always constructive.
// No BACK navigation during the quiz to keep the experience intentional.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../viewmodels/skill_test_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry widget
// ─────────────────────────────────────────────────────────────────────────────

class SkillTestPage extends ConsumerStatefulWidget {
  final List<String> skills;
  final String userRole; // 'Professional' | 'Student' | 'Learner'
  final VoidCallback? onCompleted; // called after results are shown & dismissed

  const SkillTestPage({
    super.key,
    required this.skills,
    required this.userRole,
    this.onCompleted,
  });

  @override
  ConsumerState<SkillTestPage> createState() => _SkillTestPageState();
}

class _SkillTestPageState extends ConsumerState<SkillTestPage> {
  @override
  void initState() {
    super.initState();
    // Kick off generation on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(skillTestProvider.notifier).generateTest(
            skills: widget.skills,
            userRole: widget.userRole,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(skillTestProvider);

    return PopScope(
      canPop: state.phase == SkillTestPhase.idle ||
          state.phase == SkillTestPhase.completed ||
          state.phase == SkillTestPhase.error,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildPhase(state),
        ),
      ),
    );
  }

  Widget _buildPhase(SkillTestState state) {
    switch (state.phase) {
      case SkillTestPhase.generating:
        return _GeneratingScreen(
          key: const ValueKey('generating'),
          userRole: widget.userRole,
          skillCount: widget.skills.length,
        );
      case SkillTestPhase.inProgress:
        return _QuestionScreen(
          key: ValueKey(
              'q_${state.currentGroupIndex}_${state.currentQuestionIndex}'),
          state: state,
        );
      case SkillTestPhase.submitting:
        return _SubmittingScreen(key: const ValueKey('submitting'));
      case SkillTestPhase.completed:
        return _ResultsScreen(
          key: const ValueKey('results'),
          state: state,
          userRole: widget.userRole,
          onDone: () {
            ref.read(skillTestProvider.notifier).reset();
            widget.onCompleted?.call();
            if (mounted) Navigator.of(context).pop();
          },
        );
      case SkillTestPhase.error:
        return _ErrorScreen(
          key: const ValueKey('error'),
          message: state.error ?? 'Something went wrong.',
          onRetry: () {
            ref.read(skillTestProvider.notifier).generateTest(
                  skills: widget.skills,
                  userRole: widget.userRole,
                );
          },
          onBack: () {
            ref.read(skillTestProvider.notifier).reset();
            Navigator.of(context).pop();
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Generating screen
// ─────────────────────────────────────────────────────────────────────────────

class _GeneratingScreen extends StatelessWidget {
  final String userRole;
  final int skillCount;

  const _GeneratingScreen({
    super.key,
    required this.userRole,
    required this.skillCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final difficulty = _difficultyLabel(userRole);

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_outlined,
                    size: 56, color: Colors.blue),
              ),
              const SizedBox(height: 32),
              Text(
                'Building Your Skill Assessment',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Crafting $skillCount personalised skill check${skillCount == 1 ? '' : 's'} at $difficulty difficulty…',
                style: TextStyle(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              const CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 24),
              _InfoChip(label: 'Takes about 10–15 seconds'),
            ],
          ),
        ),
      ),
    );
  }

  String _difficultyLabel(String role) {
    switch (role.toLowerCase()) {
      case 'professional':
        return 'Advanced';
      case 'student':
        return 'Intermediate';
      default:
        return 'Beginner';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Question screen
// ─────────────────────────────────────────────────────────────────────────────

class _QuestionScreen extends ConsumerWidget {
  final SkillTestState state;
  const _QuestionScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final group = state.currentGroup!;
    final question = state.currentQuestion!;
    final selected = state.selectedAnswerForCurrent;
    final answered = state.hasAnsweredCurrent;

    final progress = state.totalQuestions == 0
        ? 0.0
        : state.overallQuestionNumber / state.totalQuestions;

    return SafeArea(
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        group.skillName,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${state.overallQuestionNumber} / ${state.totalQuestions}',
                      style: TextStyle(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    backgroundColor:
                        isDark ? Colors.grey[800] : Colors.grey[200],
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
              ],
            ),
          ),

          // ── Question ────────────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    question.questionText,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Options ──────────────────────────────────────────
                  ...List.generate(question.options.length, (idx) {
                    return _OptionTile(
                      label: question.options[idx],
                      index: idx,
                      selected: selected == idx,
                      answered: answered,
                      correctIndex: question.correctOptionIndex,
                      onTap: answered
                          ? null
                          : () => ref
                              .read(skillTestProvider.notifier)
                              .selectAnswer(idx),
                    );
                  }),

                  // ── Explanation (shown after answering) ───────────────
                  if (answered) ...[
                    const SizedBox(height: 16),
                    _ExplanationCard(
                      isCorrect: selected == question.correctOptionIndex,
                      explanation: question.explanation,
                    ),
                    const SizedBox(height: 8),
                  ],

                  const SizedBox(height: 80), // space for button
                ],
              ),
            ),
          ),

          // ── Continue button ─────────────────────────────────────────────
          if (answered)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: ElevatedButton(
                onPressed: () =>
                    ref.read(skillTestProvider.notifier).nextQuestion(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  state.isLastQuestion ? 'See My Results' : 'Continue',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Option tile
// ─────────────────────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final String label;
  final int index;
  final bool selected;
  final bool answered;
  final int correctIndex;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.label,
    required this.index,
    required this.selected,
    required this.answered,
    required this.correctIndex,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color borderColor;
    Color bgColor;
    Color textColor;
    Widget? trailingIcon;

    if (!answered) {
      borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;
      bgColor = isDark ? Colors.grey[850]! : Colors.grey[50]!;
      textColor = Theme.of(context).colorScheme.onSurface;
    } else if (index == correctIndex) {
      borderColor = Colors.green;
      bgColor = Colors.green.withOpacity(0.1);
      textColor = Colors.green;
      trailingIcon =
          const Icon(Icons.check_circle, color: Colors.green, size: 20);
    } else if (selected && index != correctIndex) {
      borderColor = Colors.red;
      bgColor = Colors.red.withOpacity(0.08);
      textColor = Colors.red;
      trailingIcon =
          const Icon(Icons.cancel, color: Colors.red, size: 20);
    } else {
      borderColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
      bgColor = Colors.transparent;
      textColor = isDark ? Colors.grey[500]! : Colors.grey[400]!;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontWeight:
                      (answered && index == correctIndex)
                          ? FontWeight.w600
                          : FontWeight.normal,
                ),
              ),
            ),
            if (trailingIcon != null) trailingIcon,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Explanation card
// ─────────────────────────────────────────────────────────────────────────────

class _ExplanationCard extends StatelessWidget {
  final bool isCorrect;
  final String explanation;

  const _ExplanationCard({
    required this.isCorrect,
    required this.explanation,
  });

  @override
  Widget build(BuildContext context) {
    final color = isCorrect ? Colors.green : Colors.orange;
    final icon = isCorrect ? Icons.lightbulb : Icons.school_outlined;
    final headline = isCorrect ? 'Well done!' : 'Good to know';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  explanation,
                  style: TextStyle(
                    color: color.withOpacity(0.9),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Submitting screen
// ─────────────────────────────────────────────────────────────────────────────

class _SubmittingScreen extends StatelessWidget {
  const _SubmittingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 20),
          Text(
            'Calculating your skill profile…',
            style: TextStyle(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Results screen
// ─────────────────────────────────────────────────────────────────────────────

class _ResultsScreen extends StatelessWidget {
  final SkillTestState state;
  final String userRole;
  final VoidCallback onDone;

  const _ResultsScreen({
    super.key,
    required this.state,
    required this.userRole,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final results = state.results ?? [];

    // Overall average
    final avgConfidence = results.isEmpty
        ? 0.0
        : results.map((r) => r.confidenceScore).reduce((a, b) => a + b) /
            results.length;

    final overallLabel = SkillResult.compute(
      skillName: '',
      correct: 0,
      total: 0,
      selfConfidence: null,
      blendRatio: 0,
    ).label; // static-ish, just use the avg to build label manually

    final overallLevelLabel = _labelFromScore(avgConfidence);
    final overallColor = _colorForScore(avgConfidence);

    return SafeArea(
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: overallColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.emoji_events_outlined,
                      size: 48, color: overallColor),
                ),
                const SizedBox(height: 16),
                Text(
                  'Assessment Complete!',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Text(
                  'Your skill profile has been calibrated.',
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                // Overall badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: overallColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: overallColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    'Overall: $overallLevelLabel  •  ${(avgConfidence * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: overallColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Per-skill cards ──────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              itemCount: results.length,
              itemBuilder: (context, idx) {
                final r = results[idx];
                return _SkillResultCard(result: r);
              },
            ),
          ),

          // ── Note + CTA ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Column(
              children: [
                if (state.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: Colors.orange, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Results could not be synced. They will be saved next time.',
                            style: const TextStyle(
                                color: Colors.orange, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Text(
                  'These results help Plaro personalise your learning journey. You can retake skill tests anytime.',
                  style: TextStyle(
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: onDone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Continue to Plaro',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _labelFromScore(double score) {
    if (score >= 0.80) return 'Advanced';
    if (score >= 0.60) return 'Proficient';
    if (score >= 0.35) return 'Developing';
    return 'Beginner';
  }

  Color _colorForScore(double score) {
    if (score >= 0.80) return Colors.purple;
    if (score >= 0.60) return Colors.green;
    if (score >= 0.35) return Colors.orange;
    return Colors.blue;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skill result card
// ─────────────────────────────────────────────────────────────────────────────

class _SkillResultCard extends StatelessWidget {
  final SkillResult result;
  const _SkillResultCard({required this.result});

  Color get _color {
    if (result.confidenceScore >= 0.80) return Colors.purple;
    if (result.confidenceScore >= 0.60) return Colors.green;
    if (result.confidenceScore >= 0.35) return Colors.orange;
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  result.skillName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  result.label,
                  style: TextStyle(
                    color: _color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Confidence bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: result.confidenceScore,
                    minHeight: 6,
                    backgroundColor:
                        isDark ? Colors.grey[800] : Colors.grey[200],
                    valueColor:
                        AlwaysStoppedAnimation<Color>(_color),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(result.confidenceScore * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: _color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${result.correct}/${result.total} correct in the test',
            style: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error screen
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _ErrorScreen({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.orange),
            const SizedBox(height: 24),
            const Text(
              'Something went wrong',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 13),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Try Again'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onBack,
              child: const Text('Go Back',
                  style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  const _InfoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          fontSize: 13,
        ),
      ),
    );
  }
}