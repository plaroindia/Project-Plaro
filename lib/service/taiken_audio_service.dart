// =============================================================================
// taiken_audio_service.dart
//
// Background music playback for the Taiken experience using just_audio.
//
// Behaviour:
//   • Per-taiken default music cue — plays from the moment the intro screen
//     appears and throughout the whole experience unless overridden.
//   • Per-stage override — when a stage has its own musicCue, the track fades
//     out and the new one fades in.  When the stage's musicCue is null, the
//     taiken default resumes (or silence if no default).
//   • Questions — music fades out when enterQuestionPhase() is called.
//     Music resumes (fades in) when dialogue phase begins again.
//   • Outro — music stops when the outro screen is shown.
//   • Looping — every track loops indefinitely until explicitly changed/stopped.
//   • Fade duration — 800 ms cross-fade by default.
//
// Lifecycle: create one instance per TaikenExperiencePage, dispose when the
// page is disposed.
//
// Usage:
//   final audio = TaikenAudioService();
//   await audio.init();
//   audio.setTaikenDefault('ambient');        // from taiken.defaultMusicCue
//   audio.onStageChange('study');             // from stage.musicCue (or null)
//   audio.onQuestionPhase();                  // fade out
//   audio.onDialoguePhase('ambient');         // fade back in
//   audio.onOutro();                          // stop
//   audio.dispose();
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class TaikenAudioService {
  static const Duration _fadeDuration = Duration(milliseconds: 800);
  static const double   _targetVolume = 0.45; // comfortable background level

  // Two players enable cross-fading: one fades out while the other fades in.
  final AudioPlayer _playerA = AudioPlayer();
  final AudioPlayer _playerB = AudioPlayer();

  bool _useA      = true;   // which player is currently "active"
  String? _currentCue;      // key of the currently-playing track
  String? _taikenDefault;   // taiken-level default cue
  bool _initialised = false;
  bool _muted       = false;

  AudioPlayer get _active   => _useA ? _playerA : _playerB;
  AudioPlayer get _inactive => _useA ? _playerB : _playerA;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    await _playerA.setVolume(0);
    await _playerB.setVolume(0);
    await _playerA.setLoopMode(LoopMode.one);
    await _playerB.setLoopMode(LoopMode.one);
  }

  void dispose() {
    _playerA.dispose();
    _playerB.dispose();
  }

  // ── Public API called by the experience page ───────────────────────────────

  /// Called once when the experience loads — sets the taiken-level default.
  void setTaikenDefault(String? cue) {
    _taikenDefault = cue;
    if (cue != null) _crossFadeTo(cue);
  }

  /// Called when advancing to a new stage.
  /// [stageCue] is the stage's own musicCue; null means fall back to default.
  void onStageChange(String? stageCue) {
    final target = stageCue ?? _taikenDefault;
    if (target == null) {
      _fadeOutActive();
      _currentCue = null;
    } else if (target != _currentCue) {
      _crossFadeTo(target);
    }
    // If same cue → do nothing, let it keep playing.
  }

  /// Called when entering the question phase — fades out music.
  void onQuestionPhase() {
    _fadeOutActive();
  }

  /// Called when returning to dialogue phase (after questions or gate).
  /// [stageCue] is the current stage's cue; falls back to taiken default.
  void onDialoguePhase(String? stageCue) {
    final target = stageCue ?? _taikenDefault;
    if (target != null && target != _currentCue) {
      _crossFadeTo(target);
    } else if (target != null && _active.volume < _targetVolume) {
      // Same track — just fade back in.
      _fadeIn(_active);
    }
  }

  /// Called when the outro screen appears — stop everything.
  void onOutro() {
    _fadeOutActive();
    _currentCue = null;
  }

  /// Toggle mute/unmute.
  void setMuted(bool muted) {
    _muted = muted;
    if (muted) {
      _playerA.setVolume(0);
      _playerB.setVolume(0);
    } else if (_currentCue != null) {
      _fadeIn(_active);
    }
  }

  bool get isMuted => _muted;
  String? get currentCue => _currentCue;

  // ── Internal helpers ───────────────────────────────────────────────────────

  Future<void> _crossFadeTo(String cue) async {
    if (_muted) {
      // Load silently — ready for when user un-mutes.
      await _loadTrack(_inactive, cue);
      _useA = !_useA;
      _currentCue = cue;
      return;
    }

    try {
      await _loadTrack(_inactive, cue);
      await _inactive.seek(Duration.zero);
      await _inactive.play();

      // Fade out active, fade in inactive simultaneously.
      await Future.wait([
        _fadeOut(_active),
        _fadeIn(_inactive),
      ]);

      await _active.stop();
      _useA = !_useA;
      _currentCue = cue;
    } catch (e) {
      debugPrint('[TaikenAudio] crossFade error: $e');
    }
  }

  Future<void> _loadTrack(AudioPlayer player, String cue) async {
    final path = 'assets/taiken/music/$cue.mp3';
    try {
      await player.setAsset(path);
    } catch (e) {
      debugPrint('[TaikenAudio] failed to load "$path": $e');
      rethrow;
    }
  }

  void _fadeOutActive() {
    _fadeOut(_active).then((_) => _active.stop()).catchError(
          (e) => debugPrint('[TaikenAudio] fadeOut error: $e'),
    );
    _currentCue = null;
  }

  Future<void> _fadeOut(AudioPlayer player) async {
    const steps = 16;
    final stepMs = _fadeDuration.inMilliseconds ~/ steps;
    final start  = player.volume;
    for (int i = steps; i >= 0; i--) {
      await player.setVolume((start * i / steps).clamp(0.0, 1.0));
      await Future.delayed(Duration(milliseconds: stepMs));
    }
  }

  Future<void> _fadeIn(AudioPlayer player) async {
    const steps = 16;
    final stepMs = _fadeDuration.inMilliseconds ~/ steps;
    final target = _muted ? 0.0 : _targetVolume;
    for (int i = 0; i <= steps; i++) {
      await player.setVolume((target * i / steps).clamp(0.0, 1.0));
      await Future.delayed(Duration(milliseconds: stepMs));
    }
  }
}