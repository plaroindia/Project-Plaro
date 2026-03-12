// =============================================================================
// taiken_ai_sheet.dart
//
// A modal bottom-sheet that collects the user's Taiken idea and triggers
// Gemini generation.  Call it from TaikenCreatePage via:
//
//   TaikenAiSheet.show(context, ref);
//
// After successful generation the sheet auto-closes and the builder fields
// are pre-filled.  The user can then edit anything before publishing.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ViewModel/taiken_ai_provider.dart';
import '../ViewModel/taiken_ai_service.dart';

class TaikenAiSheet extends ConsumerStatefulWidget {
  const TaikenAiSheet({super.key});

  /// Convenience launcher — shows the sheet as a modal bottom-sheet.
  static Future<void> show(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TaikenAiSheet(),
    );
  }

  @override
  ConsumerState<TaikenAiSheet> createState() => _TaikenAiSheetState();
}

class _TaikenAiSheetState extends ConsumerState<TaikenAiSheet> {
  final _topicCtrl     = TextEditingController();
  final _objectiveCtrl = TextEditingController();
  final _questionsCtrl = TextEditingController();
  String _difficulty   = 'beginner';
  String _domain       = 'Technology';
  int    _stageCount   = 2;

  static const _difficulties = ['beginner', 'intermediate', 'advanced'];
  static const _domains      = ['Science', 'Business', 'History', 'Technology', 'Arts'];

  @override
  void dispose() {
    _topicCtrl.dispose();
    _objectiveCtrl.dispose();
    _questionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final topic     = _topicCtrl.text.trim();
    final objective = _objectiveCtrl.text.trim();
    if (topic.isEmpty || objective.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill in topic and learning objective.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    await ref.read(taikenAiProvider.notifier).generate(
      TaikenAiInput(
        topic:             topic,
        learningObjective: objective,
        keyQuestions:      _questionsCtrl.text.trim(),
        difficulty:        _difficulty,
        domain:            _domain,
        stageCount:        _stageCount,
      ),
    );

    if (!mounted) return;
    final state = ref.read(taikenAiProvider);
    if (state.error == null && state.wasApplied) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Taiken generated! Review and edit before publishing.'),
          ],
        ),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiState   = ref.watch(taikenAiProvider);
    final scheme    = Theme.of(context).colorScheme;
    final cardColor = Theme.of(context).cardColor;

    // Listen for errors
    ref.listen<TaikenAiState>(taikenAiProvider, (_, next) {
      if (next.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.error!),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
        ref.read(taikenAiProvider.notifier).clearError();
      }
    });

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // ── Handle ─────────────────────────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),

            // ── Header ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C63FF), Color(0xFF9C27B0)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI Taiken Generator',
                            style: TextStyle(
                              color:      scheme.onSurface,
                              fontSize:   18,
                              fontWeight: FontWeight.bold,
                            )),
                        Text('Describe your idea — AI fills the builder',
                            style: TextStyle(
                              color:    scheme.onSurface.withOpacity(0.55),
                              fontSize: 12,
                            )),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: scheme.onSurface.withOpacity(0.5),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Form ───────────────────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                children: [
                  // Topic
                  _label('Topic *'),
                  const SizedBox(height: 6),
                  _textField(
                    controller: _topicCtrl,
                    hint: 'e.g. Supply and Demand in a Startup',
                    maxLines: 1,
                  ),
                  const SizedBox(height: 16),

                  // Learning objective
                  _label('Learning Objective *'),
                  const SizedBox(height: 6),
                  _textField(
                    controller: _objectiveCtrl,
                    hint: 'e.g. Understand how price changes affect market equilibrium',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // Key questions (optional)
                  _label('Key Questions (optional)'),
                  const SizedBox(height: 6),
                  _textField(
                    controller: _questionsCtrl,
                    hint: 'e.g. What happens when supply exceeds demand? What drives prices up?',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),

                  // Domain + Difficulty row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Domain'),
                            const SizedBox(height: 6),
                            _dropdown<String>(
                              value:    _domain,
                              items:    _domains,
                              onChanged: (v) {
                                if (v != null) setState(() => _domain = v);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _label('Difficulty'),
                            const SizedBox(height: 6),
                            _dropdown<String>(
                              value:   _difficulty,
                              items:   _difficulties,
                              display: (v) => v[0].toUpperCase() + v.substring(1),
                              onChanged: (v) {
                                if (v != null) setState(() => _difficulty = v);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Stage count
                  _label('Number of Stages: $_stageCount'),
                  Slider(
                    value:      _stageCount.toDouble(),
                    min:        1,
                    max:        4,
                    divisions:  3,
                    label:      '$_stageCount',
                    activeColor: const Color(0xFF6C63FF),
                    onChanged:  (v) => setState(() => _stageCount = v.toInt()),
                  ),

                  const SizedBox(height: 8),

                  // Asset hint card
                  _buildAssetHintCard(scheme),

                  const SizedBox(height: 28),

                  // Generate / Regenerate button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: aiState.isGenerating ? null : _generate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        disabledBackgroundColor:
                        const Color(0xFF6C63FF).withOpacity(0.5),
                      ),
                      child: aiState.isGenerating
                          ? const _GeneratingIndicator()
                          : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            aiState.wasApplied
                                ? Icons.refresh
                                : Icons.auto_awesome,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            aiState.wasApplied
                                ? 'Regenerate'
                                : 'Generate Taiken',
                            style: const TextStyle(
                                fontSize:   16,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (aiState.wasApplied) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        '✓ Builder pre-filled — close to review & edit',
                        style: TextStyle(
                          color:    scheme.onSurface.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _label(String text) => Text(
    text,
    style: TextStyle(
      color:      Theme.of(context).colorScheme.onSurface,
      fontSize:   13,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) =>
      TextField(
        controller: controller,
        maxLines:   maxLines,
        style:      TextStyle(color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(
          hintText:  hint,
          hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
              fontSize: 13),
          filled:    true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    String Function(T)? display,
    required void Function(T?) onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value:         value,
        dropdownColor: Theme.of(context).cardColor,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
        decoration: InputDecoration(
          filled:    true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
        items: items
            .map((i) => DropdownMenuItem<T>(
          value: i,
          child: Text(display != null ? display(i) : i.toString()),
        ))
            .toList(),
        onChanged: onChanged,
      );

  Widget _buildAssetHintCard(ColorScheme scheme) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF6C63FF).withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
          color: const Color(0xFF6C63FF).withOpacity(0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.info_outline,
              color: Color(0xFF6C63FF), size: 16),
          const SizedBox(width: 6),
          Text('AI will auto-select from:',
              style: TextStyle(
                color:      scheme.onSurface,
                fontSize:   12,
                fontWeight: FontWeight.w600,
              )),
        ]),
        const SizedBox(height: 8),
        _assetRow('👤 Characters',
            TaikenAssets.characters.join(', ')),
        _assetRow('🖼️ Backgrounds',
            TaikenAssets.backgrounds.join(', ')),
        _assetRow('🎵 Music',
            TaikenAssets.backgroundMusic.join(', ')),
        const SizedBox(height: 6),
        Text(
          'No images or audio are generated — only text content.',
          style: TextStyle(
            color:    scheme.onSurface.withOpacity(0.45),
            fontSize: 11,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    ),
  );

  Widget _assetRow(String label, String values) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: RichText(
      text: TextSpan(
        style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface),
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(
              text: values,
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.6))),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated "Generating…" indicator
// ─────────────────────────────────────────────────────────────────────────────

class _GeneratingIndicator extends StatefulWidget {
  const _GeneratingIndicator();

  @override
  State<_GeneratingIndicator> createState() => _GeneratingIndicatorState();
}

class _GeneratingIndicatorState extends State<_GeneratingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  final List<String> _labels = [
    'Crafting story…',
    'Writing dialogues…',
    'Building questions…',
    'Choosing characters…',
    'Finalising…',
  ];
  int _labelIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);

    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted) return false;
      setState(() => _labelIndex = (_labelIndex + 1) % _labels.length);
      return mounted;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Text(
            _labels[_labelIndex],
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}