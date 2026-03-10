// =============================================================================
// taiken_experience_page.dart  — FINAL  (B + C + D + E combined)
//
// What this file contains vs the Phase A stub:
//
//  PHASE B — Visual Novel engine
//    • Full-screen blurred background with sharp centre image overlay
//    • Left / right character portrait system
//      – portrait_url_talking shown while that character's bubble typewriters
//      – dimmed + slightly scaled-down when not speaking
//    • Per-bubble typewriter with configurable speed (TypewriterSpeed enum)
//    • Blinking cursor during typewriting
//    • First tap = skip animation; second tap = advance to next bubble
//    • pauseAfterMs respected between bubbles (dramatic pause)
//    • Stacked bubble history scrollable inside dark bottom panel
//    • Mood-based accent colour and tint overlay (tense/dramatic/mysterious…)
//    • Stage title cinematic reveal on each stage entry
//
//  PHASE C — Gate interstitial (full-screen, not modal)
//    • Domain badge + question preview text
//    • "Learn First →" navigates to _TaikenLearningPageStub
//      (replace stub import with real TaikenLearningPage when built)
//    • "I already know this" locked behind animated countdown
//    • Gate countdown driven by gateSkipDelaySeconds from DB
//
//  PHASE D — Outro / result card
//    • Score count-up animation via AnimationController
//    • RepaintBoundary shareable card (share_plus + path_provider)
//    • Badge display with icon, name, dynamic colour from DB hex
//    • Next-episode teaser with thumbnail and "Continue Story →" CTA
//    • Inline star rating (persisted via provider)
//    • Streak status row
//    • Try Again / Back to Taikens CTAs
//
//  PHASE E — List / series integration hooks
//    • Episode badge on intro screen
//    • Character avatar strip on intro screen
//    • Domain + difficulty chips throughout
//    • Pass-threshold marker line on progress bar
//
//  No changes to taiken.dart or taiken_experience_provider.dart are required.
//  The provider's model + API are already final from Phase A.
//
//  pubspec.yaml dependencies needed (add if not present):
//    share_plus: ^7.0.0
//    path_provider: ^2.1.0
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../Model/taiken.dart';
import '../ViewModel/taiken_experience_provider.dart';
import '../ViewModel/streakandpoints_provider.dart';
import 'widgets/streak_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mood → visual mapping  (extension on enum from model)
// ─────────────────────────────────────────────────────────────────────────────

extension _MoodTheme on StageMood {
  Color get tintColor {
    switch (this) {
      case StageMood.tense:      return const Color(0xFFFF0000).withOpacity(0.14);
      case StageMood.dramatic:   return const Color(0xFF9B00FF).withOpacity(0.14);
      case StageMood.mysterious: return const Color(0xFF3A00CC).withOpacity(0.14);
      case StageMood.urgent:     return const Color(0xFFFF6B00).withOpacity(0.14);
      case StageMood.happy:      return const Color(0xFFFFD700).withOpacity(0.08);
      case StageMood.neutral:    return Colors.transparent;
    }
  }

  Color get accent {
    switch (this) {
      case StageMood.tense:      return const Color(0xFFFF5252);
      case StageMood.dramatic:   return const Color(0xFFCE93D8);
      case StageMood.mysterious: return const Color(0xFF7986CB);
      case StageMood.urgent:     return const Color(0xFFFFB74D);
      case StageMood.happy:      return const Color(0xFFFFD54F);
      case StageMood.neutral:    return const Color(0xFF64B5F6);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class TaikenExperiencePage extends ConsumerStatefulWidget {
  final String taikenId;
  const TaikenExperiencePage({super.key, required this.taikenId});

  @override
  ConsumerState<TaikenExperiencePage> createState() =>
      _TaikenExperiencePageState();
}

class _TaikenExperiencePageState extends ConsumerState<TaikenExperiencePage>
    with TickerProviderStateMixin {

  // ── Typewriter ────────────────────────────────────────────────────────────
  final List<int> _shownBubbles = [];   // indices of fully-revealed bubbles
  int    _currentBubble   = -1;        // index of bubble currently animating
  String _twDisplay       = '';        // partial text shown during typewriter
  bool   _isTypewriting   = false;
  bool   _isPaused        = false;     // pauseAfterMs in progress
  Timer? _twTimer;
  Timer? _pauseTimer;

  // ── Question ──────────────────────────────────────────────────────────────
  int?  _selectedAnswer;
  bool  _showExplanation = false;

  // ── Gate countdown ────────────────────────────────────────────────────────
  int   _gateCountdown     = 5;
  bool  _gateSkipUnlocked  = false;
  Timer? _gateTimer;

  // ── Stage title reveal ────────────────────────────────────────────────────
  late AnimationController _titleCtrl;
  late Animation<double>   _titleFade;
  bool   _showTitle    = false;
  String _titleText    = '';

  // ── XP bar ────────────────────────────────────────────────────────────────
  late AnimationController _xpCtrl;
  late Animation<double>   _xpAnim;
  double _xpValue = 1.0;   // 0.0 – 1.0

  // ── Score count-up (outro) ────────────────────────────────────────────────
  late AnimationController _scoreCtrl;
  late Animation<double>   _scoreAnim;

  // ── Share card key ────────────────────────────────────────────────────────
  final GlobalKey _shareKey = GlobalKey();

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _titleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _titleFade = CurvedAnimation(parent: _titleCtrl, curve: Curves.easeInOut);

    _xpCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 750));
    _xpAnim = Tween<double>(begin: 1.0, end: 1.0)
        .animate(CurvedAnimation(parent: _xpCtrl, curve: Curves.easeInOut));

    _scoreCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _scoreAnim = CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOut);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taikenExperienceProvider(widget.taikenId).notifier)
          .loadTaiken();
    });
  }

  @override
  void dispose() {
    _twTimer?.cancel();
    _pauseTimer?.cancel();
    _gateTimer?.cancel();
    _titleCtrl.dispose();
    _xpCtrl.dispose();
    _scoreCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State listener
  // ─────────────────────────────────────────────────────────────────────────

  void _onStateChange(TaikenExperienceState? prev, TaikenExperienceState next) {
    if (!mounted) return;

    final stageChanged   = prev?.currentStageIndex != next.currentStageIndex;
    final toDialogue     = prev?.phase != next.phase && next.phase == TaikenPhase.dialogue;
    final toQuestion     = prev?.phase != next.phase && next.phase == TaikenPhase.question;
    final toGate         = prev?.phase != next.phase && next.phase == TaikenPhase.gateInterstitial;
    final toOutro        = prev?.phase != next.phase && next.phase == TaikenPhase.outro;

    if (stageChanged || toDialogue) {
      _resetDialogue();
      final title = next.currentStage?.stageTitle;
      if (title != null && title.isNotEmpty) _flashTitle(title);
    }

    if (toQuestion) {
      setState(() { _selectedAnswer = null; _showExplanation = false; });
    }

    if (toGate) {
      _startGateCountdown(next.currentQuestion?.gateSkipDelaySeconds ?? 5);
    }

    if (toOutro) {
      _scoreCtrl.forward(from: 0.0);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dialogue helpers
  // ─────────────────────────────────────────────────────────────────────────

  void _resetDialogue() {
    _twTimer?.cancel();
    _pauseTimer?.cancel();
    setState(() {
      _shownBubbles.clear();
      _currentBubble  = -1;
      _twDisplay      = '';
      _isTypewriting  = false;
      _isPaused       = false;
      _selectedAnswer = null;
      _showExplanation = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _advanceBubble();
    });
  }

  void _advanceBubble() {
    final dialogues = ref
        .read(taikenExperienceProvider(widget.taikenId))
        .currentDialogues;
    final next = _currentBubble + 1;
    if (next >= dialogues.length) return;

    final dlg   = dialogues[next];
    final speed = dlg.typewriterSpeed;

    setState(() {
      _currentBubble = next;
      _shownBubbles.add(next);
      _twDisplay     = speed == TypewriterSpeed.instant ? dlg.dialogueText : '';
      _isTypewriting = speed != TypewriterSpeed.instant;
      _isPaused      = false;
    });

    if (speed == TypewriterSpeed.instant) {
      _onBubbleDone(dlg);
      return;
    }

    final msPerChar = (1000 / speed.charsPerSecond).round();
    int i = 0;
    _twTimer?.cancel();
    _twTimer = Timer.periodic(Duration(milliseconds: msPerChar), (t) {
      if (!mounted) { t.cancel(); return; }
      i++;
      if (i >= dlg.dialogueText.length) {
        t.cancel();
        setState(() { _twDisplay = dlg.dialogueText; _isTypewriting = false; });
        _onBubbleDone(dlg);
      } else {
        setState(() { _twDisplay = dlg.dialogueText.substring(0, i); });
      }
    });
  }

  void _onBubbleDone(TaikenDialogue dlg) {
    if (dlg.pauseAfterMs > 0) {
      setState(() => _isPaused = true);
      _pauseTimer = Timer(Duration(milliseconds: dlg.pauseAfterMs), () {
        if (mounted) setState(() => _isPaused = false);
      });
    }
  }

  void _onDialogueTap() {
    if (_isPaused) return;
    final dialogues = ref
        .read(taikenExperienceProvider(widget.taikenId))
        .currentDialogues;

    if (_isTypewriting) {
      // First tap: skip to end of current bubble instantly.
      _twTimer?.cancel();
      final dlg = dialogues[_currentBubble];
      setState(() { _twDisplay = dlg.dialogueText; _isTypewriting = false; });
      _onBubbleDone(dlg);
      return;
    }
    // Second tap: advance to next bubble.
    if (_currentBubble < dialogues.length - 1) _advanceBubble();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stage title flash
  // ─────────────────────────────────────────────────────────────────────────

  void _flashTitle(String title) {
    setState(() { _titleText = title; _showTitle = true; });
    _titleCtrl.forward(from: 0.0);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      _titleCtrl.reverse().then((_) {
        if (mounted) setState(() => _showTitle = false);
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gate countdown
  // ─────────────────────────────────────────────────────────────────────────

  void _startGateCountdown(int seconds) {
    _gateTimer?.cancel();
    setState(() {
      _gateCountdown    = seconds;
      _gateSkipUnlocked = seconds <= 0;
    });
    if (seconds <= 0) return;
    _gateTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _gateCountdown--;
        if (_gateCountdown <= 0) { _gateSkipUnlocked = true; t.cancel(); }
      });
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // XP bar
  // ─────────────────────────────────────────────────────────────────────────

  void _updateXP(TaikenExperienceState s) {
    final total = s.taiken?.totalQuestions ?? 0;
    if (total == 0) return;
    final wrong    = s.progress?.wrongAnswers ?? 0;
    final lossRate = 1.0 / (total / 2.0);
    final newXP    = (1.0 - wrong * lossRate).clamp(0.0, 1.0);

    _xpAnim = Tween<double>(begin: _xpValue, end: newXP)
        .animate(CurvedAnimation(parent: _xpCtrl, curve: Curves.easeInOut));
    _xpValue = newXP;
    _xpCtrl.forward(from: 0.0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Share
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _share() async {
    try {
      final boundary = _shareKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data  = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/taiken_result.png');
      await file.writeAsBytes(data.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)],
          text: 'I just completed a Taiken on Pearl! 🎯');
    } catch (e) {
      debugPrint('Share error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build root
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<TaikenExperienceState>(
        taikenExperienceProvider(widget.taikenId), _onStateChange);
    final state = ref.watch(taikenExperienceProvider(widget.taikenId));
    return MilestoneToastListener(child: _route(state));
  }

  Widget _route(TaikenExperienceState s) {
    if (s.isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (s.error != null)  return _errorScreen(s.error!);
    if (s.taiken == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: Text('Taiken not found',
                style: TextStyle(color: Colors.white))),
      );
    }
    switch (s.phase) {
      case TaikenPhase.intro:            return _introScreen(s);
      case TaikenPhase.dialogue:         return _vnScreen(s);
      case TaikenPhase.gateInterstitial: return _gateScreen(s);
      case TaikenPhase.question:         return _questionScreen(s);
      case TaikenPhase.outro:            return _outroScreen(s);
    }
  }

  // =========================================================================
  // ERROR
  // =========================================================================

  Widget _errorScreen(String msg) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(backgroundColor: Colors.transparent,
        foregroundColor: Colors.white, title: const Text('Error')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(msg,
              style: const TextStyle(color: Colors.red, fontSize: 16),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              ref.read(taikenExperienceProvider(widget.taikenId).notifier)
                ..clearError()
                ..loadTaiken();
            },
            child: const Text('Retry'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Go Back',
                style: TextStyle(color: Colors.white70)),
          ),
        ]),
      ),
    ),
  );

  // =========================================================================
  // INTRO SCREEN  (Phase B + E)
  // =========================================================================

  Widget _introScreen(TaikenExperienceState s) {
    final t = s.taiken!;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Blurred background
        if (t.thumbnailUrl != null)
          Positioned.fill(
            child: Image.network(t.thumbnailUrl!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.grey[900])),
          ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.25),
                  Colors.black.withOpacity(0.80),
                  Colors.black,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
        ),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 160),
                // Episode badge (Phase E)
                if (t.isPartOfSeries && t.episodeNumber != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _chip('Episode ${t.episodeNumber}', Colors.purple),
                  ),
                Text(t.title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 30,
                        fontWeight: FontWeight.bold, height: 1.2),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _chip(t.domain, Colors.blue),
                  const SizedBox(width: 8),
                  _chip(t.difficulty, Colors.orange),
                ]),
                const SizedBox(height: 22),
                // Intro script
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Text(t.introScript,
                      style: TextStyle(
                          color: Colors.grey[300], fontSize: 15, height: 1.6),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(height: 22),
                // Stats row
                Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _statPill(Icons.layers_rounded, '${t.totalStages} Stages'),
                  _statPill(Icons.quiz_rounded, '${t.totalQuestions} Q'),
                  _statPill(Icons.check_circle_rounded, '${t.passThreshold}% pass'),
                ]),
                // Characters strip (Phase E)
                if (s.characters.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Text('CHARACTERS',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 11, letterSpacing: 1.5)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: s.characters.take(4).map((c) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundImage: c.effectivePortraitUrl != null
                              ? NetworkImage(c.effectivePortraitUrl!) : null,
                          backgroundColor: Colors.grey[800],
                          child: c.effectivePortraitUrl == null
                              ? Text(c.characterName[0],
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16))
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(c.characterName,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 10)),
                      ]),
                    )).toList(),
                  ),
                ],
                const SizedBox(height: 22),
                // Streak hint
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFFF6B35).withOpacity(0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const StreakBadge(size: 16),
                    const SizedBox(width: 8),
                    Text('Complete stages to extend your streak!',
                        style: TextStyle(color: Colors.grey[300], fontSize: 12)),
                  ]),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => ref
                        .read(taikenExperienceProvider(widget.taikenId).notifier)
                        .startExperience(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Begin Story',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // =========================================================================
  // VISUAL NOVEL SCREEN  (Phase B)
  // =========================================================================

  Widget _vnScreen(TaikenExperienceState s) {
    final stage    = s.currentStage;
    final dialogues = s.currentDialogues;
    final mood     = stage?.mood ?? StageMood.neutral;
    final allDone  = _shownBubbles.length >= dialogues.length
        && dialogues.isNotEmpty
        && !_isTypewriting;

    // Determine which character is currently speaking.
    TaikenCharacter? speaker;
    if (_currentBubble >= 0 && _currentBubble < dialogues.length) {
      final dlg = dialogues[_currentBubble];
      if (!dlg.isNarrator) {
        speaker = s.characters.firstWhere(
                (c) => c.characterId == dlg.characterId,
            orElse: () => s.characters.isNotEmpty ? s.characters.first
                : TaikenCharacter(characterId: '', taikenId: '',
                characterName: '', displayOrder: 0,
                createdAt: DateTime.now()));
      }
    }

    return GestureDetector(
      onTap: allDone ? null : _onDialogueTap,
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: _transparentAppBar(s),
        body: Stack(children: [
          // Background
          _background(stage),
          // Mood tint
          Positioned.fill(
            child: AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                color: mood.tintColor),
          ),
          // Bottom gradient
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.35),
                    Colors.black.withOpacity(0.82),
                  ],
                  stops: const [0.0, 0.48, 1.0],
                ),
              ),
            ),
          ),
          // Character portraits
          _portraits(s, speaker),
          // Stage title flash
          if (_showTitle) _titleFlash(mood),
          // Main UI
          SafeArea(
            child: Column(children: [
              const SizedBox(height: kToolbarHeight + 4),
              const Spacer(),
              _dialoguePanel(s, dialogues, allDone, mood),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _background(TaikenStage? stage) {
    final url = stage?.effectiveBackgroundUrl;
    if (url == null) {
      return Positioned.fill(child: Container(color: const Color(0xFF0D0D0D)));
    }
    return Positioned.fill(
      child: Stack(children: [
        Image.network(url,
            fit: BoxFit.cover, width: double.infinity, height: double.infinity,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF0D0D0D))),
        BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(color: Colors.black.withOpacity(0.3)),
        ),
        Center(
          child: Image.network(url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox()),
        ),
      ]),
    );
  }

  Widget _portraits(TaikenExperienceState s, TaikenCharacter? speaker) {
    final leftChar  = s.characters.firstWhere(
            (c) => c.portraitSide == PortraitSide.left,
        orElse: () => s.characters.isNotEmpty ? s.characters.first
            : TaikenCharacter(characterId: '__none__', taikenId: '',
            characterName: '', displayOrder: 0, createdAt: DateTime.now()));
    final rightChar = s.characters.firstWhere(
            (c) => c.portraitSide == PortraitSide.right,
        orElse: () => TaikenCharacter(characterId: '__none__', taikenId: '',
            characterName: '', displayOrder: 0, createdAt: DateTime.now()));

    Widget portrait(TaikenCharacter c, {required bool isLeft}) {
      if (c.characterId == '__none__') return const SizedBox();
      final isSpeaking = speaker?.characterId == c.characterId;
      final url = isSpeaking
          ? c.effectiveTalkingPortraitUrl
          : c.effectivePortraitUrl;
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 280),
        opacity: isSpeaking ? 1.0 : 0.42,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          scale: isSpeaking ? 1.0 : 0.91,
          alignment: isLeft ? Alignment.bottomLeft : Alignment.bottomRight,
          child: SizedBox(
            width: 140, height: 260,
            child: url != null
                ? Image.network(url,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                errorBuilder: (_, __, ___) => _portraitFallback(c))
                : _portraitFallback(c),
          ),
        ),
      );
    }

    return Positioned(
      left: 0, right: 0, bottom: 210,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          portrait(leftChar, isLeft: true),
          const Spacer(),
          portrait(rightChar, isLeft: false),
        ],
      ),
    );
  }

  Widget _portraitFallback(TaikenCharacter c) => Align(
    alignment: Alignment.bottomCenter,
    child: CircleAvatar(
      radius: 36, backgroundColor: Colors.grey[800],
      child: Text(c.characterName.isEmpty ? '?' : c.characterName[0],
          style: const TextStyle(color: Colors.white, fontSize: 24)),
    ),
  );

  Widget _titleFlash(StageMood mood) => Positioned.fill(
    child: IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _titleFade,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.72),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: mood.accent.withOpacity(0.5)),
            ),
            child: Text(_titleText,
                style: TextStyle(
                    color: mood.accent,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.4),
                textAlign: TextAlign.center),
          ),
        ),
      ),
    ),
  );

  Widget _dialoguePanel(TaikenExperienceState s,
      List<TaikenDialogue> dialogues, bool allDone, StageMood mood) {
    return Container(
      constraints:
      BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.40),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.84),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mood.accent.withOpacity(0.28)),
      ),
      child: Column(children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            itemCount: _shownBubbles.length,
            itemBuilder: (_, idx) {
              final bubbleIdx = _shownBubbles[idx];
              final dlg = dialogues[bubbleIdx];
              final isActive = bubbleIdx == _currentBubble;
              final displayText = isActive && _isTypewriting
                  ? _twDisplay
                  : dlg.dialogueText;
              final char = s.characters.firstWhere(
                      (c) => c.characterId == dlg.characterId,
                  orElse: () => TaikenCharacter(
                      characterId: '', taikenId: '',
                      characterName: 'Narrator', displayOrder: -1,
                      createdAt: DateTime.now()));
              return _bubble(dlg, char, displayText,
                  isActive && _isTypewriting);
            },
          ),
        ),
        _dialogueFooter(dialogues, allDone, mood),
      ]),
    );
  }

  Widget _bubble(TaikenDialogue dlg, TaikenCharacter char,
      String text, bool isActive) {
    if (dlg.isNarrator) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  height: 1.5),
              textAlign: TextAlign.center),
        ),
      );
    }
    final isLeft = char.portraitSide == PortraitSide.left;
    final bubbleColor = isLeft
        ? Colors.blue[900]!.withOpacity(0.88)
        : Colors.green[900]!.withOpacity(0.88);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
        isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isLeft) ...[
            CircleAvatar(
              radius: 13,
              backgroundImage: char.effectivePortraitUrl != null
                  ? NetworkImage(char.effectivePortraitUrl!) : null,
              backgroundColor: Colors.grey[700],
              child: char.effectivePortraitUrl == null
                  ? Text(char.characterName.isEmpty ? '?' : char.characterName[0],
                  style: const TextStyle(fontSize: 9, color: Colors.white))
                  : null,
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.70),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(14),
                  topRight:    const Radius.circular(14),
                  bottomLeft:  isLeft ? Radius.zero : const Radius.circular(14),
                  bottomRight: isLeft ? const Radius.circular(14) : Radius.zero,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(char.characterName,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.45),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(text,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                height: 1.45)),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 3),
                        _cursor(),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (!isLeft) ...[
            const SizedBox(width: 7),
            CircleAvatar(
              radius: 13,
              backgroundImage: char.effectivePortraitUrl != null
                  ? NetworkImage(char.effectivePortraitUrl!) : null,
              backgroundColor: Colors.grey[700],
              child: char.effectivePortraitUrl == null
                  ? Text(char.characterName.isEmpty ? '?' : char.characterName[0],
                  style: const TextStyle(fontSize: 9, color: Colors.white))
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _cursor() => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.0, end: 1.0),
    duration: const Duration(milliseconds: 480),
    builder: (_, v, __) => Opacity(
      opacity: v < 0.5 ? v * 2 : (1 - v) * 2,
      child: Container(width: 2, height: 13, color: Colors.white60),
    ),
  );

  Widget _dialogueFooter(
      List<TaikenDialogue> dialogues, bool allDone, StageMood mood) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: allDone
          ? SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => ref
              .read(taikenExperienceProvider(widget.taikenId).notifier)
              .enterQuestionPhase(),
          style: ElevatedButton.styleFrom(
            backgroundColor: mood.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 13),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Begin Challenge',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              SizedBox(width: 6),
              Icon(Icons.arrow_forward_rounded, size: 17),
            ],
          ),
        ),
      )
          : Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('${_shownBubbles.length}/${dialogues.length}',
              style: const TextStyle(
                  color: Colors.white30, fontSize: 11)),
          Row(children: [
            const Icon(Icons.touch_app_rounded,
                color: Colors.white24, size: 13),
            const SizedBox(width: 4),
            const Text('Tap to continue',
                style: TextStyle(color: Colors.white30, fontSize: 11)),
          ]),
        ],
      ),
    );
  }

  // =========================================================================
  // GATE INTERSTITIAL  (Phase C)
  // =========================================================================

  Widget _gateScreen(TaikenExperienceState s) {
    final question = s.currentQuestion;
    final domain   = question?.gateContentDomain
        ?? s.taiken?.domain
        ?? 'this topic';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (s.currentStage?.effectiveBackgroundUrl != null)
          Positioned.fill(
            child: Stack(children: [
              Image.network(s.currentStage!.effectiveBackgroundUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity, height: double.infinity,
                  errorBuilder: (_, __, ___) =>
                      Container(color: Colors.grey[900])),
              Container(color: Colors.black.withOpacity(0.76)),
            ]),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Header card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.09),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.orange.withOpacity(0.35)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 62, height: 62,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.menu_book_rounded,
                          color: Colors.orange, size: 30),
                    ),
                    const SizedBox(height: 14),
                    const Text('Before you continue…',
                        style: TextStyle(
                            color: Colors.white, fontSize: 19,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text('This challenge involves knowledge of',
                        style: TextStyle(
                            color: Colors.grey[400], fontSize: 13),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    _chip(domain, Colors.orange),
                    if (question != null) ...[
                      const SizedBox(height: 12),
                      Text('"${question.questionText}"',
                          style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                              fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ]),
                ),
                const SizedBox(height: 26),
                // Learn First
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ref.read(taikenExperienceProvider(widget.taikenId)
                          .notifier).studyGate();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _LearningPageStub(
                            domain: domain,
                            onDone: () => ref
                                .read(taikenExperienceProvider(widget.taikenId)
                                .notifier)
                                .resumeFromGate(),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.school_rounded),
                    label: const Text('Learn First',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Skip with countdown
                SizedBox(
                  width: double.infinity,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 280),
                    opacity: _gateSkipUnlocked ? 1.0 : 0.38,
                    child: OutlinedButton(
                      onPressed: _gateSkipUnlocked
                          ? () => ref
                          .read(taikenExperienceProvider(widget.taikenId)
                          .notifier)
                          .skipGate(afterDelay: true)
                          : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: BorderSide(
                            color: _gateSkipUnlocked
                                ? Colors.white24
                                : Colors.white12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _gateSkipUnlocked
                            ? 'I already know this'
                            : 'I already know this  ($_gateCountdown)',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // =========================================================================
  // QUESTION SCREEN  (Phase B)
  // =========================================================================

  Widget _questionScreen(TaikenExperienceState s) {
    final question = s.currentQuestion;
    if (question == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref
            .read(taikenExperienceProvider(widget.taikenId).notifier)
            .advanceToNextQuestion();
      });
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    final stage = s.currentStage;
    final mood  = stage?.mood ?? StageMood.neutral;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _transparentAppBar(s),
      body: Stack(children: [
        _background(stage),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.55),
                  Colors.black.withOpacity(0.94),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            const SizedBox(height: kToolbarHeight + 4),
            _progressBar(s),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stage / question counter chips
                    Row(children: [
                      _chip(
                          'Stage ${s.currentStageIndex + 1}'
                              '/${s.stages.length}',
                          Colors.white24),
                      const SizedBox(width: 8),
                      _chip(
                          'Q ${s.currentQuestionIndex + 1}'
                              '/${s.currentQuestions.length}',
                          mood.accent.withOpacity(0.35)),
                    ]),
                    const SizedBox(height: 14),
                    // Question card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: mood.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: mood.accent.withOpacity(0.38),
                            width: 1.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.quiz_rounded,
                              color: mood.accent, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(question.questionText,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    height: 1.45)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Options
                    ...List.generate(question.options.length,
                            (i) => _optionTile(question, i, s, mood)),
                    // Explanation
                    if (_showExplanation && question.explanation != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.info_outline,
                                  color: mood.accent, size: 15),
                              const SizedBox(width: 6),
                              Text('Explanation',
                                  style: TextStyle(
                                      color: mood.accent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ]),
                            const SizedBox(height: 7),
                            Text(question.explanation!,
                                style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 13,
                                    height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                    // Continue button
                    if (_selectedAnswer != null) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedAnswer  = null;
                              _showExplanation = false;
                            });
                            ref
                                .read(taikenExperienceProvider(widget.taikenId)
                                .notifier)
                                .advanceToNextQuestion();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: mood.accent,
                            foregroundColor: Colors.white,
                            padding:
                            const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            s.isLastQuestion && !s.hasMoreStages
                                ? 'Finish Story'
                                : 'Continue',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _optionTile(TaikenQuestion q, int i,
      TaikenExperienceState s, StageMood mood) {
    final isSelected = _selectedAnswer == i;
    final isCorrect  = i == q.correctOptionIndex;
    final answered   = _selectedAnswer != null;

    Color bg, border, text;
    IconData? icon;

    if (answered) {
      if (isCorrect) {
        bg = Colors.green.withOpacity(0.18);
        border = Colors.green;
        text   = Colors.green;
        icon   = Icons.check_circle_rounded;
      } else if (isSelected) {
        bg = Colors.red.withOpacity(0.18);
        border = Colors.red;
        text   = Colors.red;
        icon   = Icons.cancel_rounded;
      } else {
        bg     = Colors.white.withOpacity(0.03);
        border = Colors.white12;
        text   = Colors.white30;
      }
    } else {
      bg     = Colors.white.withOpacity(0.06);
      border = Colors.white.withOpacity(0.14);
      text   = Colors.white;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: answered ? null : () async {
          setState(() { _selectedAnswer = i; _showExplanation = true; });
          await ref
              .read(taikenExperienceProvider(widget.taikenId).notifier)
              .submitAnswer(q.questionId, i);
          _updateXP(ref.read(taikenExperienceProvider(widget.taikenId)));
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(children: [
            Expanded(
              child: Text(q.options[i],
                  style: TextStyle(
                      color: text, fontSize: 15,
                      fontWeight: FontWeight.w500)),
            ),
            if (icon != null) Icon(icon, color: border, size: 20),
          ]),
        ),
      ),
    );
  }

  // =========================================================================
  // OUTRO / RESULT SCREEN  (Phase D)
  // =========================================================================

  Widget _outroScreen(TaikenExperienceState s) {
    final isPassed  = s.progress?.status == 'completed';
    final accuracy  = s.progress?.accuracyPercentage ?? 0.0;
    final correct   = s.progress?.correctAnswers ?? 0;
    final total     = s.taiken?.totalQuestions ?? 0;
    final badge     = s.earnedBadge;
    final nextEp    = s.nextEpisode;
    final streak    = ref.watch(currentStreakProvider);
    final isActive  = ref.watch(isStreakActiveTodayProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              // ── Shareable result card ──────────────────────────────────
              RepaintBoundary(
                key: _shareKey,
                child: _resultCard(s, isPassed, accuracy, correct, total, badge),
              ),
              const SizedBox(height: 16),
              // ── Share button ───────────────────────────────────────────
              if (isPassed)
                OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_rounded,
                      size: 17, color: Colors.white60),
                  label: const Text('Share Result',
                      style: TextStyle(color: Colors.white60, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              const SizedBox(height: 18),
              // ── Streak ────────────────────────────────────────────────
              _streakRow(streak, isActive),
              const SizedBox(height: 16),
              // ── Rating ────────────────────────────────────────────────
              _ratingSection(s),
              const SizedBox(height: 16),
              // ── Next episode ──────────────────────────────────────────
              if (isPassed && nextEp != null) ...[
                _nextEpisodeTeaser(nextEp),
                const SizedBox(height: 16),
              ],
              // ── CTAs ──────────────────────────────────────────────────
              if (!isPassed) ...[
                _cta(
                  label: 'Try Again',
                  color: Colors.orange,
                  onTap: () async => ref
                      .read(taikenExperienceProvider(widget.taikenId).notifier)
                      .resetAndRestart(),
                ),
                const SizedBox(height: 10),
              ],
              _cta(
                label: 'Back to Taikens',
                color: Colors.transparent,
                outlined: true,
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _resultCard(TaikenExperienceState s, bool isPassed,
      double accuracy, int correct, int total, TaikenBadge? badge) {
    final accentColor = isPassed ? Colors.green : Colors.red;
    Color badgeColor  = accentColor;
    if (badge != null) {
      try {
        badgeColor = Color(
            int.parse(badge.badgeColorHex.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }

    return AnimatedBuilder(
      animation: _scoreAnim,
      builder: (_, __) {
        final displayed = accuracy * _scoreAnim.value;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF111111),
            borderRadius: BorderRadius.circular(20),
            border:
            Border.all(color: accentColor.withOpacity(0.35), width: 1.5),
          ),
          child: Column(children: [
            // Status icon
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.13),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPassed
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: accentColor, size: 40,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              isPassed ? 'Mission Complete!' : 'Mission Failed',
              style: TextStyle(
                  color: accentColor, fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(s.taiken?.title ?? '',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 18),
            // Score count-up
            Text('${displayed.toStringAsFixed(1)}%',
                style: TextStyle(
                    color: accentColor, fontSize: 54,
                    fontWeight: FontWeight.w900)),
            Text('$correct / $total correct',
                style: TextStyle(color: Colors.grey[500], fontSize: 13)),
            const SizedBox(height: 16),
            // Badge
            if (badge != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                      color: badgeColor.withOpacity(0.35)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Image.network(badge.badgeIconUrl,
                      width: 26, height: 26,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.emoji_events_rounded,
                          color: badgeColor, size: 22)),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(badge.badgeName,
                        style: TextStyle(
                            color: badgeColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    if (badge.description != null)
                      Text(badge.description!,
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 10)),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            // Domain / difficulty chips
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _chip(s.taiken?.domain ?? '', Colors.blue),
              const SizedBox(width: 8),
              _chip(s.taiken?.difficulty ?? '', Colors.orange),
            ]),
            const SizedBox(height: 14),
            // App branding
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 18, height: 18,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text('Pearl App',
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ]),
          ]),
        );
      },
    );
  }

  Widget _streakRow(int streak, bool isActive) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isActive
          ? const Color(0xFFFF6B35).withOpacity(0.1)
          : Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: isActive
              ? const Color(0xFFFF6B35).withOpacity(0.3)
              : Colors.white12),
    ),
    child: Row(children: [
      Icon(Icons.local_fire_department_rounded,
          color: isActive
              ? const Color(0xFFFF6B35)
              : Colors.grey[700],
          size: 22),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          isActive
              ? '$streak day streak — active today! 🔥'
              : 'Current streak: $streak days',
          style: TextStyle(
              color: isActive ? Colors.white : Colors.grey[600],
              fontSize: 13,
              fontWeight: FontWeight.w600),
        ),
      ),
    ]),
  );

  Widget _ratingSection(TaikenExperienceState s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: StatefulBuilder(builder: (_, set) {
        int selected  = s.userRating ?? 0;
        bool submitted = selected > 0;
        return Column(children: [
          Text('Rate this Taiken',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: submitted ? null : () async {
                  set(() { selected = star; submitted = true; });
                  await ref
                      .read(taikenExperienceProvider(widget.taikenId)
                      .notifier)
                      .rateTaiken(star, null);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    star <= selected
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: Colors.amber, size: 30,
                  ),
                ),
              );
            }),
          ),
          if (submitted)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Thanks for rating!',
                  style: TextStyle(
                      color: Colors.green[400], fontSize: 12)),
            ),
        ]);
      }),
    );
  }

  Widget _nextEpisodeTeaser(Taiken nextEp) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.purple.withOpacity(0.09),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.purple.withOpacity(0.28)),
    ),
    child: Column(children: [
      Row(children: [
        const Icon(Icons.play_circle_outline,
            color: Colors.purple, size: 17),
        const SizedBox(width: 7),
        Text(
          'Episode ${nextEp.episodeNumber} — Up Next',
          style: const TextStyle(
              color: Colors.purple,
              fontWeight: FontWeight.bold,
              fontSize: 12),
        ),
      ]),
      const SizedBox(height: 10),
      if (nextEp.thumbnailUrl != null)
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            nextEp.thumbnailUrl!,
            height: 90, width: double.infinity, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(),
          ),
        ),
      const SizedBox(height: 10),
      Text(nextEp.title,
          style: const TextStyle(
              color: Colors.white, fontSize: 15,
              fontWeight: FontWeight.w600),
          textAlign: TextAlign.center),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TaikenExperiencePage(taikenId: nextEp.taikenId),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Continue Story →',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    ]),
  );

  // =========================================================================
  // SHARED HELPERS
  // =========================================================================

  AppBar _transparentAppBar(TaikenExperienceState s) => AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    foregroundColor: Colors.white,
    leading: IconButton(
      icon: const Icon(Icons.close_rounded),
      onPressed: () => Navigator.pop(context),
    ),
    title: _topBar(s),
    centerTitle: true,
  );

  Widget _topBar(TaikenExperienceState s) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _chip(
          'Stage ${s.currentStageIndex + 1}/${s.stages.length}',
          Colors.white24),
      const SizedBox(width: 8),
      const StreakBadge(size: 13),
      const SizedBox(width: 8),
      _xpPill(),
    ],
  );

  Widget _xpPill() => AnimatedBuilder(
    animation: _xpAnim,
    builder: (_, __) {
      final v = _xpAnim.value;
      final c = v > 0.7
          ? Colors.green
          : v > 0.4
          ? Colors.orange
          : Colors.red;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.favorite_rounded, color: c, size: 12),
          const SizedBox(width: 3),
          Text('${(v * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: c, fontSize: 11, fontWeight: FontWeight.bold)),
        ]),
      );
    },
  );

  Widget _progressBar(TaikenExperienceState s) {
    final total     = s.taiken!.totalQuestions;
    final answered  = s.progress!.questionsAnswered;
    final progress  = total == 0 ? 0.0 : answered / total;
    final threshold = s.taiken!.passThreshold / 100.0;
    final accuracy  = s.progress!.accuracyPercentage;
    final passing   = accuracy >= s.taiken!.passThreshold;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$answered/$total',
              style: const TextStyle(color: Colors.white30, fontSize: 11)),
          Text('${accuracy.toStringAsFixed(0)}% accuracy',
              style: TextStyle(
                  color: passing ? Colors.green : Colors.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                  passing ? Colors.green : Colors.orange),
            ),
          ),
          // Threshold marker
          Positioned(
            left: (MediaQuery.of(context).size.width - 32) * threshold,
            top: 0, bottom: 0,
            child: Container(
                width: 2,
                decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(1))),
          ),
        ]),
      ]),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.38)),
    ),
    child: Text(label,
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _statPill(IconData icon, String label) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white30, size: 13),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]);

  Widget _cta({
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool outlined = false,
  }) => SizedBox(
    width: double.infinity,
    child: outlined
        ? OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white60,
        side: const BorderSide(color: Colors.white12),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15)),
    )
        : ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Learning page stub  (Phase C)
// Once TaikenLearningPage is built in its own file, replace this with a
// proper import and remove this class.
// ─────────────────────────────────────────────────────────────────────────────

class _LearningPageStub extends StatelessWidget {
  final String domain;
  final VoidCallback onDone;
  const _LearningPageStub({required this.domain, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text('Study: $domain'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.school_rounded,
                  color: Colors.orange, size: 36),
            ),
            const SizedBox(height: 22),
            Text('Studying: $domain',
                style: const TextStyle(
                    color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text(
              'Replace this stub with TaikenLearningPage once the '
                  'learning feed provider is ready. The gate flow is '
                  'fully wired end-to-end right now.',
              style: TextStyle(
                  color: Colors.grey[500], fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  onDone();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Return to Mission →',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}