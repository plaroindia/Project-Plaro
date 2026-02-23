import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ViewModel/taiken_list_provider.dart';
import '../ViewModel/streak_provider.dart'; // ✅ NEW
import '../Model/taiken.dart';
import 'taiken_experience_page.dart';
import 'taiken_create_page.dart';
import 'widgets/streak_widgets.dart'; // ✅ NEW — StreakCard, MilestoneToastListener

class TaikensListPage extends ConsumerStatefulWidget {
  const TaikensListPage({super.key});

  @override
  ConsumerState<TaikensListPage> createState() => _TaikensListPageState();
}

class _TaikensListPageState extends ConsumerState<TaikensListPage> {
  final ScrollController _scrollController = ScrollController();
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taikenListProvider);

    // ✅ MilestoneToastListener wraps the whole page so the 🏆 SnackBar can
    // appear even if the user navigates back to the list right after completing.
    return MilestoneToastListener(
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
          title: const Text('Taikens'),
          actions: [
            // ✅ Streak badge in AppBar
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: const StreakBadge(size: 18)),
            ),
          ],
        ),
        // ✅ FAB to create a new Taiken
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const TaikenCreatePage()),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Create'),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // ✅ Streak card at the top — motivates daily play
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

  Widget _buildSearchAndFilter() {
    final state = ref.watch(taikenListProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            style:
            TextStyle(color: Theme.of(context).colorScheme.onSurface),
            decoration: InputDecoration(
              hintText: 'Search Taikens...',
              hintStyle: TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.5),
              ),
              prefixIcon: Icon(
                Icons.search,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withOpacity(0.7),
              ),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (query) {
              ref.read(taikenListProvider.notifier).searchTaikens(query);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildFilterChip(
                  'Domain',
                  state.filterDomain,
                  ['Science', 'Business', 'History', 'Technology', 'Arts'],
                      (value) =>
                      ref.read(taikenListProvider.notifier).filterByDomain(value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildFilterChip(
                  'Difficulty',
                  state.filterDifficulty,
                  ['beginner', 'intermediate', 'advanced'],
                      (value) => ref
                      .read(taikenListProvider.notifier)
                      .filterByDifficulty(value),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
      String label,
      String? currentValue,
      List<String> options,
      Function(String?) onSelect,
      ) {
    return PopupMenuButton<String>(
      child: Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: currentValue != null
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              currentValue ?? label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            Icon(Icons.arrow_drop_down,
                color: Theme.of(context).colorScheme.onSurface),
          ],
        ),
      ),
      onSelected: onSelect,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('All')),
        ...options.map(
              (option) => PopupMenuItem(value: option, child: Text(option)),
        ),
      ],
    );
  }

  Widget _buildTaikenList(TaikenListState state) {
    return RefreshIndicator(
      onRefresh: () async {
        await ref
            .read(taikenListProvider.notifier)
            .loadTaikens(refresh: true);
      },
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: state.taikens.length + (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.taikens.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          }
          final taiken = state.taikens[index];
          return _buildTaikenCard(taiken);
        },
      ),
    );
  }

  Widget _buildTaikenCard(Taiken taiken) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).cardColor,
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  TaikenExperiencePage(taikenId: taiken.taikenId),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (taiken.thumbnailUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
                child: Image.network(
                  taiken.thumbnailUrl!,
                  width: double.infinity,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 180,
                    color: Colors.grey[800],
                    child: const Icon(Icons.image_not_supported, size: 64),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    taiken.title,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    taiken.description,
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.7),
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildInfoChip(taiken.domain, Icons.category),
                      const SizedBox(width: 8),
                      _buildInfoChip(
                          taiken.difficulty, Icons.signal_cellular_alt),
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.star,
                              color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            taiken.averageRating.toStringAsFixed(1),
                            style: TextStyle(
                              color:
                              Theme.of(context).colorScheme.onSurface,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // ✅ Fixed encoding: replaced â€¢ with the actual bullet •
                  Text(
                    '${taiken.totalStages} Stages \u2022 ${taiken.totalQuestions} Questions',
                    style: TextStyle(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 280,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.school_outlined,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Taikens found',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.7),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Be the first to create one!',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          // ✅ CTA button in empty state as well
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const TaikenCreatePage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Create a Taiken'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}