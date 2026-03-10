// =============================================================================
// taiken_create_page.dart  — FINAL
//
// Changes from previous version (new fields wired into UI):
//
//   Page 0 – Basic Info
//     + Pass threshold slider (50 – 100)
//     + Series section: "Is this part of a series?" toggle
//       → expands to show Series ID text field + Episode number field
//
//   Page 2 – Characters
//     + Portrait side toggle (Left / Right) per character card
//     + "Player character" checkbox per character card
//
//   Page 3 – Stages
//     + Stage mood dropdown (neutral / tense / happy / dramatic /
//       mysterious / urgent) per stage card
//     + Stage type dropdown (story / challenge / mixed) per stage card
//     + Per dialogue: emotion + typewriter speed dropdowns
//     + Per dialogue: pause after (ms) number field
//     + Per question: "Learning gate" toggle
//       → expands to show domain field + skip delay seconds field
//
//   All existing pages (Page 1 Scripts, Page 4 Review) are unchanged.
//   All existing provider calls use the same method names.
//   The review page now also shows series info and pass threshold.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ViewModel/taiken_create_provider.dart';
import '../Model/taiken.dart';

class TaikenCreatePage extends ConsumerStatefulWidget {
  const TaikenCreatePage({super.key});

  @override
  ConsumerState<TaikenCreatePage> createState() => _TaikenCreatePageState();
}

class _TaikenCreatePageState extends ConsumerState<TaikenCreatePage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Text controllers for Page 0
  final _titleController       = TextEditingController();
  final _descriptionController = TextEditingController();
  final _seriesIdController    = TextEditingController();

  // Text controllers for Page 1
  final _introScriptController    = TextEditingController();
  final _outroSuccessController   = TextEditingController();
  final _outroFailureController   = TextEditingController();

  bool _showSeriesFields = false;

  @override
  void dispose() {
    _pageController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _seriesIdController.dispose();
    _introScriptController.dispose();
    _outroSuccessController.dispose();
    _outroFailureController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 4) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut);
    }
  }

  Future<void> _handleCreate() async {
    final success =
    await ref.read(taikenCreateProvider.notifier).createTaiken();
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Taiken published successfully! 🎉'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      ref.read(taikenCreateProvider.notifier).reset();
      Navigator.pop(context);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taikenCreateProvider);

    ref.listen<TaikenCreateState>(taikenCreateProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(next.error!),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
        ref.read(taikenCreateProvider.notifier).clearError();
      }
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        title: const Text('Create Taiken'),
        actions: [
          if (_currentPage == 4)
            TextButton(
              onPressed: state.isLoading ? null : _handleCreate,
              child: state.isLoading
                  ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Publish'),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildProgressIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (p) => setState(() => _currentPage = p),
              children: [
                _buildBasicInfoPage(),
                _buildScriptsPage(),
                _buildCharactersPage(),
                _buildStagesPage(),
                _buildReviewPage(),
              ],
            ),
          ),
          _buildNavigationButtons(),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: List.generate(5, (i) {
        final isActive    = i == _currentPage;
        final isCompleted = i < _currentPage;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 4,
            decoration: BoxDecoration(
              color: isCompleted
                  ? Theme.of(context).colorScheme.primary
                  : isActive
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.5)
                  : Colors.grey[700],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    ),
  );

  Widget _buildNavigationButtons() {
    final state = ref.watch(taikenCreateProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          if (_currentPage > 0) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _previousPage,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.primary),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 16),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: _currentPage == 4
                  ? (state.isLoading ? null : _handleCreate)
                  : _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(_currentPage == 4 ? 'Publish Taiken' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // PAGE 0 — Basic info
  // =========================================================================

  Widget _buildBasicInfoPage() {
    final state = ref.watch(taikenCreateProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Basic Information'),
          const SizedBox(height: 24),

          // Thumbnail
          GestureDetector(
            onTap: () =>
                ref.read(taikenCreateProvider.notifier).pickThumbnail(),
            child: Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: state.thumbnailFile != null
                  ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                      File(state.thumbnailFile!.path),
                      fit: BoxFit.cover))
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate,
                      size: 48, color: Colors.grey[600]),
                  const SizedBox(height: 8),
                  Text('Add Thumbnail',
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          _formField(
            controller: _titleController,
            label: 'Taiken Title',
            onChanged: (v) =>
                ref.read(taikenCreateProvider.notifier).updateTitle(v),
          ),
          const SizedBox(height: 14),

          _formField(
            controller: _descriptionController,
            label: 'Description',
            maxLines: 3,
            onChanged: (v) =>
                ref.read(taikenCreateProvider.notifier).updateDescription(v),
          ),
          const SizedBox(height: 14),

          // Domain
          _dropdownField<String>(
            label: 'Domain',
            value: state.domain.isEmpty ? null : state.domain,
            items: ['Science', 'Business', 'History', 'Technology', 'Arts'],
            onChanged: (v) {
              if (v != null)
                ref.read(taikenCreateProvider.notifier).updateDomain(v);
            },
          ),
          const SizedBox(height: 14),

          // Difficulty
          _dropdownField<String>(
            label: 'Difficulty',
            value: state.difficulty,
            items: ['beginner', 'intermediate', 'advanced'],
            displayBuilder: (v) => v[0].toUpperCase() + v.substring(1),
            onChanged: (v) {
              if (v != null)
                ref.read(taikenCreateProvider.notifier).updateDifficulty(v);
            },
          ),
          const SizedBox(height: 14),

          // Number of stages
          TextFormField(
            keyboardType: TextInputType.number,
            initialValue: state.totalStages.toString(),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface),
            decoration: _inputDecoration('Number of Stages'),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0)
                ref.read(taikenCreateProvider.notifier).setTotalStages(n);
            },
          ),
          const SizedBox(height: 20),

          // ★ Pass threshold slider
          _sectionSubtitle('Pass Threshold: ${state.passThreshold}%'),
          Slider(
            value: state.passThreshold.toDouble(),
            min: 30, max: 100, divisions: 14,
            label: '${state.passThreshold}%',
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (v) => ref
                .read(taikenCreateProvider.notifier)
                .updatePassThreshold(v.toInt()),
          ),
          const SizedBox(height: 6),
          Text(
            'Players need ${state.passThreshold}% correct answers to complete this Taiken.',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.5),
                fontSize: 12),
          ),
          const SizedBox(height: 20),

          // ★ Series section
          _buildSeriesSection(state),
        ],
      ),
    );
  }

  Widget _buildSeriesSection(TaikenCreateState state) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                const Icon(Icons.play_circle_outline,
                    color: Colors.purple, size: 18),
                const SizedBox(width: 8),
                Text('Part of a Series?',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600)),
              ]),
              Switch(
                value: _showSeriesFields,
                activeColor: Colors.purple,
                onChanged: (v) {
                  setState(() => _showSeriesFields = v);
                  if (!v) {
                    ref
                        .read(taikenCreateProvider.notifier)
                        .updateSeriesId(null);
                    ref
                        .read(taikenCreateProvider.notifier)
                        .updateEpisodeNumber(null);
                    _seriesIdController.clear();
                  }
                },
              ),
            ],
          ),
          if (_showSeriesFields) ...[
            const SizedBox(height: 12),
            Text(
              'Create or paste the series UUID from the taiken_series table.',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5),
                  fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _seriesIdController,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13),
              decoration: _inputDecoration('Series UUID'),
              onChanged: (v) => ref
                  .read(taikenCreateProvider.notifier)
                  .updateSeriesId(v.trim().isEmpty ? null : v.trim()),
            ),
            const SizedBox(height: 10),
            TextFormField(
              keyboardType: TextInputType.number,
              initialValue: state.episodeNumber?.toString(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13),
              decoration: _inputDecoration('Episode Number (1-based)'),
              onChanged: (v) {
                final n = int.tryParse(v);
                ref
                    .read(taikenCreateProvider.notifier)
                    .updateEpisodeNumber(n);
              },
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // PAGE 1 — Scripts (unchanged)
  // =========================================================================

  Widget _buildScriptsPage() => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Story Scripts'),
        const SizedBox(height: 6),
        Text('Write the intro and outro narratives for your Taiken',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.55),
                fontSize: 13)),
        const SizedBox(height: 24),
        _buildScriptField(
          label: 'Introduction',
          hint: 'Write the opening narrative that sets the stage...',
          controller: _introScriptController,
          onChanged: (v) => ref
              .read(taikenCreateProvider.notifier)
              .updateIntroScript(v),
        ),
        const SizedBox(height: 24),
        _buildScriptField(
          label: 'Success Outro',
          hint: 'What happens when the user succeeds...',
          controller: _outroSuccessController,
          onChanged: (v) => ref
              .read(taikenCreateProvider.notifier)
              .updateOutroSuccessScript(v),
        ),
        const SizedBox(height: 24),
        _buildScriptField(
          label: 'Failure Outro',
          hint: 'What happens when the user fails...',
          controller: _outroFailureController,
          onChanged: (v) => ref
              .read(taikenCreateProvider.notifier)
              .updateOutroFailureScript(v),
        ),
      ],
    ),
  );

  Widget _buildScriptField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required void Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionSubtitle(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style:
          TextStyle(color: Theme.of(context).colorScheme.onSurface),
          maxLines: 5,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.5)),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // =========================================================================
  // PAGE 2 — Characters  (★ added portrait side + isPlayer)
  // =========================================================================

  Widget _buildCharactersPage() {
    final state = ref.watch(taikenCreateProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Characters'),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(taikenCreateProvider.notifier).addCharacter(),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                    Theme.of(context).colorScheme.primary),
              ),
            ],
          ),
        ),
        Expanded(
          child: state.characters.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add,
                    size: 64,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.3)),
                const SizedBox(height: 16),
                Text('No characters yet',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.55),
                        fontSize: 16)),
              ],
            ),
          )
              : ListView.builder(
            padding:
            const EdgeInsets.symmetric(horizontal: 16),
            itemCount: state.characters.length,
            itemBuilder: (_, i) => _buildCharacterCard(i),
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterCard(int index) {
    final state = ref.watch(taikenCreateProvider);
    final c     = state.characters[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).cardColor,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Portrait image picker
                GestureDetector(
                  onTap: () => ref
                      .read(taikenCreateProvider.notifier)
                      .pickCharacterImage(index),
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[700]!),
                    ),
                    child: c.characterImage != null
                        ? ClipOval(
                        child: Image.file(
                            File(c.characterImage!.path),
                            fit: BoxFit.cover))
                        : Icon(Icons.person,
                        size: 36, color: Colors.grey[600]),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                            hintText: 'Character name',
                            border: InputBorder.none),
                        onChanged: (v) => ref
                            .read(taikenCreateProvider.notifier)
                            .updateCharacter(
                            index, c.copyWith(characterName: v)),
                      ),
                      TextField(
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface,
                            fontSize: 12),
                        decoration: const InputDecoration(
                            hintText: 'Description (optional)',
                            border: InputBorder.none),
                        onChanged: (v) => ref
                            .read(taikenCreateProvider.notifier)
                            .updateCharacter(index,
                            c.copyWith(characterDescription: v)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  color: Colors.red,
                  onPressed: () => ref
                      .read(taikenCreateProvider.notifier)
                      .removeCharacter(index),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ★ Portrait side toggle
            Row(
              children: [
                Text('Portrait side:',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                        fontSize: 13)),
                const SizedBox(width: 12),
                SegmentedButton<PortraitSide>(
                  segments: const [
                    ButtonSegment(
                        value: PortraitSide.left,
                        label: Text('Left'),
                        icon: Icon(Icons.align_horizontal_left, size: 14)),
                    ButtonSegment(
                        value: PortraitSide.right,
                        label: Text('Right'),
                        icon: Icon(Icons.align_horizontal_right,
                            size: 14)),
                  ],
                  selected: {c.portraitSide},
                  onSelectionChanged: (s) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateCharacter(index,
                      c.copyWith(portraitSide: s.first)),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: MaterialStateProperty.all(
                        const TextStyle(fontSize: 12)),
                  ),
                ),
                const Spacer(),
                // ★ isPlayer toggle
                Row(children: [
                  Text('Player',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.7),
                          fontSize: 13)),
                  Checkbox(
                    value: c.isPlayer,
                    onChanged: (v) => ref
                        .read(taikenCreateProvider.notifier)
                        .updateCharacter(index,
                        c.copyWith(isPlayer: v ?? false)),
                    activeColor:
                    Theme.of(context).colorScheme.primary,
                    materialTapTargetSize:
                    MaterialTapTargetSize.shrinkWrap,
                  ),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PAGE 3 — Stages  (★ mood, stageType, dialogue fields, gate fields)
  // =========================================================================

  Widget _buildStagesPage() {
    final state = ref.watch(taikenCreateProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _sectionTitle('Configure Stages'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: state.stages.length,
            itemBuilder: (_, i) => _buildStageCard(i),
          ),
        ),
      ],
    );
  }

  Widget _buildStageCard(int si) {
    final state = ref.watch(taikenCreateProvider);
    final stage = state.stages[si];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Theme.of(context).cardColor,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(
          'Stage ${si + 1}: ${stage.stageTitle}',
          style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                TextField(
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface),
                  controller:
                  TextEditingController(text: stage.stageTitle),
                  decoration: _inputDecoration('Stage Title'),
                  onChanged: (v) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateStage(si, stage.copyWith(stageTitle: v)),
                ),
                const SizedBox(height: 14),

                // ★ Mood dropdown
                _dropdownField<StageMood>(
                  label: 'Mood',
                  value: stage.mood,
                  items: StageMood.values,
                  displayBuilder: (v) =>
                  v.name[0].toUpperCase() + v.name.substring(1),
                  onChanged: (v) {
                    if (v != null)
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateStage(si, stage.copyWith(mood: v));
                  },
                ),
                const SizedBox(height: 14),

                // ★ Stage type dropdown
                _dropdownField<StageType>(
                  label: 'Stage Type',
                  value: stage.stageType,
                  items: StageType.values,
                  displayBuilder: (v) =>
                  v.name[0].toUpperCase() + v.name.substring(1),
                  onChanged: (v) {
                    if (v != null)
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateStage(si, stage.copyWith(stageType: v));
                  },
                ),
                const SizedBox(height: 14),

                // Scene image
                GestureDetector(
                  onTap: () => ref
                      .read(taikenCreateProvider.notifier)
                      .pickSceneImage(si),
                  child: Container(
                    width: double.infinity,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[850],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[700]!),
                    ),
                    child: stage.sceneImage != null
                        ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                            File(stage.sceneImage!.path),
                            fit: BoxFit.cover))
                        : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.landscape,
                            size: 40, color: Colors.grey[600]),
                        const SizedBox(height: 6),
                        Text('Add Scene / Background',
                            style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Dialogues
                _stageSubHeader(
                  'Dialogues',
                  onAdd: () => ref
                      .read(taikenCreateProvider.notifier)
                      .addDialogue(si),
                ),
                ...List.generate(stage.dialogues.length,
                        (di) => _buildDialogueField(si, di)),
                const SizedBox(height: 16),

                // Questions
                _stageSubHeader(
                  'Questions',
                  onAdd: () => ref
                      .read(taikenCreateProvider.notifier)
                      .addQuestion(si),
                ),
                ...List.generate(stage.questions.length,
                        (qi) => _buildQuestionField(si, qi)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogueField(int si, int di) {
    final state    = ref.watch(taikenCreateProvider);
    final dialogue = state.stages[si].dialogues[di];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Character picker
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: dialogue.characterTempId,
                  dropdownColor: Theme.of(context).cardColor,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12),
                  decoration: const InputDecoration(
                      labelText: 'Character',
                      isDense: true,
                      border: InputBorder.none),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Narrator')),
                    ...state.characters.map((c) => DropdownMenuItem(
                      value: c.tempId,
                      child: Text(c.characterName),
                    )),
                  ],
                  onChanged: (v) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateDialogue(
                      si, di, dialogue.copyWith(characterTempId: v)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 18),
                color: Colors.red,
                onPressed: () => ref
                    .read(taikenCreateProvider.notifier)
                    .removeDialogue(si, di),
              ),
            ],
          ),
          // Dialogue text
          TextField(
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface),
            maxLines: 2,
            decoration: const InputDecoration(
                hintText: 'Enter dialogue text...',
                border: InputBorder.none),
            onChanged: (v) => ref
                .read(taikenCreateProvider.notifier)
                .updateDialogue(
                si, di, dialogue.copyWith(dialogueText: v)),
          ),
          const Divider(height: 12),

          // ★ Emotion + typewriter speed row
          Row(
            children: [
              Expanded(
                child: _compactDropdown<DialogueEmotion>(
                  label: 'Emotion',
                  value: dialogue.emotion,
                  items: DialogueEmotion.values,
                  onChanged: (v) {
                    if (v != null)
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateDialogue(si, di,
                          dialogue.copyWith(emotion: v));
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _compactDropdown<TypewriterSpeed>(
                  label: 'Speed',
                  value: dialogue.typewriterSpeed,
                  items: TypewriterSpeed.values,
                  onChanged: (v) {
                    if (v != null)
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateDialogue(si, di,
                          dialogue.copyWith(typewriterSpeed: v));
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ★ Pause after (ms)
          TextFormField(
            keyboardType: TextInputType.number,
            initialValue: dialogue.pauseAfterMs > 0
                ? dialogue.pauseAfterMs.toString()
                : '',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Dramatic pause after (ms, 0 = none)',
              labelStyle: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.55),
                  fontSize: 11),
              isDense: true,
              border: InputBorder.none,
            ),
            onChanged: (v) {
              final ms = int.tryParse(v) ?? 0;
              ref.read(taikenCreateProvider.notifier).updateDialogue(
                  si, di, dialogue.copyWith(pauseAfterMs: ms));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionField(int si, int qi) {
    final state    = ref.watch(taikenCreateProvider);
    final question = state.stages[si].questions[qi];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                      hintText: 'Question text...',
                      border: InputBorder.none),
                  onChanged: (v) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateQuestion(
                      si, qi, question.copyWith(questionText: v)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 18),
                color: Colors.red,
                onPressed: () => ref
                    .read(taikenCreateProvider.notifier)
                    .removeQuestion(si, qi),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(question.options.length,
                  (oi) => _buildOptionField(si, qi, oi, question)),

          // Explanation
          TextField(
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12),
            decoration: const InputDecoration(
                hintText: 'Explanation (optional)',
                border: InputBorder.none),
            onChanged: (v) => ref
                .read(taikenCreateProvider.notifier)
                .updateQuestion(
                si, qi, question.copyWith(explanation: v)),
          ),

          const Divider(height: 14),

          // ★ Learning gate toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                const Icon(Icons.menu_book_rounded,
                    color: Colors.orange, size: 16),
                const SizedBox(width: 6),
                Text('Learning Gate',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
              Switch(
                value: question.hasLearningGate,
                activeColor: Colors.orange,
                onChanged: (v) => ref
                    .read(taikenCreateProvider.notifier)
                    .updateQuestion(si, qi,
                    question.copyWith(hasLearningGate: v)),
              ),
            ],
          ),
          if (question.hasLearningGate) ...[
            const SizedBox(height: 6),
            TextField(
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12),
              decoration: _inputDecoration('Gate domain (e.g. data_analysis)'),
              onChanged: (v) => ref
                  .read(taikenCreateProvider.notifier)
                  .updateQuestion(si, qi,
                  question.copyWith(gateContentDomain: v)),
            ),
            const SizedBox(height: 8),
            TextFormField(
              keyboardType: TextInputType.number,
              initialValue: question.gateSkipDelaySeconds.toString(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12),
              decoration: _inputDecoration('Skip delay (seconds)'),
              onChanged: (v) {
                final s = int.tryParse(v) ?? 5;
                ref
                    .read(taikenCreateProvider.notifier)
                    .updateQuestion(si, qi,
                    question.copyWith(gateSkipDelaySeconds: s));
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionField(
      int si, int qi, int oi, QuestionData question) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Radio<int>(
            value: oi,
            groupValue: question.correctOptionIndex,
            onChanged: (v) {
              if (v != null)
                ref
                    .read(taikenCreateProvider.notifier)
                    .updateQuestion(si, qi,
                    question.copyWith(correctOptionIndex: v));
            },
          ),
          Expanded(
            child: TextField(
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                  hintText: 'Option ${oi + 1}',
                  border: InputBorder.none),
              onChanged: (v) {
                final opts = List<String>.from(question.options);
                opts[oi] = v;
                ref
                    .read(taikenCreateProvider.notifier)
                    .updateQuestion(
                    si, qi, question.copyWith(options: opts));
              },
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // PAGE 4 — Review  (★ added series info + pass threshold)
  // =========================================================================

  Widget _buildReviewPage() {
    final state          = ref.watch(taikenCreateProvider);
    final totalQuestions = state.stages
        .fold<int>(0, (sum, s) => sum + s.questions.length);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Review & Publish'),
          const SizedBox(height: 24),
          _reviewRow('Title',           state.title),
          _reviewRow('Domain',          state.domain),
          _reviewRow('Difficulty',      state.difficulty),
          _reviewRow('Pass Threshold',  '${state.passThreshold}%'),   // ★
          _reviewRow('Stages',          '${state.totalStages}'),
          _reviewRow('Total Questions', '$totalQuestions'),
          _reviewRow('Characters',      '${state.characters.length}'),
          if (state.seriesId != null) ...[                             // ★
            _reviewRow('Series',        state.seriesId!.substring(0, 8) + '…'),
            if (state.episodeNumber != null)
              _reviewRow('Episode', '${state.episodeNumber}'),
          ],
          const SizedBox(height: 24),
          // Streak/points reminder (unchanged)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border:
              Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: Color(0xFFFF6B35)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Publishing earns 10 Plaro points!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface)),
                    Text(
                      'Players who complete your stages will also build their streak.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.55)),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.55),
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  // =========================================================================
  // SHARED HELPER WIDGETS
  // =========================================================================

  Widget _sectionTitle(String text) => Text(
    text,
    style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.bold),
  );

  Widget _sectionSubtitle(String text) => Text(
    text,
    style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w600),
  );

  Widget _stageSubHeader(String label, {required VoidCallback onAdd}) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.add_circle),
            color: Theme.of(context).colorScheme.primary,
            onPressed: onAdd,
          ),
        ],
      );

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(
        color: Theme.of(context)
            .colorScheme
            .onSurface
            .withOpacity(0.65)),
    filled: true,
    fillColor: Theme.of(context).cardColor,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _formField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    required void Function(String) onChanged,
  }) =>
      TextField(
        controller: controller,
        style:
        TextStyle(color: Theme.of(context).colorScheme.onSurface),
        maxLines: maxLines,
        decoration: _inputDecoration(label),
        onChanged: onChanged,
      );

  Widget _dropdownField<T>({
    required String label,
    required T? value,
    required List<T> items,
    String Function(T)? displayBuilder,
    required void Function(T?) onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        dropdownColor: Theme.of(context).cardColor,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface),
        decoration: _inputDecoration(label),
        items: items
            .map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(displayBuilder != null
              ? displayBuilder(item)
              : item.toString()),
        ))
            .toList(),
        onChanged: onChanged,
      );

  /// Compact inline dropdown for tight spaces (dialogue row).
  Widget _compactDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required void Function(T?) onChanged,
  }) =>
      DropdownButtonFormField<T>(
        value: value,
        dropdownColor: Theme.of(context).cardColor,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 12),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.55),
              fontSize: 11),
          isDense: true,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        items: items
            .map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(
            item is Enum
                ? (item as Enum).name
                : item.toString(),
            style: const TextStyle(fontSize: 12),
          ),
        ))
            .toList(),
        onChanged: onChanged,
      );
}