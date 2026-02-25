import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:ui';
import '../ViewModel/taiken_experience_provider.dart';
import '../ViewModel/streak_provider.dart'; // ✅ NEW
import '../Model/taiken.dart';
import 'widgets/streak_widgets.dart'; // ✅ NEW — StreakBadge, MilestoneToastListener

class TaikenExperiencePage extends ConsumerStatefulWidget {
  final String taikenId;

  const TaikenExperiencePage({super.key, required this.taikenId});

  @override
  ConsumerState<TaikenExperiencePage> createState() =>
      _TaikenExperiencePageState();
}

class _TaikenExperiencePageState extends ConsumerState<TaikenExperiencePage>
    with SingleTickerProviderStateMixin {
  int? _selectedAnswerIndex;
  bool _showExplanation = false;
  int _visibleDialoguesCount = 0;
  bool _isAdvancingDialogue = false;
  late AnimationController _xpAnimationController;
  late Animation<double> _xpAnimation;
  double _currentXP = 100.0;
  final ScrollController _dialogueScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _xpAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _xpAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _xpAnimationController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taikenExperienceProvider(widget.taikenId).notifier).loadTaiken();
    });
  }

  @override
  void dispose() {
    _dialogueScrollController.dispose();
    _xpAnimationController.dispose();
    super.dispose();
  }

  void _updateXPBar(TaikenExperienceState state) {
    if (state.taiken == null || state.progress == null) return;

    final totalQuestions = state.taiken!.totalQuestions;
    final wrongAnswers = state.progress!.wrongAnswers;

    final xpLossPerWrong = 100.0 / (totalQuestions / 2);
    final newXP = (100.0 - (wrongAnswers * xpLossPerWrong)).clamp(0.0, 100.0);

    _xpAnimation = Tween<double>(
      begin: _currentXP / 100.0,
      end: newXP / 100.0,
    ).animate(
      CurvedAnimation(parent: _xpAnimationController, curve: Curves.easeInOut),
    );

    _currentXP = newXP;
    _xpAnimationController.forward(from: 0.0);
  }

  void _showNextDialogue(int totalDialogues) {
    if (_isAdvancingDialogue) return;

    if (_visibleDialoguesCount < totalDialogues) {
      setState(() {
        _isAdvancingDialogue = true;
        _visibleDialoguesCount++;
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_dialogueScrollController.hasClients) {
          _dialogueScrollController.animateTo(
            _dialogueScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
        if (mounted) {
          setState(() => _isAdvancingDialogue = false);
        }
      });
    }
  }

  Future<void> _handleTryAgain() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resetting taiken...'),
          duration: Duration(seconds: 1),
        ),
      );

      await ref
          .read(taikenExperienceProvider(widget.taikenId).notifier)
          .resetAndRestart();

      if (mounted) {
        setState(() {
          _currentXP = 100.0;
          _selectedAnswerIndex = null;
          _showExplanation = false;
          _visibleDialoguesCount = 0;
          _isAdvancingDialogue = false;
        });

        if (_dialogueScrollController.hasClients) {
          _dialogueScrollController.jumpTo(0);
        }

        _xpAnimationController.reset();
        _xpAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _xpAnimationController,
            curve: Curves.easeInOut,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taikenExperienceProvider(widget.taikenId));

    // ✅ MilestoneToastListener catches newMilestoneProvider changes anywhere
    // in this subtree and shows the 🏆 SnackBar automatically.
    return MilestoneToastListener(child: _buildContent(state));
  }

  Widget _buildContent(TaikenExperienceState state) {
    if (state.isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (state.error != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
          title: const Text('Error'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  state.error!,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.taiken == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: Text('Taiken not found')),
      );
    }

    if (state.showingIntro) return _buildIntroScreen(state);
    if (state.showingOutro) return _buildOutroScreen(state);
    return _buildExperienceScreen(state);
  }

  // ── Intro (unchanged + streak hint) ─────────────────────────────────────────

  Widget _buildIntroScreen(TaikenExperienceState state) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (state.taiken!.thumbnailUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    state.taiken!.thumbnailUrl!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder:
                        (context, error, stackTrace) => Container(
                          height: 200,
                          color: Colors.grey[800],
                          child: const Icon(
                            Icons.image_not_supported,
                            size: 64,
                          ),
                        ),
                  ),
                ),
              const SizedBox(height: 32),
              Text(
                state.taiken!.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TypewriterText(
                  text: state.taiken!.introScript,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              _buildInfoRow(
                Icons.layers,
                '${state.taiken!.totalStages} Stages',
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.quiz,
                '${state.taiken!.totalQuestions} Questions',
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.check_circle,
                'Pass: ${state.taiken!.passThreshold}% correct',
              ),

              // ✅ Streak hint
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFFF6B35).withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const StreakBadge(size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Completing each stage extends your streak!',
                      style: TextStyle(color: Colors.grey[300], fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    ref
                        .read(
                          taikenExperienceProvider(widget.taikenId).notifier,
                        )
                        .startExperience();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Start Experience',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: Colors.blue, size: 20),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14)),
      ],
    );
  }

  // ── Outro (unchanged + streak result card + Plaro points row) ────────────────

  Widget _buildOutroScreen(TaikenExperienceState state) {
    final isPassed = state.progress!.status == 'completed';
    final accuracy = state.progress!.accuracyPercentage;

    // ✅ Read live streak state — updated ~300 ms after stage completion fires
    final currentStreak = ref.watch(currentStreakProvider);
    final isStreakActive = ref.watch(isStreakActiveTodayProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              Icon(
                isPassed ? Icons.check_circle : Icons.cancel,
                size: 100,
                color: isPassed ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                isPassed ? 'Congratulations!' : 'Taiken Failed',
                style: TextStyle(
                  color: isPassed ? Colors.green : Colors.red,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TypewriterText(
                  text:
                      isPassed
                          ? state.taiken!.outroSuccessScript
                          : state.taiken!.outroFailureScript,
                  style: TextStyle(
                    color: Colors.grey[300],
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),
              _buildResultStat(
                'Accuracy',
                '${accuracy.toStringAsFixed(1)}%',
                isPassed ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 12),
              _buildResultStat(
                'Correct Answers',
                '${state.progress!.correctAnswers}/${state.progress!.questionsAnswered}',
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _buildResultStat(
                'Final XP',
                '${_currentXP.toStringAsFixed(0)}%',
                _currentXP > 50 ? Colors.green : Colors.orange,
              ),

              // ✅ Streak result
              const SizedBox(height: 12),
              _buildStreakResultCard(
                isPassed: isPassed,
                currentStreak: currentStreak,
                isStreakActive: isStreakActive,
              ),

              // ✅ Plaro points earned (only on pass)
              if (isPassed) ...[
                const SizedBox(height: 12),
                _buildResultStat('Plaro Points', '+5 pts', Colors.amber),
              ],

              const SizedBox(height: 32),
              Text(
                'Rate this Taiken',
                style: TextStyle(color: Colors.grey[400], fontSize: 16),
              ),
              const SizedBox(height: 12),
              _buildRatingStars(state),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back to Taikens',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (!isPassed) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _handleTryAgain,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.white),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Try Again',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ NEW — streak summary on the results screen
  Widget _buildStreakResultCard({
    required bool isPassed,
    required int currentStreak,
    required bool isStreakActive,
  }) {
    const orange = Color(0xFFFF6B35);
    final color = isStreakActive ? orange : Colors.grey.shade700;
    final label =
        isStreakActive
            ? '$currentStreak day streak 🔥'
            : 'Complete a stage to start your streak';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_rounded, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isStreakActive ? Colors.white : Colors.grey[500],
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultStat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingStars(TaikenExperienceState state) {
    final existingRating = state.userRating ?? 0;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        int selectedRating = existingRating;
        bool isSubmitted = existingRating > 0;

        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                final isFilled = starIndex <= selectedRating;

                return IconButton(
                  icon: Icon(
                    isFilled ? Icons.star : Icons.star_border,
                    color: Colors.amber,
                    size: 32,
                  ),
                  onPressed:
                      isSubmitted
                          ? null
                          : () async {
                            setLocalState(() => selectedRating = starIndex);
                            await ref
                                .read(
                                  taikenExperienceProvider(
                                    widget.taikenId,
                                  ).notifier,
                                )
                                .rateTaiken(starIndex, null);
                            setLocalState(() => isSubmitted = true);
                          },
                );
              }),
            ),
            const SizedBox(height: 8),
            if (isSubmitted)
              Text(
                'Thank you for rating!',
                style: TextStyle(color: Colors.green[400], fontSize: 14),
              ),
          ],
        );
      },
    );
  }

  // ── Experience screen (unchanged + StreakBadge in AppBar) ────────────────────

  Widget _buildExperienceScreen(TaikenExperienceState state) {
    final hasDialogues = state.currentDialogues.isNotEmpty;
    final hasQuestions = state.currentQuestions.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Stage ${state.currentStageIndex + 1}/${state.stages.length}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
        actions: [
          // ✅ Live streak badge
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const StreakBadge(size: 15),
              ),
            ),
          ),
          // XP pill (unchanged)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      color: _currentXP > 50 ? Colors.red : Colors.grey,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentXP.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: _currentXP > 50 ? Colors.red : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Blurred background image
          if (state.currentStage?.sceneImageUrl != null)
            Positioned.fill(
              child: Stack(
                children: [
                  Image.network(
                    state.currentStage!.sceneImageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder:
                        (context, error, stackTrace) =>
                            Container(color: Colors.grey[900]),
                  ),
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                    child: Container(color: Colors.black.withOpacity(0.5)),
                  ),
                ],
              ),
            )
          else
            Positioned.fill(child: Container(color: Colors.grey[900])),

          // Main image (non-blurred center)
          if (state.currentStage?.sceneImageUrl != null)
            Positioned.fill(
              child: Center(
                child: Image.network(
                  state.currentStage!.sceneImageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder:
                      (context, error, stackTrace) => const SizedBox(),
                ),
              ),
            ),

          // Gradient overlay
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.3),
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                _buildXPBar(state),
                _buildProgressBar(state),
                Expanded(
                  child:
                      hasDialogues && state.hasMoreDialogues
                          ? _buildDialogueSection(state)
                          : hasQuestions && state.hasMoreQuestions
                          ? _buildQuestionSection(state)
                          : const Center(
                            child: Text(
                              'No content',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── XP bar (unchanged) ───────────────────────────────────────────────────────

  Widget _buildXPBar(TaikenExperienceState state) {
    return AnimatedBuilder(
      animation: _xpAnimation,
      builder: (context, child) {
        final xpValue = _xpAnimation.value;
        Color xpColor;
        if (xpValue > 0.7) {
          xpColor = Colors.green;
        } else if (xpValue > 0.4) {
          xpColor = Colors.orange;
        } else {
          xpColor = Colors.red;
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.favorite, color: xpColor, size: 16),
                      const SizedBox(width: 4),
                      const Text(
                        'XP Health',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(xpValue * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: xpColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: xpValue,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [xpColor, xpColor.withOpacity(0.7)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Progress bar (unchanged) ─────────────────────────────────────────────────

  Widget _buildProgressBar(TaikenExperienceState state) {
    final totalQuestions = state.taiken!.totalQuestions;
    final answered = state.progress!.questionsAnswered;
    final progress = answered / totalQuestions;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress: $answered/$totalQuestions',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'Accuracy: ${state.progress!.accuracyPercentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color:
                      state.progress!.accuracyPercentage >=
                              state.taiken!.passThreshold
                          ? Colors.green
                          : Colors.orange,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(
                progress >= (state.taiken!.passThreshold / 100)
                    ? Colors.green
                    : Colors.orange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialogue section (unchanged) ─────────────────────────────────────────────

  Widget _buildDialogueSection(TaikenExperienceState state) {
    final dialogues = state.currentDialogues;

    if (_visibleDialoguesCount == 0 && dialogues.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visibleDialoguesCount == 0) {
          setState(() => _visibleDialoguesCount = 1);
        }
      });
    }

    return GestureDetector(
      onTap:
          _isAdvancingDialogue
              ? null
              : () => _showNextDialogue(dialogues.length),
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _dialogueScrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ...List.generate(
                    _visibleDialoguesCount.clamp(0, dialogues.length),
                    (index) {
                      if (index >= dialogues.length) return const SizedBox();
                      final dialogue = dialogues[index];
                      final character = state.characters.firstWhere(
                        (c) => c.characterId == dialogue.characterId,
                        orElse:
                            () => TaikenCharacter(
                              characterId: '',
                              taikenId: '',
                              characterName: 'Narrator',
                              displayOrder: -1,
                              createdAt: DateTime.now(),
                            ),
                      );
                      return _buildAnimatedDialogueCard(
                        dialogue,
                        character,
                        index,
                      );
                    },
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.8)),
            child: Column(
              children: [
                if (_visibleDialoguesCount < dialogues.length)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.touch_app,
                          color: Colors.grey[600],
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Tap anywhere to continue • $_visibleDialoguesCount/${dialogues.length}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_visibleDialoguesCount >= dialogues.length)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _visibleDialoguesCount = 0;
                          _selectedAnswerIndex = null;
                          _showExplanation = false;
                        });
                        ref
                            .read(
                              taikenExperienceProvider(
                                widget.taikenId,
                              ).notifier,
                            )
                            .advanceDialogue();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Continue to Questions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedDialogueCard(
    TaikenDialogue dialogue,
    TaikenCharacter character,
    int index,
  ) {
    final isNarrator = character.characterName == 'Narrator';
    final isLeftAligned = index % 2 == 0;

    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutBack,
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        final clampedValue = value.clamp(0.0, 1.0);
        return Transform.scale(
          scale: clampedValue,
          alignment:
              isLeftAligned ? Alignment.centerLeft : Alignment.centerRight,
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment:
              isLeftAligned ? MainAxisAlignment.start : MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isLeftAligned && !isNarrator)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage:
                      character.characterImageUrl != null
                          ? NetworkImage(character.characterImageUrl!)
                          : null,
                  backgroundColor: Colors.grey[800],
                  child:
                      character.characterImageUrl == null
                          ? const Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.white,
                          )
                          : null,
                ),
              ),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      isNarrator
                          ? Colors.grey[900]?.withOpacity(0.9)
                          : isLeftAligned
                          ? Colors.blue[900]?.withOpacity(0.9)
                          : Colors.green[900]?.withOpacity(0.9),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft:
                        isLeftAligned ? Radius.zero : const Radius.circular(16),
                    bottomRight:
                        isLeftAligned ? const Radius.circular(16) : Radius.zero,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      character.characterName,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TypewriterText(
                      text: dialogue.dialogueText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isLeftAligned && !isNarrator)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage:
                      character.characterImageUrl != null
                          ? NetworkImage(character.characterImageUrl!)
                          : null,
                  backgroundColor: Colors.grey[800],
                  child:
                      character.characterImageUrl == null
                          ? const Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.white,
                          )
                          : null,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Question section (unchanged) ─────────────────────────────────────────────

  Widget _buildQuestionSection(TaikenExperienceState state) {
    final question = state.currentQuestions[state.currentQuestionIndex];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue, width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.quiz, color: Colors.blue, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: TypewriterText(
                    text: question.questionText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(
            question.options.length,
            (index) => _buildOptionButton(
              question.options[index],
              index,
              question,
              state,
            ),
          ),
          if (_showExplanation && question.explanation != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900]?.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[300],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Explanation',
                        style: TextStyle(
                          color: Colors.blue[300],
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    question.explanation!,
                    style: TextStyle(
                      color: Colors.grey[300],
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_selectedAnswerIndex != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedAnswerIndex = null;
                    _showExplanation = false;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionButton(
    String option,
    int index,
    TaikenQuestion question,
    TaikenExperienceState state,
  ) {
    final isSelected = _selectedAnswerIndex == index;
    final isCorrect = index == question.correctOptionIndex;
    final showResult = _selectedAnswerIndex != null;

    Color backgroundColor;
    Color borderColor;
    Color textColor;

    if (showResult) {
      if (isCorrect) {
        backgroundColor = Colors.green.withOpacity(0.3);
        borderColor = Colors.green;
        textColor = Colors.green;
      } else if (isSelected) {
        backgroundColor = Colors.red.withOpacity(0.3);
        borderColor = Colors.red;
        textColor = Colors.red;
      } else {
        backgroundColor = Colors.grey[900]!.withOpacity(0.5);
        borderColor = Colors.grey[700]!;
        textColor = Colors.grey[400]!;
      }
    } else {
      backgroundColor =
          isSelected
              ? Colors.blue.withOpacity(0.3)
              : Colors.grey[900]!.withOpacity(0.7);
      borderColor = isSelected ? Colors.blue : Colors.grey[700]!;
      textColor = isSelected ? Colors.blue : Colors.white;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap:
            _selectedAnswerIndex == null
                ? () async {
                  setState(() {
                    _selectedAnswerIndex = index;
                    _showExplanation = true;
                  });
                  await ref
                      .read(taikenExperienceProvider(widget.taikenId).notifier)
                      .submitAnswer(question.questionId, index);

                  _updateXPBar(
                    ref.read(taikenExperienceProvider(widget.taikenId)),
                  );
                }
                : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor, width: 2),
                  color:
                      isSelected || (showResult && isCorrect)
                          ? borderColor
                          : Colors.transparent,
                ),
                child:
                    showResult && isCorrect
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : showResult && isSelected && !isCorrect
                        ? const Icon(Icons.close, size: 16, color: Colors.white)
                        : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  option,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// ✨ TYPEWRITER TEXT WIDGET
// Reveals text character-by-character like a retro JRPG dialogue system
// ============================================

class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  final TextAlign? textAlign;

  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 30),
    this.textAlign,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = '';
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAnimation();
  }

  @override
  void didUpdateWidget(TypewriterText oldWidget) {
    if (oldWidget.text != widget.text) {
      _displayedText = '';
      _currentIndex = 0;
      _timer?.cancel();
      _startAnimation();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _startAnimation() {
    _timer = Timer.periodic(widget.duration, (timer) {
      if (_currentIndex < widget.text.length) {
        if (mounted) {
          setState(() {
            _displayedText += widget.text[_currentIndex];
            _currentIndex++;
          });
        }
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style,
      textAlign: widget.textAlign,
    );
  }
}
