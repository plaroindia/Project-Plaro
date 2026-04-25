// ================================================================
// freelance_feed_page.dart
//
// Standalone "Pearl Offers" browsing page.
// - Accessible from notifications Pearl Offers tab banner
// - Shows all open freelance posts filtered by user's rank
// - Rank badge, Pro gate, apply sheet, withdraw
// - Does NOT appear in main feed (post_feed_provider is untouched)
// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../Viewmodels/freelance_provider.dart';
import '../Viewmodels/pro_provider.dart';

class FreelanceFeedPage extends ConsumerStatefulWidget {
  const FreelanceFeedPage({super.key});

  @override
  ConsumerState<FreelanceFeedPage> createState() =>
      _FreelanceFeedPageState();
}

class _FreelanceFeedPageState extends ConsumerState<FreelanceFeedPage> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
            () => ref.read(freelanceFeedProvider.notifier).loadFeed());
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(freelanceFeedProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(freelanceFeedProvider);
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          const Text('Pearl Offers',
              style:
              TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          const SizedBox(width: 8),
          if (isPro)
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('PRO',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.read(freelanceFeedProvider.notifier).refresh(),
          ),
        ],
      ),
      body: _buildBody(state),
    );
  }

  Widget _buildBody(FreelanceFeedState state) {
    if (state.isLoading && state.posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 12),
            Text('Failed to load offers',
                style: TextStyle(color: Colors.grey[400])),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () =>
                  ref.read(freelanceFeedProvider.notifier).refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.work_off_outlined,
                size: 64, color: Colors.grey[600]),
            const SizedBox(height: 16),
            Text('No open offers right now',
                style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Text('Check back soon for new freelance tasks',
                style:
                TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(freelanceFeedProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.posts.length +
            (state.isLoadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == state.posts.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return FreelancePostCard(post: state.posts[i]);
        },
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// FreelancePostCard
// ════════════════════════════════════════════════════════════════════════════

class FreelancePostCard extends ConsumerWidget {
  final FreelancePost post;
  const FreelancePostCard({super.key, required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: post.isEligible
              ? Colors.transparent
              : Colors.grey.withOpacity(0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: badges + budget
            Row(children: [
              _RankBadge(rank: post.freelanceMinRank),
              if (post.requiresPro) ...[
                const SizedBox(width: 6),
                _ProBadge(),
              ],
              const Spacer(),
              if (post.freelanceBudget != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '💰 ${post.freelanceBudget}',
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 13),
                  ),
                ),
            ]),
            const SizedBox(height: 10),

            // Title
            Text(post.title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),

            // Content preview
            if (post.content != null && post.content!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(post.content!,
                  style:
                  TextStyle(fontSize: 13, color: Colors.grey[400]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],

            const SizedBox(height: 10),

            // Meta row
            Row(children: [
              if (post.domain != null) ...[
                Icon(Icons.label_outline,
                    size: 13, color: Colors.grey[600]),
                const SizedBox(width: 3),
                Text(post.domain!,
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600])),
                const SizedBox(width: 12),
              ],
              if (post.freelanceDeadline != null) ...[
                Icon(Icons.access_time,
                    size: 13, color: Colors.grey[600]),
                const SizedBox(width: 3),
                Text(_fmt(post.freelanceDeadline!),
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600])),
              ],
              const Spacer(),
              Text('by ${post.authorUsername}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600])),
            ]),

            const SizedBox(height: 14),

            // CTA button
            _buildCta(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildCta(BuildContext context, WidgetRef ref) {
    if (post.alreadyApplied) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline,
                color: Colors.green, size: 16),
            const SizedBox(width: 6),
            const Text('Applied',
                style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            const Spacer(),
            TextButton(
              onPressed: () async {
                final err = await ref
                    .read(freelanceFeedProvider.notifier)
                    .withdraw(postId: post.postId);
                if (err != null && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(err)));
                }
              },
              style: TextButton.styleFrom(
                  foregroundColor: Colors.grey[500],
                  padding: EdgeInsets.zero),
              child: const Text('Withdraw',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (!post.isEligible) {
      final reason = post.requiresPro
          ? 'Requires Pro'
          : 'Requires ${post.freelanceMinRank} rank';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border:
          Border.all(color: Colors.grey.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline,
                size: 15, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(reason,
                style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _showApplySheet(context, ref),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00BFA5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('Apply Now',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _showApplySheet(BuildContext context, WidgetRef ref) {
    final msgCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[700],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('Apply: ${post.title}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.white)),
              const SizedBox(height: 14),
              TextField(
                controller: msgCtrl,
                maxLines: 4,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Briefly describe why you are a good fit…',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  filled: true,
                  fillColor: Colors.grey[900],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final error = await ref
                        .read(freelanceFeedProvider.notifier)
                        .apply(
                      postId: post.postId,
                      message: msgCtrl.text,
                    );
                    if (error != null && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error)));
                    } else if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text(
                                '✅ Application submitted!'),
                            backgroundColor: Colors.green),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BFA5),
                    foregroundColor: Colors.white,
                    padding:
                    const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Submit Application',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

// ── Shared badge widgets (also exported for notifications_page) ───────────────

class _RankBadge extends StatelessWidget {
  final String rank;
  const _RankBadge({required this.rank});

  Color get _color {
    switch (rank.toLowerCase()) {
      case 'intermediate': return Colors.blue;
      case 'advanced':     return Colors.purple;
      case 'expert':       return Colors.orange;
      case 'master':       return Colors.red;
      default:             return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _color),
    ),
    child: Text(rank.toUpperCase(),
        style: TextStyle(
            color: _color,
            fontSize: 11,
            fontWeight: FontWeight.w700)),
  );
}

class _ProBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.amber.withOpacity(0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.amber),
    ),
    child: const Text('⭐ PRO',
        style: TextStyle(
            color: Colors.amber,
            fontSize: 11,
            fontWeight: FontWeight.w700)),
  );
}