// =============================================================================
// taiken_create_page.dart  — FINAL
//
// Changes from previous version:
//
//   Page 0 – Basic Info
//     DOMAIN FIX: replaced the old hardcoded list
//       ['Science', 'Business', 'History', 'Technology', 'Arts']
//     with the full DomainConstants two-level picker (domain → subdomain),
//     matching post_page.dart exactly:
//       • _buildDomainDropdown()   — top-level domain with icon + label
//       • _buildSubdomainDropdown()— optional subdomain, only shown when a
//                                    domain with subdomains is selected
//       • Subdomain value overwrites top-level domain in the provider so the
//         stored value is as specific as possible (same behaviour as posts)
//       • _syncDomainPickersFromProvider() keeps the UI pickers in sync when
//         the AI fill button populates the domain field
//     REVIEW FIX: domain row now shows human-readable label instead of raw
//     snake_case value, looked up from DomainConstants.domains.
//
//   All other pages (Scripts, Characters, Stages) are unchanged.
//   Pass threshold, music cue, series section — all unchanged.
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../Viewmodels/taiken_create_provider.dart';
import '../Viewmodels/taiken_ai_provider.dart';
import '../views/taiken_ai_sheet.dart';
import '../models/taiken.dart';
import '../Widgets/taiken_asset_resolver.dart';
import '../constants/domain_constants.dart';

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
  final _introScriptController  = TextEditingController();
  final _outroSuccessController = TextEditingController();
  final _outroFailureController = TextEditingController();

  // Domain picker state — mirrors post_page.dart
  String? _selectedDomain;
  String? _selectedSubdomain;

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

  /// Returns true if the user has entered any content that would be lost.
  bool get _hasUnsavedContent {
    final s = ref.read(taikenCreateProvider);
    return s.title.isNotEmpty ||
        s.description.isNotEmpty ||
        s.introScript.isNotEmpty ||
        s.domain.isNotEmpty ||
        s.characters.isNotEmpty ||
        s.stages.any((st) =>
            st.dialogues.isNotEmpty || st.questions.isNotEmpty);
  }

  /// Shows a dialog asking the user what to do with unsaved content.
  /// Returns true if the page should be popped (discard).
  Future<bool> _confirmLeave() async {
    if (!_hasUnsavedContent) return true;

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Save as draft?'),
        content: const Text(
            'You have unsaved content. Would you like to discard it or stay to keep editing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            child: Text('Discard', style: TextStyle(color: Colors.red.shade400)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('Keep editing'),
          ),
        ],
      ),
    );
    return result == 'discard';
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the human-readable label for whatever domain value is stored in
  /// the provider, searching both top-level domains and all subdomains.
  String _domainLabel(String value) {
    for (final d in DomainConstants.domains) {
      if (d['value'] == value) return d['label']!;
    }
    for (final subs in DomainConstants.subdomains.values) {
      for (final s in subs) {
        if (s['value'] == value) return s['label']!;
      }
    }
    // Fallback: capitalise the raw value
    return value.isEmpty ? '—' : value[0].toUpperCase() + value.substring(1);
  }

  /// When the AI provider fills the domain field, reconcile the two local
  /// picker state variables so the dropdowns reflect the right selection.
  void _syncDomainPickersFromProvider(String domainValue) {
    // Check if it's a top-level domain value.
    for (final d in DomainConstants.domains) {
      if (d['value'] == domainValue) {
        setState(() {
          _selectedDomain    = domainValue;
          _selectedSubdomain = null;
        });
        return;
      }
    }
    // Check if it's a subdomain value.
    for (final entry in DomainConstants.subdomains.entries) {
      for (final s in entry.value) {
        if (s['value'] == domainValue) {
          setState(() {
            _selectedDomain    = entry.key;
            _selectedSubdomain = domainValue;
          });
          return;
        }
      }
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

    // Sync text controllers + domain pickers when AI generation fills the state.
    ref.listen<TaikenAiState>(taikenAiProvider, (_, next) {
      if (next.wasApplied) {
        final s = ref.read(taikenCreateProvider);
        _titleController.text        = s.title;
        _descriptionController.text  = s.description;
        _introScriptController.text  = s.introScript;
        _outroSuccessController.text = s.outroSuccessScript;
        _outroFailureController.text = s.outroFailureScript;
        _syncDomainPickersFromProvider(s.domain);
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave()) {
          if (mounted) {
            ref.read(taikenCreateProvider.notifier).reset();
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        title: Text('Create Taiken'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () async {
            if (await _confirmLeave()) {
              if (mounted) {
                ref.read(taikenCreateProvider.notifier).reset();
                Navigator.of(context).pop();
              }
            }
          },
        ),
        actions: [
          if (_currentPage < 4)
            _AiGenerateButton(
                onTap: () => TaikenAiSheet.show(context, ref)),
          if (_currentPage == 4)
            TextButton(
              onPressed: state.isLoading ? null : _handleCreate,
              child: state.isLoading
                  ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Publish'),
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
      ), // Scaffold
    ); // PopScope
  }

  Widget _buildProgressIndicator() => Container(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: List.generate(5, (i) {
        final isActive    = i == _currentPage;
        final isCompleted = i < _currentPage;
        return Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 4),
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
      padding: EdgeInsets.all(16),
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
                  padding: EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(
                      color: Theme.of(context).colorScheme.primary),
                ),
                child: Text('Back'),
              ),
            ),
            SizedBox(width: 16),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: _currentPage == 4
                  ? (state.isLoading ? null : _handleCreate)
                  : _nextPage,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
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
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Basic Information'),
          SizedBox(height: 24),

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
                  child: Image.file(File(state.thumbnailFile!.path),
                      fit: BoxFit.cover))
                  : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate,
                      size: 48, color: Colors.grey[600]),
                  SizedBox(height: 8),
                  Text('Add Thumbnail',
                      style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),

          _formField(
            controller: _titleController,
            label: 'Taiken Title',
            onChanged: (v) =>
                ref.read(taikenCreateProvider.notifier).updateTitle(v),
          ),
          SizedBox(height: 14),

          _formField(
            controller: _descriptionController,
            label: 'Description',
            maxLines: 3,
            onChanged: (v) =>
                ref.read(taikenCreateProvider.notifier).updateDescription(v),
          ),
          SizedBox(height: 14),

          // ── Domain + Subdomain (DomainConstants) ─────────────────────────
          _buildDomainDropdown(),
          _buildSubdomainDropdown(),

          // Difficulty
          _dropdownField<String>(
            label: 'Difficulty',
            value: state.difficulty,
            items: ['beginner', 'intermediate', 'advanced'],
            displayBuilder: (v) => v[0].toUpperCase() + v.substring(1),
            onChanged: (v) {
              if (v != null) {
                ref.read(taikenCreateProvider.notifier).updateDifficulty(v);
              }
            },
          ),
          SizedBox(height: 14),

          // Number of stages
          TextFormField(
            keyboardType: TextInputType.number,
            initialValue: state.totalStages.toString(),
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface),
            decoration: _inputDecoration('Number of Stages'),
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) {
                ref.read(taikenCreateProvider.notifier).setTotalStages(n);
              }
            },
          ),
          SizedBox(height: 20),

          // Pass threshold slider
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
          SizedBox(height: 6),
          Text(
            'Players need ${state.passThreshold}% correct answers to complete this Taiken.',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.5),
                fontSize: 12),
          ),
          SizedBox(height: 20),

          // Default background music
          _buildMusicCuePicker(
            label: 'Default Background Music',
            subtitle: 'Plays throughout the whole Taiken. Stages can override.',
            value: state.defaultMusicCue,
            onChanged: (v) => ref
                .read(taikenCreateProvider.notifier)
                .updateDefaultMusicCue(v),
          ),
          SizedBox(height: 20),

          // Series section
          _buildSeriesSection(state),
        ],
      ),
    );
  }

  // ── Domain dropdown — matches post_page.dart pattern exactly ─────────────

  Widget _buildDomainDropdown() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedDomain == null
              ? Colors.red.withOpacity(0.5)
              : Colors.grey[700]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Text(
                  'Domain',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(width: 4),
                Text(
                  '*',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedDomain,
                hint: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Select content domain',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4),
                      fontSize: 16,
                    ),
                  ),
                ),
                dropdownColor: Theme.of(context).cardColor,
                icon: Icon(Icons.arrow_drop_down,
                    color: Theme.of(context).colorScheme.onSurface),
                items: DomainConstants.domains.map((domain) {
                  return DropdownMenuItem<String>(
                    value: domain['value'],
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Text(
                            domain['icon']!,
                            style: TextStyle(fontSize: 20),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              domain['label']!,
                              style: TextStyle(
                                color:
                                Theme.of(context).colorScheme.onSurface,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? value) {
                  setState(() {
                    _selectedDomain    = value;
                    _selectedSubdomain = null;
                  });
                  if (value != null) {
                    // Write the top-level domain to the provider.
                    // If the user then picks a subdomain, that call overwrites
                    // this so the stored value is as specific as possible.
                    ref
                        .read(taikenCreateProvider.notifier)
                        .updateDomain(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Subdomain dropdown — mirrors post_page.dart ───────────────────────────

  Widget _buildSubdomainDropdown() {
    if (_selectedDomain == null) return SizedBox();

    final subdomains =
        DomainConstants.subdomains[_selectedDomain] ?? [];
    if (subdomains.isEmpty) return SizedBox();

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'Subdomain',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedSubdomain,
                hint: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Select subdomain (optional)',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.4),
                    ),
                  ),
                ),
                dropdownColor: Theme.of(context).cardColor,
                icon: Icon(Icons.arrow_drop_down,
                    color: Theme.of(context).colorScheme.onSurface),
                items: subdomains.map((sub) {
                  return DropdownMenuItem<String>(
                    value: sub['value'],
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        sub['label']!,
                        style: TextStyle(
                            color:
                            Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? value) {
                  setState(() => _selectedSubdomain = value);
                  if (value != null) {
                    // Subdomain overwrites the parent domain in the provider.
                    ref
                        .read(taikenCreateProvider.notifier)
                        .updateDomain(value);
                  } else {
                    // Subdomain cleared — fall back to the parent domain.
                    if (_selectedDomain != null) {
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateDomain(_selectedDomain!);
                    }
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Series section (unchanged) ────────────────────────────────────────────

  Widget _buildSeriesSection(TaikenCreateState state) {
    return Container(
      padding: EdgeInsets.all(14),
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
                Icon(Icons.play_circle_outline,
                    color: Colors.purple, size: 18),
                SizedBox(width: 8),
                Text('Part of a Series?',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w600)),
              ]),
              Switch(
                value: _showSeriesFields,
                activeThumbColor: Colors.purple,
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
            SizedBox(height: 12),
            Text(
              'Create or paste the series UUID from the taiken_series table.',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5),
                  fontSize: 12),
            ),
            SizedBox(height: 10),
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
            SizedBox(height: 10),
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
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Story Scripts'),
        SizedBox(height: 6),
        Text('Write the intro and outro narratives for your Taiken',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.55),
                fontSize: 13)),
        SizedBox(height: 24),
        _buildScriptField(
          label: 'Introduction',
          hint: 'Write the opening narrative that sets the stage...',
          controller: _introScriptController,
          onChanged: (v) => ref
              .read(taikenCreateProvider.notifier)
              .updateIntroScript(v),
        ),
        SizedBox(height: 24),
        _buildScriptField(
          label: 'Success Outro',
          hint: 'What happens when the user succeeds...',
          controller: _outroSuccessController,
          onChanged: (v) => ref
              .read(taikenCreateProvider.notifier)
              .updateOutroSuccessScript(v),
        ),
        SizedBox(height: 24),
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
        SizedBox(height: 8),
        TextField(
          controller: controller,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
            border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  // =========================================================================
  // PAGE 2 — Characters (unchanged)
  // =========================================================================

  Widget _buildCharactersPage() {
    final state = ref.watch(taikenCreateProvider);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Characters'),
              ElevatedButton.icon(
                onPressed: () =>
                    ref.read(taikenCreateProvider.notifier).addCharacter(),
                icon: Icon(Icons.add),
                label: Text('Add'),
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
                SizedBox(height: 16),
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
            padding: EdgeInsets.symmetric(horizontal: 16),
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
      margin: EdgeInsets.only(bottom: 16),
      color: Theme.of(context).cardColor,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    CharacterAvatar(
                      localFile: c.characterImage != null
                          ? File(c.characterImage!.path)
                          : null,
                      assetKey: c.assetKey,
                      size: 72,
                    ),
                    if (c.characterImage != null)
                      Positioned(
                        top: 0, right: 0,
                        child: GestureDetector(
                          onTap: () => ref
                              .read(taikenCreateProvider.notifier)
                              .updateCharacter(index,
                              c.copyWith(clearCharacterImage: true)),
                          child: Container(
                            width: 20, height: 20,
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.close,
                                color: Colors.white, size: 12),
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                            hintText: 'Character name',
                            border: InputBorder.none),
                        onChanged: (v) => ref
                            .read(taikenCreateProvider.notifier)
                            .updateCharacter(
                            index, c.copyWith(characterName: v)),
                      ),
                      TextField(
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 12),
                        decoration: InputDecoration(
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
                  icon: Icon(Icons.delete),
                  color: Colors.red,
                  onPressed: () => ref
                      .read(taikenCreateProvider.notifier)
                      .removeCharacter(index),
                ),
              ],
            ),
            SizedBox(height: 14),

            Text('Choose character',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: TaikenAssets.characters.length,
                separatorBuilder: (_, __) => SizedBox(width: 8),
                itemBuilder: (_, ci) {
                  final key = TaikenAssets.characters[ci];
                  return SizedBox(
                    width: 72,
                    child: CharacterPickerTile(
                      assetKey: key,
                      selected: c.assetKey == key &&
                          c.characterImage == null,
                      onTap: () => ref
                          .read(taikenCreateProvider.notifier)
                          .updateCharacter(
                          index,
                          c.copyWith(
                            assetKey:            key,
                            clearCharacterImage: true,
                          )),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(taikenCreateProvider.notifier)
                        .pickCharacterImage(index),
                    icon: Icon(Icons.upload_rounded, size: 16),
                    label: Text(
                      c.characterImage != null
                          ? 'Custom image ✓'
                          : 'Upload custom image (optional)',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      side: BorderSide(
                        color: c.characterImage != null
                            ? Colors.green
                            : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.3),
                      ),
                      foregroundColor: c.characterImage != null
                          ? Colors.green
                          : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ),
                ),
              ],
            ),
            if (c.characterImage != null) ...[
              SizedBox(height: 6),
              Text(
                'Custom upload overrides preset selection',
                style: TextStyle(
                    color: Colors.green.withOpacity(0.8),
                    fontSize: 11,
                    fontStyle: FontStyle.italic),
              ),
            ],
            SizedBox(height: 12),

            Row(
              children: [
                Text('Portrait side:',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.7),
                        fontSize: 13)),
                SizedBox(width: 12),
                SegmentedButton<PortraitSide>(
                  segments: const [
                    ButtonSegment(
                        value: PortraitSide.left,
                        label: Text('Left'),
                        icon: Icon(Icons.align_horizontal_left, size: 14)),
                    ButtonSegment(
                        value: PortraitSide.right,
                        label: Text('Right'),
                        icon: Icon(Icons.align_horizontal_right, size: 14)),
                  ],
                  selected: {c.portraitSide},
                  onSelectionChanged: (s) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateCharacter(
                      index, c.copyWith(portraitSide: s.first)),
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    textStyle: WidgetStateProperty.all(
                        TextStyle(fontSize: 12)),
                  ),
                ),
                const Spacer(),
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
                        .updateCharacter(
                        index, c.copyWith(isPlayer: v ?? false)),
                    activeColor: Theme.of(context).colorScheme.primary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
  // PAGE 3 — Stages (unchanged)
  // =========================================================================

  Widget _buildStagesPage() {
    final state = ref.watch(taikenCreateProvider);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _sectionTitle('Configure Stages'),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: 16),
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
      margin: EdgeInsets.only(bottom: 16),
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
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: stage.stageTitle,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface),
                  decoration: _inputDecoration('Stage Title'),
                  onChanged: (v) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateStage(si, stage.copyWith(stageTitle: v)),
                ),
                SizedBox(height: 14),

                _dropdownField<StageMood>(
                  label: 'Mood',
                  value: stage.mood,
                  items: StageMood.values,
                  displayBuilder: (v) =>
                  v.name[0].toUpperCase() + v.name.substring(1),
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateStage(si, stage.copyWith(mood: v));
                    }
                  },
                ),
                SizedBox(height: 14),

                _dropdownField<StageType>(
                  label: 'Stage Type',
                  value: stage.stageType,
                  items: StageType.values,
                  displayBuilder: (v) =>
                  v.name[0].toUpperCase() + v.name.substring(1),
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateStage(si, stage.copyWith(stageType: v));
                    }
                  },
                ),
                SizedBox(height: 14),

                // Background section
                _sectionSubtitle('Background'),
                SizedBox(height: 10),

                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 110,
                    child: BackgroundImage(
                      localFile: stage.sceneImage != null
                          ? File(stage.sceneImage!.path)
                          : null,
                      assetKey: stage.sceneImage == null
                          ? stage.backgroundKey
                          : null,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: stage.hasBackground
                            ? Padding(
                          padding: EdgeInsets.all(8),
                          child: GestureDetector(
                            onTap: () => ref
                                .read(taikenCreateProvider.notifier)
                                .updateStage(
                              si,
                              stage.copyWith(
                                clearSceneImage:    true,
                                clearBackgroundKey: true,
                              ),
                            ),
                            child: Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius:
                                BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.close,
                                  color: Colors.white, size: 14),
                            ),
                          ),
                        )
                            : Center(
                          child: Column(
                            mainAxisAlignment:
                            MainAxisAlignment.center,
                            children: [
                              Icon(Icons.landscape,
                                  size: 32,
                                  color: Colors.grey[500]),
                              SizedBox(height: 4),
                              Text('No background selected',
                                  style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10),

                Text('Preset backgrounds',
                    style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.6),
                        fontSize: 12)),
                SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount:   4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing:  8,
                    childAspectRatio: 1.4,
                  ),
                  itemCount: TaikenAssets.backgrounds.length,
                  itemBuilder: (_, bi) {
                    final key = TaikenAssets.backgrounds[bi];
                    return BackgroundThumbnail(
                      assetKey: key,
                      selected: stage.backgroundKey == key &&
                          stage.sceneImage == null,
                      onTap: () => ref
                          .read(taikenCreateProvider.notifier)
                          .updateStage(
                        si,
                        stage.copyWith(
                          backgroundKey:   key,
                          clearSceneImage: true,
                        ),
                      ),
                    );
                  },
                ),
                SizedBox(height: 10),

                OutlinedButton.icon(
                  onPressed: () => ref
                      .read(taikenCreateProvider.notifier)
                      .pickSceneImage(si),
                  icon: Icon(Icons.upload_rounded, size: 16),
                  label: Text(
                    stage.sceneImage != null
                        ? 'Custom background ✓'
                        : 'Upload custom background (optional)',
                    style: TextStyle(fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    side: BorderSide(
                      color: stage.sceneImage != null
                          ? Colors.green
                          : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.3),
                    ),
                    foregroundColor: stage.sceneImage != null
                        ? Colors.green
                        : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
                ),
                if (stage.sceneImage != null) ...[
                  SizedBox(height: 4),
                  Text(
                    'Custom upload overrides preset selection',
                    style: TextStyle(
                        color: Colors.green.withOpacity(0.8),
                        fontSize: 11,
                        fontStyle: FontStyle.italic),
                  ),
                ],
                SizedBox(height: 16),

                _buildMusicCuePicker(
                  label: 'Stage Music Override (optional)',
                  subtitle: 'Leave unset to use the Taiken default.',
                  value: stage.musicCue,
                  onChanged: (v) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateStage(si, stage.copyWith(musicCue: v)),
                ),
                SizedBox(height: 16),

                _stageSubHeader(
                  'Dialogues',
                  onAdd: () => ref
                      .read(taikenCreateProvider.notifier)
                      .addDialogue(si),
                ),
                ...List.generate(stage.dialogues.length,
                        (di) => _buildDialogueField(si, di)),
                SizedBox(height: 16),

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
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[850],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: dialogue.characterTempId,
                  dropdownColor: Theme.of(context).cardColor,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12),
                  decoration: InputDecoration(
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
                icon: Icon(Icons.delete, size: 18),
                color: Colors.red,
                onPressed: () => ref
                    .read(taikenCreateProvider.notifier)
                    .removeDialogue(si, di),
              ),
            ],
          ),
          TextField(
            style:
            TextStyle(color: Theme.of(context).colorScheme.onSurface),
            maxLines: 2,
            decoration: InputDecoration(
                hintText: 'Enter dialogue text...',
                border: InputBorder.none),
            onChanged: (v) => ref
                .read(taikenCreateProvider.notifier)
                .updateDialogue(
                si, di, dialogue.copyWith(dialogueText: v)),
          ),
          const Divider(height: 12),

          Row(
            children: [
              Expanded(
                child: _compactDropdown<DialogueEmotion>(
                  label: 'Emotion',
                  value: dialogue.emotion,
                  items: DialogueEmotion.values,
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateDialogue(
                          si, di, dialogue.copyWith(emotion: v));
                    }
                  },
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: _compactDropdown<TypewriterSpeed>(
                  label: 'Speed',
                  value: dialogue.typewriterSpeed,
                  items: TypewriterSpeed.values,
                  onChanged: (v) {
                    if (v != null) {
                      ref
                          .read(taikenCreateProvider.notifier)
                          .updateDialogue(si, di,
                          dialogue.copyWith(typewriterSpeed: v));
                    }
                  },
                ),
              ),
            ],
          ),
          SizedBox(height: 8),

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
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(12),
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
                  decoration: InputDecoration(
                      hintText: 'Question text...',
                      border: InputBorder.none),
                  onChanged: (v) => ref
                      .read(taikenCreateProvider.notifier)
                      .updateQuestion(
                      si, qi, question.copyWith(questionText: v)),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete, size: 18),
                color: Colors.red,
                onPressed: () => ref
                    .read(taikenCreateProvider.notifier)
                    .removeQuestion(si, qi),
              ),
            ],
          ),
          SizedBox(height: 8),
          ...List.generate(question.options.length,
                  (oi) => _buildOptionField(si, qi, oi, question)),

          TextField(
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12),
            decoration: InputDecoration(
                hintText: 'Explanation (optional)',
                border: InputBorder.none),
            onChanged: (v) => ref
                .read(taikenCreateProvider.notifier)
                .updateQuestion(
                si, qi, question.copyWith(explanation: v)),
          ),

          const Divider(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.menu_book_rounded,
                    color: Colors.orange, size: 16),
                SizedBox(width: 6),
                Text('Learning Gate',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
              Switch(
                value: question.hasLearningGate,
                activeThumbColor: Colors.orange,
                onChanged: (v) => ref
                    .read(taikenCreateProvider.notifier)
                    .updateQuestion(
                    si, qi, question.copyWith(hasLearningGate: v)),
              ),
            ],
          ),
          if (question.hasLearningGate) ...[
            SizedBox(height: 6),
            TextField(
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12),
              decoration:
              _inputDecoration('Gate domain (e.g. data_science)'),
              onChanged: (v) => ref
                  .read(taikenCreateProvider.notifier)
                  .updateQuestion(
                  si, qi, question.copyWith(gateContentDomain: v)),
            ),
            SizedBox(height: 8),
            TextFormField(
              keyboardType: TextInputType.number,
              initialValue: question.gateSkipDelaySeconds.toString(),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 12),
              decoration: _inputDecoration('Skip delay (seconds)'),
              onChanged: (v) {
                final s = int.tryParse(v) ?? 5;
                ref.read(taikenCreateProvider.notifier).updateQuestion(
                    si, qi, question.copyWith(gateSkipDelaySeconds: s));
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
      margin: EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Radio<int>(
            value: oi,
            groupValue: question.correctOptionIndex,
            onChanged: (v) {
              if (v != null) {
                ref.read(taikenCreateProvider.notifier).updateQuestion(
                    si, qi, question.copyWith(correctOptionIndex: v));
              }
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
                ref.read(taikenCreateProvider.notifier).updateQuestion(
                    si, qi, question.copyWith(options: opts));
              },
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // PAGE 4 — Review
  // =========================================================================

  Widget _buildReviewPage() {
    final state          = ref.watch(taikenCreateProvider);
    final totalQuestions = state.stages
        .fold<int>(0, (sum, s) => sum + s.questions.length);

    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Review & Publish'),
          SizedBox(height: 24),
          _reviewRow('Title',           state.title),
          // Use human-readable label from DomainConstants
          _reviewRow('Domain',          _domainLabel(state.domain)),
          _reviewRow('Difficulty',      state.difficulty),
          _reviewRow('Pass Threshold',  '${state.passThreshold}%'),
          _reviewRow('Stages',          '${state.totalStages}'),
          _reviewRow('Total Questions', '$totalQuestions'),
          _reviewRow('Characters',      '${state.characters.length}'),
          if (state.defaultMusicCue != null)
            _reviewRow('Music',         state.defaultMusicCue![0]
                .toUpperCase() +
                state.defaultMusicCue!.substring(1)),
          if (state.seriesId != null) ...[
            _reviewRow('Series',  '${state.seriesId!.substring(0, 8)}…'),
            if (state.episodeNumber != null)
              _reviewRow('Episode', '${state.episodeNumber}'),
          ],
          SizedBox(height: 24),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFFF6B35).withOpacity(0.3)),
            ),
            child: Row(children: [
              Icon(Icons.local_fire_department_rounded,
                  color: Color(0xFFFF6B35)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Publishing earns 10 Plaro points!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                            Theme.of(context).colorScheme.onSurface)),
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
    padding: EdgeInsets.only(bottom: 12),
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
            icon: Icon(Icons.add_circle),
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
    border:
    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _formField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    required void Function(String) onChanged,
  }) =>
      TextField(
        controller: controller,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        maxLines: maxLines,
        decoration: _inputDecoration(label),
        onChanged: onChanged,
      );

  // ── Music cue picker ───────────────────────────────────────────────────────

  static const _musicCues = ['ambient', 'study', 'focus'];
  static const _musicIcons = {
    'ambient': Icons.waves_rounded,
    'study':   Icons.auto_stories_rounded,
    'focus':   Icons.psychology_rounded,
  };
  static const _musicDescriptions = {
    'ambient': 'Soft, relaxing atmosphere',
    'study':   'Calm, note-taking vibe',
    'focus':   'Deep concentration',
  };

  Widget _buildMusicCuePicker({
    required String label,
    required String subtitle,
    required String? value,
    required void Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionSubtitle(label),
        SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.5),
                fontSize: 12)),
        SizedBox(height: 10),
        Row(
          children: [
            _musicChip(
              key:      null,
              label:    'None',
              icon:     Icons.music_off_rounded,
              selected: value == null,
              onTap:    () => onChanged(null),
            ),
            SizedBox(width: 8),
            ..._musicCues.map((cue) => Padding(
              padding: EdgeInsets.only(right: 8),
              child: _musicChip(
                key:      cue,
                label:    cue[0].toUpperCase() + cue.substring(1),
                icon:     _musicIcons[cue]!,
                selected: value == cue,
                onTap:    () => onChanged(cue),
              ),
            )),
          ],
        ),
        if (value != null) ...[
          SizedBox(height: 6),
          Row(children: [
            Icon(Icons.info_outline,
                size: 13,
                color: Theme.of(context).colorScheme.primary),
            SizedBox(width: 4),
            Text(
              _musicDescriptions[value] ?? '',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12),
            ),
          ]),
        ],
      ],
    );
  }

  Widget _musicChip({
    required String? key,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? primary.withOpacity(0.15)
              : Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? primary : Colors.grey[700]!,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected
                    ? primary
                    : Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.5)),
            SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                    selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? primary
                        : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6))),
          ],
        ),
      ),
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required T? value,
    required List<T> items,
    String Function(T)? displayBuilder,
    required void Function(T?) onChanged,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        dropdownColor: Theme.of(context).cardColor,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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

  Widget _compactDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required void Function(T?) onChanged,
  }) =>
      DropdownButtonFormField<T>(
        initialValue: value,
        dropdownColor: Theme.of(context).cardColor,
        style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface, fontSize: 12),
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
          EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          filled: true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
          border:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        items: items
            .map((item) => DropdownMenuItem<T>(
          value: item,
          child: Text(
            item is Enum
                ? (item as Enum).name
                : item.toString(),
            style: TextStyle(fontSize: 12),
          ),
        ))
            .toList(),
        onChanged: onChanged,
      );
}

// =============================================================================
// AI Generate Button — shown in AppBar on pages 0–3
// =============================================================================

class _AiGenerateButton extends ConsumerWidget {
  final VoidCallback onTap;
  const _AiGenerateButton({required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGenerating =
    ref.watch(taikenAiProvider.select((s) => s.isGenerating));
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: TextButton.icon(
        onPressed: isGenerating ? null : onTap,
        icon: isGenerating
            ? SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Color(0xFF6C63FF)),
        )
            : Icon(Icons.auto_awesome,
            color: Color(0xFF6C63FF), size: 18),
        label: Text(
          isGenerating ? 'Generating…' : 'AI Fill',
          style: TextStyle(
            color:      Color(0xFF6C63FF),
            fontWeight: FontWeight.bold,
            fontSize:   13,
          ),
        ),
      ),
    );
  }
}