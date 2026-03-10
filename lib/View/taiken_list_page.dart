// =============================================================================
// taiken_list_page.dart  — FINAL
//
// Changes from previous version (Phase E additions):
//   • _buildTaikenCard
//       – Completion checkmark overlay (green banner) when status == 'completed'
//       – In-progress indicator (progress bar) when status == 'in_progress'
//       – Lock overlay with domain requirement text when taiken is locked
//       – Episode badge (purple pill) when taiken is part of a series
//       – Series episode number shown under the title
//
//   All existing behaviour (search, filters, scroll pagination,
//   StreakCard, StreakBadge, FAB, skeleton loader) is preserved exactly.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../Model/taiken.dart';
import '../ViewModel/taiken_list_provider.dart';
import 'taiken_experience_page.dart';
import 'taiken_create_page.dart';
import 'widgets/streak_widgets.dart';

class TaikensListPage extends ConsumerStatefulWidget {
  const TaikensListPage({super.key});

  @override
  ConsumerState<TaikensListPage> createState() => _TaikensListPageState();
}

class _TaikensListPageState extends ConsumerState<TaikensListPage> {
  final ScrollController   _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taikenListProvider.notifier).loadTaikens();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      ref.read(taikenListProvider.notifier).loadTaikens();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taikenListProvider);

    return MilestoneToastListener(
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
          title: const Text('Taikens'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: const StreakBadge(size: 18)),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const TaikenCreatePage())),
          icon: const Icon(Icons.add),
          label: const Text('Create'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: StreakCard(),
            ),
            _buildSearchAndFilter(),
            Expanded(
              child: state.isLoading && state.taikens.isEmpty
                  ? _buildSkeletonLoader()
                  : state.taikens.isEmpty
                  ? _buildEmptyState()
                  : _buildTaikenList(state),
            ),
          ],
        ),
      ),
    );
  }

  // ── Search + filter (unchanged) ───────────────────────────────────────────

  Widget _buildSearchAndFilter() {
    final state = ref.watch(taikenListProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Search Taikens...',
              hintStyle: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5)),
              prefixIcon: Icon(Icons.search,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.7)),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
            onSubmitted: (q) =>
                ref.read(taikenListProvider.notifier).searchTaikens(q),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFilterChip(
                  'Domain',
                  state.filterDomain,
                  ['Science', 'Business', 'History', 'Technology', 'Arts'],
                      (v) => ref
                      .read(taikenListProvider.notifier)
                      .filterByDomain(v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterChip(
                  'Difficulty',
                  state.filterDifficulty,
                  ['beginner', 'intermediate', 'advanced'],
                      (v) => ref
                      .read(taikenListProvider.notifier)
                      .filterByDifficulty(v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String? currentValue,
      List<String> options, Function(String?) onSelect) {
    return PopupMenuButton<String>(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: currentValue != null
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(currentValue ?? label,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14)),
            Icon(Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.onSurface),
          ],
        ),
      ),
      onSelected: onSelect,
      itemBuilder: (_) => [
        const PopupMenuItem(value: null, child: Text('All')),
        ...options.map((o) => PopupMenuItem(value: o, child: Text(o))),
      ],
    );
  }

  // ── List ──────────────────────────────────────────────────────────────────

  Widget _buildTaikenList(TaikenListState state) {
    return RefreshIndicator(
      onRefresh: () async =>
          ref.read(taikenListProvider.notifier).loadTaikens(refresh: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.taikens.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (_, index) {
          if (index == state.taikens.length) {
            return const Center(
              child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator()),
            );
          }
          return _buildTaikenCard(state.taikens[index], state);
        },
      ),
    );
  }

  // ── Card (Phase E additions highlighted with // ★) ────────────────────────

  Widget _buildTaikenCard(Taiken taiken, TaikenListState state) {
    final isLocked     = state.isLocked(taiken.taikenId);    // ★
    final isCompleted  = state.isCompleted(taiken.taikenId); // ★
    final isInProgress = state.isInProgress(taiken.taikenId); // ★
    final progress     = state.userProgressMap[taiken.taikenId]; // ★

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isLocked
            ? () => _showLockedDialog(taiken) // ★ locked → show dialog
            : () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                TaikenExperiencePage(taikenId: taiken.taikenId),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Stack(                          // ★ Stack for overlays
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Thumbnail ────────────────────────────────────────────
                if (taiken.thumbnailUrl != null)
                  Stack(                       // ★ Stack for episode badge
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                        child: Image.network(
                          taiken.thumbnailUrl!,
                          width: double.infinity,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 160,
                            color: Colors.grey[800],
                            child: const Icon(Icons.image_not_supported,
                                size: 48),
                          ),
                        ),
                      ),
                      // ★ Episode badge
                      if (taiken.isPartOfSeries &&
                          taiken.episodeNumber != null)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.purple.withOpacity(0.88),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_circle_outline,
                                    color: Colors.white, size: 12),
                                const SizedBox(width: 4),
                                Text(
                                  'EP ${taiken.episodeNumber}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // ★ Completed banner on thumbnail
                      if (isCompleted)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text('Completed',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),

                // ── Content ───────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ★ Series label above title
                      if (taiken.isPartOfSeries &&
                          taiken.episodeNumber != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Episode ${taiken.episodeNumber}',
                            style: TextStyle(
                                color: Colors.purple[300],
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5),
                          ),
                        ),

                      Text(
                        taiken.title,
                        style: TextStyle(
                            color:
                            Theme.of(context).colorScheme.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        taiken.description,
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.65),
                            fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),

                      // Chips row
                      Row(
                        children: [
                          _infoChip(taiken.domain, Icons.category),
                          const SizedBox(width: 6),
                          _infoChip(taiken.difficulty,
                              Icons.signal_cellular_alt),
                          const Spacer(),
                          Row(children: [
                            const Icon(Icons.star,
                                color: Colors.amber, size: 14),
                            const SizedBox(width: 3),
                            Text(
                              taiken.averageRating.toStringAsFixed(1),
                              style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  fontSize: 13),
                            ),
                          ]),
                        ],
                      ),
                      const SizedBox(height: 6),

                      Text(
                        '${taiken.totalStages} Stages \u2022 '
                            '${taiken.totalQuestions} Questions',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.45),
                            fontSize: 11),
                      ),

                      // ★ In-progress accuracy bar
                      if (isInProgress && progress != null) ...[
                        const SizedBox(height: 10),
                        _buildProgressBar(progress, taiken),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            // ★ Lock overlay
            if (isLocked) _buildLockOverlay(taiken),
          ],
        ),
      ),
    );
  }

  // ★ Progress bar shown on in-progress cards
  Widget _buildProgressBar(TaikenProgress progress, Taiken taiken) {
    final total    = taiken.totalQuestions;
    final answered = progress.questionsAnswered;
    final value    = total == 0 ? 0.0 : answered / total;
    final passing  = progress.accuracyPercentage >= taiken.passThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$answered/$total answered',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.5),
                  fontSize: 10)),
          Text('${progress.accuracyPercentage.toStringAsFixed(0)}%',
              style: TextStyle(
                  color: passing ? Colors.green : Colors.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 4,
            backgroundColor: Colors.grey.withOpacity(0.25),
            valueColor: AlwaysStoppedAnimation<Color>(
                passing ? Colors.green : Colors.orange),
          ),
        ),
      ],
    );
  }

  // ★ Translucent lock overlay
  Widget _buildLockOverlay(Taiken taiken) {
    final req    = taiken.domainUnlockRequirement;
    final domain = req?['domain'] as String? ?? 'this domain';
    final min    = (req?['min_taikens_passed'] as num?)?.toInt() ?? 1;

    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          color: Colors.black.withOpacity(0.72),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_rounded,
                    color: Colors.white70, size: 26),
              ),
              const SizedBox(height: 10),
              Text(
                'Locked',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'Complete $min Taiken${min > 1 ? 's' : ''} in "$domain" to unlock',
                  style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ★ Locked-taiken tapped → bottom sheet explanation
  void _showLockedDialog(Taiken taiken) {
    final req    = taiken.domainUnlockRequirement;
    final domain = req?['domain'] as String? ?? 'this domain';
    final min    = (req?['min_taikens_passed'] as num?)?.toInt() ?? 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Icon(Icons.lock_rounded, size: 40, color: Colors.orange),
            const SizedBox(height: 16),
            Text(
              taiken.title,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Complete $min Taiken${min > 1 ? 's' : ''} in the "$domain" domain first to unlock this story.',
              style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.65),
                  fontSize: 14,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Optionally filter to the prerequisite domain.
                  ref
                      .read(taikenListProvider.notifier)
                      .filterByDomain(domain);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                  Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Show "$domain" Taikens'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shared small widgets (unchanged) ──────────────────────────────────────

  Widget _infoChip(String label, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12,
          color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 4),
      Text(label,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 11,
              fontWeight: FontWeight.w500)),
    ]),
  );

  Widget _buildSkeletonLoader() => ListView.builder(
    itemCount: 5,
    itemBuilder: (_, __) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 260,
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12)),
    ),
  );

  Widget _buildEmptyState() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.school_outlined,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withOpacity(0.3)),
        const SizedBox(height: 16),
        Text('No Taikens found',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.65),
                fontSize: 18,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text('Be the first to create one!',
            style: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.45),
                fontSize: 14)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(
                  builder: (_) => const TaikenCreatePage())),
          icon: const Icon(Icons.add),
          label: const Text('Create a Taiken'),
          style: ElevatedButton.styleFrom(
            backgroundColor:
            Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    ),
  );
}