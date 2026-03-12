// =============================================================================
// taiken_audio_widgets.dart
//
// Two things:
//
//  1. TaikenMusicButton
//     A small mute/unmute icon button for the AppBar of the experience page.
//
//  2. TaikenAudioMixin
//     A mixin for the TaikenExperiencePage State class.
//     Handles: init, dispose, audio event routing, mute toggle, and wiring
//     the audio callback into the provider.
//
// Usage in TaikenExperiencePage:
//
//   class _TaikenExperiencePageState extends ConsumerState<TaikenExperiencePage>
//       with TaikenAudioMixin {
//
//     @override
//     void initState() {
//       super.initState();
//       initAudio(widget.taikenId);   // ← call this
//     }
//
//     @override
//     void dispose() {
//       disposeAudio();               // ← and this
//       super.dispose();
//     }
//   }
//
//   // In the AppBar actions:
//   TaikenMusicButton(isMuted: audioIsMuted, onToggle: toggleAudioMute)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../Service/taiken_audio_service.dart';
import '../ViewModel/taiken_experience_provider.dart';
import '../Model/taiken.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Mute/unmute icon button
// ─────────────────────────────────────────────────────────────────────────────

class TaikenMusicButton extends StatelessWidget {
  final bool isMuted;
  final VoidCallback onToggle;

  const TaikenMusicButton({
    super.key,
    required this.isMuted,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: isMuted ? 'Unmute music' : 'Mute music',
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Icon(
          isMuted ? Icons.music_off_rounded : Icons.music_note_rounded,
          key: ValueKey(isMuted),
          size: 22,
        ),
      ),
      color: Theme.of(context).appBarTheme.foregroundColor,
      onPressed: onToggle,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio mixin — add to TaikenExperiencePage's State
// ─────────────────────────────────────────────────────────────────────────────

mixin TaikenAudioMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final TaikenAudioService _audio = TaikenAudioService();
  bool audioIsMuted = false;

  // ── Call from initState ────────────────────────────────────────────────────

  Future<void> initAudio(String taikenId) async {
    await _audio.init();

    // Register callback into the provider so every phase/stage event
    // gets routed here.
    final notifier = ref.read(taikenExperienceProvider(taikenId).notifier);
    notifier.registerAudioCallback(_handleAudioEvent);

    // If the provider already has a loaded taiken (e.g. hot-reload), set the
    // default cue immediately.
    final s = ref.read(taikenExperienceProvider(taikenId));
    if (s.taiken?.defaultMusicCue != null) {
      _audio.setTaikenDefault(s.taiken!.defaultMusicCue);
    }
  }

  // ── Call from dispose ──────────────────────────────────────────────────────

  void disposeAudio() => _audio.dispose();

  // ── Public — wire to AppBar button ────────────────────────────────────────

  void toggleAudioMute() {
    setState(() => audioIsMuted = !audioIsMuted);
    _audio.setMuted(audioIsMuted);
  }

  // ── Called by the provider on every event ─────────────────────────────────

  void _handleAudioEvent(String event, String? stageCue) {
    switch (event) {
      case 'dialogue':
        _audio.onDialoguePhase(stageCue);
        break;
      case 'question':
        _audio.onQuestionPhase();
        break;
      case 'stage_change':
        _audio.onStageChange(stageCue);
        break;
      case 'gate':
      // Gates are a sub-state of question phase — keep music off.
        break;
      case 'outro':
        _audio.onOutro();
        break;
    }
  }

  // ── Called when taiken finishes loading (set default cue) ─────────────────

  void onTaikenLoaded(Taiken taiken) {
    _audio.setTaikenDefault(taiken.defaultMusicCue);
  }
}