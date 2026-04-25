// =============================================================================
// taiken_list_page.dart  — REDESIGN
//
// UX/UI improvements:
//   • StreakCard removed from the main scroll body.
//     Instead, tapping the flame badge in the AppBar opens a smooth
//     bottom-sheet overlay (like Duolingo's streak panel) with full card detail.
//   • New SliverAppBar with a gradient hero section — shows greeting + XP bar.
//   • Cards redesigned: wider thumbnail, sharper typography, pill tags,
//     a glow accent on the leading edge, and smooth hero transitions.
//   • Filter row replaced with a horizontal scrollable chip strip.
//   • Skeleton loader uses shimmer-style animated containers.
//   • Pull-to-refresh uses a custom colour to match brand orange.
//   • All existing logic (search, pagination, lock overlays, progress bars)
//     is preserved exactly.
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/taiken.dart';
import '../Viewmodels/taiken_list_provider.dart';
import 'taiken_experience_page.dart';
import 'taiken_create_page.dart';
import 'widgets/streak_widgets.dart';
import 'profile.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Colours / design tokens (keep in sync with your theme)
// ─────────────────────────────────────────────────────────────────────────────

const _kBrand       = Color(0xFFFF6B35); // brand orange (matches streak)
const _kBrandLight  = Color(0xFFFF8C5A);
const _kBrandDark   = Color(0xFFD94F1A);
const _kGold        = Color(0xFFFFB800);
const _kSuccess     = Color(0xFF22C55E);
const _kPurple      = Color(0xFF8B5CF6);
const _kCardRadius  = 16.0;

// ─────────────────────────────────────────────────────────────────────────────
// Main page
// ─────────────────────────────────────────────────────────────────────────────

class TaikensListPage extends ConsumerStatefulWidget {
  const TaikensListPage({super.key});

  @override
  ConsumerState<TaikensListPage> createState() => _TaikensListPageState();
}

class _TaikensListPageState extends ConsumerState<TaikensListPage>
    with SingleTickerProviderStateMixin {
  final ScrollController      _scrollController  = ScrollController();
  final TextEditingController _searchController  = TextEditingController();
  Timer? _searchDebounce;

  // Animated entrance for the header
  late final AnimationController _headerAnim;
  late final Animation<double>   _headerFade;
  late final Animation<Offset>   _headerSlide;

  @override
  void initState() {
    super.initState();

    _headerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _headerFade  = CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _headerAnim, curve: Curves.easeOut));

    _scrollController.addListener(_onScroll);
    // Listener keeps the clear-button reactive without relying on onChanged setState.
    _searchController.addListener(() => setState(() {}));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(taikenListProvider.notifier).loadTaikens();
      _headerAnim.forward();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _headerAnim.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      ref.read(taikenListProvider.notifier).loadTaikens();
    }
  }

  // ── Streak bottom sheet ──────────────────────────────────────────────────

  void _showStreakSheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _StreakBottomSheet(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taikenListProvider);
    final theme = Theme.of(context);

    return MilestoneToastListener(
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        // // ── FAB ─────────────────────────────────────────────────────────────
        // floatingActionButton: _CreateFab(),
        // // ── Body: CustomScrollView with sliver header ────────────────────────
        body: RefreshIndicator(
          color: _kBrand,
          onRefresh: () async =>
              ref.read(taikenListProvider.notifier).loadTaikens(refresh: true),
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Sliver App Bar ────────────────────────────────────────────
              _buildSliverAppBar(),

              // ── Search + filter strip ─────────────────────────────────────
              SliverToBoxAdapter(child: _buildSearchAndFilter(state)),

              // ── Content ───────────────────────────────────────────────────
              if (state.isLoading && state.taikens.isEmpty)
                SliverFillRemaining(child: _buildSkeletonLoader())
              else if (state.taikens.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else ...[
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (ctx, index) {
                        if (index == state.taikens.length) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(color: _kBrand),
                            ),
                          );
                        }
                        return _buildTaikenCard(state.taikens[index], state);
                      },
                      childCount:
                      state.taikens.length + (state.isLoadingMore ? 1 : 0),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Sliver App Bar ─────────────────────────────────────────────────────────

  SliverAppBar _buildSliverAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 120,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      actions: [
        // Streak badge → tapping opens the overlay panel
        GestureDetector(
          onTap: _showStreakSheet,
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _kBrand.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBrand.withOpacity(0.3)),
            ),
            child: const StreakBadge(size: 18),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: SlideTransition(
          position: _headerSlide,
          child: FadeTransition(
            opacity: _headerFade,
            child: _HeaderHero(),
          ),
        ),
        titlePadding: const EdgeInsets.only(left: 20, bottom: 14),
        title: Text(
          'Taikens',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.5,
          ),
        ),
      ),
    );
  }

  // ── Search + filter ────────────────────────────────────────────────────────

  Widget _buildSearchAndFilter(TaikenListState state) {
    final domains = [
      'technology', 'design_creativity', 'business_finance',
      'science_research', 'engineering', 'arts_culture',
    ];
    final difficulties = ['beginner', 'intermediate', 'advanced'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Search experiences…',
                hintStyle: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.4),
                    fontSize: 15),
                prefixIcon: Icon(Icons.search_rounded,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.5),
                    size: 22),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _searchController.clear();
                    ref.read(taikenListProvider.notifier).searchTaikens('');
                  },
                )
                    : null,
                filled: true,
                fillColor: Colors.transparent,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              // Live search with 400 ms debounce — no need to press Enter.
              onChanged: (q) {
                setState(() {}); // redraw clear button immediately
                _searchDebounce?.cancel();
                _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                  ref.read(taikenListProvider.notifier).searchTaikens(q.trim());
                });
              },
              onSubmitted: (q) {
                // Immediate search on keyboard submit — cancel pending debounce.
                _searchDebounce?.cancel();
                ref.read(taikenListProvider.notifier).searchTaikens(q.trim());
              },
            ),
          ),

          const SizedBox(height: 12),

          // Horizontal chip strip — Difficulty
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: 'All',
                  selected: state.filterDifficulty == null &&
                      state.filterDomain == null,
                  onTap: () =>
                      ref.read(taikenListProvider.notifier).clearFilters(),
                ),
                const SizedBox(width: 6),
                ...difficulties.map((d) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: _capitalize(d),
                    selected: state.filterDifficulty == d,
                    accent: _difficultyColor(d),
                    onTap: () => ref
                        .read(taikenListProvider.notifier)
                        .filterByDifficulty(
                        state.filterDifficulty == d ? null : d),
                  ),
                )),
                const SizedBox(width: 6),
                ...domains.map((d) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _FilterChip(
                    label: _domainLabel(d),
                    selected: state.filterDomain == d,
                    accent: _kBrand,
                    onTap: () => ref
                        .read(taikenListProvider.notifier)
                        .filterByDomain(
                        state.filterDomain == d ? null : d),
                  ),
                )),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // ── Taiken card ────────────────────────────────────────────────────────────

  Widget _buildTaikenCard(Taiken taiken, TaikenListState state) {
    final isLocked     = state.isLocked(taiken.taikenId);
    final isCompleted  = state.isCompleted(taiken.taikenId);
    final isInProgress = state.isInProgress(taiken.taikenId);
    final progress     = state.userProgressMap[taiken.taikenId];
    final theme        = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: GestureDetector(
        onTap: isLocked
            ? () => _showLockedDialog(taiken)
            : () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                TaikenExperiencePage(taikenId: taiken.taikenId),
          ),
        ),
        // The card is a ClipRRect so the lock overlay rounds correctly.
        // The Stack lives *inside* the Container so Flutter always has a
        // concrete size for the Stack before painting Positioned children.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kCardRadius),
          child: Container(
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(_kCardRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.07),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
              border: isCompleted
                  ? Border(left: BorderSide(color: _kSuccess, width: 3.5))
                  : isInProgress
                  ? Border(left: BorderSide(color: _kBrand, width: 3.5))
                  : null,
            ),
            // Stack here is sized by the Column (non-positioned child),
            // so Positioned.fill always has a valid parent size.
            child: Stack(
              children: [
                // ── Card content column ───────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Thumbnail ──────────────────────────────────────
                    if (taiken.thumbnailUrl != null)
                      _ThumbnailSection(
                        taiken:      taiken,
                        isCompleted: isCompleted,
                      ),

                    // ── Body ──────────────────────────────────────────
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        // Extra top padding when no thumbnail but completed
                        // badge needs breathing room (badge is in-flow below).
                        taiken.thumbnailUrl == null && isCompleted ? 44 : 14,
                        16,
                        14,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Series label
                          if (taiken.isPartOfSeries &&
                              taiken.episodeNumber != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                'Episode ${taiken.episodeNumber}',
                                style: TextStyle(
                                  color: _kPurple.withOpacity(0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),

                          // Title
                          Text(
                            taiken.title,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 5),

                          // Description
                          Text(
                            taiken.description,
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.55),
                              fontSize: 13,
                              height: 1.45,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),

                          // Tag row
                          Row(
                            children: [
                              _Tag(
                                label: _domainLabel(taiken.domain),
                                color: _kBrand,
                              ),
                              const SizedBox(width: 6),
                              _Tag(
                                label: _capitalize(taiken.difficulty),
                                color: _difficultyColor(taiken.difficulty),
                              ),
                              const Spacer(),
                              Row(children: [
                                const Icon(Icons.star_rounded,
                                    color: _kGold, size: 14),
                                const SizedBox(width: 3),
                                Text(
                                  taiken.averageRating.toStringAsFixed(1),
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ]),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Meta row
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => OtherProfileScreen(
                                        userId: taiken.creatorId),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.grey[800],
                                      backgroundImage: (taiken.creatorProfilePic !=
                                          null &&
                                          taiken.creatorProfilePic!
                                              .isNotEmpty)
                                          ? CachedNetworkImageProvider(
                                          taiken.creatorProfilePic!)
                                          : const AssetImage(
                                          'assets/plaro_logo.png')
                                      as ImageProvider,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      taiken.creatorUsername ?? 'Unknown Creator',
                                      style: TextStyle(
                                        color: Colors.blue[300],
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 14,
                                      color: theme.colorScheme.onSurface
                                          .withOpacity(0.35),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${taiken.totalStages} Stages \u2022 '
                                    '${taiken.totalQuestions} Questions',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withOpacity(0.38),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),

                          // In-progress bar
                          if (isInProgress && progress != null) ...[
                            const SizedBox(height: 12),
                            _buildProgressBar(progress, taiken),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // ── Completed badge (no-thumbnail cards only) ──────────
                // Positioned so it doesn't affect column layout.
                if (taiken.thumbnailUrl == null && isCompleted)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: _Pill(
                      label: 'Completed',
                      icon:  Icons.check_circle_rounded,
                      color: _kSuccess,
                    ),
                  ),

                // ── Lock overlay ───────────────────────────────────────
                if (isLocked) _buildLockOverlay(taiken),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────

  Widget _buildProgressBar(TaikenProgress progress, Taiken taiken) {
    final total    = taiken.totalQuestions;
    final answered = progress.questionsAnswered;
    final value    = total == 0 ? 0.0 : answered / total;
    final passing  = progress.accuracyPercentage >= taiken.passThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            '$answered / $total answered',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
          Text(
            '${progress.accuracyPercentage.toStringAsFixed(0)}%',
            style: TextStyle(
              color: passing ? _kSuccess : Colors.orange,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 5,
            backgroundColor: Colors.grey.withOpacity(0.2),
            valueColor:
            AlwaysStoppedAnimation<Color>(passing ? _kSuccess : Colors.orange),
          ),
        ),
      ],
    );
  }

  // ── Lock overlay ──────────────────────────────────────────────────────────

  Widget _buildLockOverlay(Taiken taiken) {
    final req    = taiken.domainUnlockRequirement;
    final domain = req?['domain'] as String? ?? 'this domain';
    final min    = (req?['min_taikens_passed'] as num?)?.toInt() ?? 1;

    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kCardRadius),
        child: Container(
          color: Colors.black.withOpacity(0.74),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border:
                  Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                ),
                child:
                const Icon(Icons.lock_rounded, color: Colors.white70, size: 26),
              ),
              const SizedBox(height: 10),
              const Text(
                'Locked',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'Complete $min Taiken${min > 1 ? 's' : ''} in "$domain" to unlock',
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 12, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Locked dialog ─────────────────────────────────────────────────────────

  void _showLockedDialog(Taiken taiken) {
    final req    = taiken.domainUnlockRequirement;
    final domain = req?['domain'] as String? ?? 'this domain';
    final min    = (req?['min_taikens_passed'] as num?)?.toInt() ?? 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded,
                  size: 28, color: Colors.orange),
            ),
            const SizedBox(height: 16),
            Text(
              taiken.title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Complete $min Taiken${min > 1 ? 's' : ''} in the "$domain" domain first to unlock this experience.',
              style: TextStyle(
                color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.62),
                fontSize: 14,
                height: 1.55,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ref
                      .read(taikenListProvider.notifier)
                      .filterByDomain(domain);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBrand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
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

  // ── Skeleton loader ────────────────────────────────────────────────────────

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 4,
      itemBuilder: (_, i) => _SkeletonCard(delay: i * 80),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: _kBrand.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.school_outlined, size: 36, color: _kBrand),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Taikens yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to create an experience!',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TaikenCreatePage())),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Create a Taiken'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBrand,
              foregroundColor: Colors.white,
              padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// StreakBottomSheet — appears when the flame badge in AppBar is tapped
// =============================================================================

class _StreakBottomSheet extends StatelessWidget {
  const _StreakBottomSheet();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.55, 0.85],
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 28,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[500]?.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _kBrand.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      color: _kBrand,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Your Streak',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            // Scrollable content — just the StreakCard from existing widgets
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: const StreakCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// _HeaderHero  — shown in the expanded sliver space
// =============================================================================

class _HeaderHero extends ConsumerWidget {
  const _HeaderHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning 🌤'
        : hour < 17
        ? 'Good afternoon ⚡'
        : 'Good evening 🌙';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      alignment: Alignment.centerLeft,
      child: Text(
        greeting,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// =============================================================================
// _CreateFab
// =============================================================================

class _CreateFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const TaikenCreatePage())),
      icon: const Icon(Icons.add_rounded),
      label: const Text(
        'Create',
        style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
      backgroundColor: _kBrand,
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    );
  }
}

// =============================================================================
// _ThumbnailSection
// =============================================================================

class _ThumbnailSection extends StatelessWidget {
  final Taiken taiken;
  final bool isCompleted;

  const _ThumbnailSection({
    required this.taiken,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(_kCardRadius)),
          child: CachedNetworkImage(
            imageUrl:    taiken.thumbnailUrl!,
            width:       double.infinity,
            height:      168,
            fit:         BoxFit.cover,
            errorWidget: (_, __, ___) => Container(
              height: 168,
              color: Colors.grey[850],
              child: const Icon(Icons.image_not_supported_rounded,
                  size: 42, color: Colors.white24),
            ),
          ),
        ),

        // Bottom gradient scrim for legibility
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 60,
          child: ClipRRect(
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(_kCardRadius)),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),

        // Episode badge (top-left)
        if (taiken.isPartOfSeries && taiken.episodeNumber != null)
          Positioned(
            top: 10,
            left: 10,
            child: _Pill(
              label: 'EP ${taiken.episodeNumber}',
              icon: Icons.play_circle_outline_rounded,
              color: _kPurple,
            ),
          ),

        // Completed badge (top-right)
        if (isCompleted)
          Positioned(
            top: 10,
            right: 10,
            child: _Pill(
              label: 'Completed',
              icon: Icons.check_circle_rounded,
              color: _kSuccess,
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Small reusable components
// =============================================================================

class _Pill extends StatelessWidget {
  final String  label;
  final IconData icon;
  final Color   color;

  const _Pill({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.88),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.4), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color  color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String  label;
  final bool    selected;
  final Color?  accent;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final color = accent ?? _kBrand;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color:        selected ? color : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withOpacity(0.3),
            width: 1.2,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withOpacity(0.25), blurRadius: 8)]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.65),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatefulWidget {
  final int delay;
  const _SkeletonCard({required this.delay});

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double>   _shimmer;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _shimmer = CurvedAnimation(parent: _anim, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        final opacity = 0.06 + _shimmer.value * 0.08;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            height: 280,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(opacity),
              borderRadius: BorderRadius.circular(_kCardRadius),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Helpers
// =============================================================================

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

String _domainLabel(String domain) {
  const map = {
    'technology':             'Tech',
    'design_creativity':      'Design',
    'business_finance':       'Business',
    'science_research':       'Science',
    'engineering':            'Engineering',
    'languages_communication':'Languages',
    'education_learning':     'Education',
    'career_growth':          'Career',
    'health_psychology':      'Health',
    'arts_culture':           'Arts',
  };
  return map[domain] ?? _capitalize(domain.replaceAll('_', ' '));
}

Color _difficultyColor(String diff) {
  switch (diff) {
    case 'beginner':     return const Color(0xFF22C55E);
    case 'intermediate': return const Color(0xFFFFB800);
    case 'advanced':     return const Color(0xFFEF4444);
    default:             return _kBrand;
  }
}