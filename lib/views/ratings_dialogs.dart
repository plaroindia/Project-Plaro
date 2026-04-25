import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../Viewmodels/post_rating_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  HELPER: compact star-row widget (read-only)
// ─────────────────────────────────────────────────────────────────────────────

class _StarDisplay extends StatelessWidget {
  final double rating; // 0.0 – 5.0
  final double size;
  final Color filledColor;

  const _StarDisplay({
    required this.rating,
    this.size = 18,
    this.filledColor = const Color(0xFFFFB800),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.floor();
        final partial = !filled && i < rating;
        return Icon(
          filled
              ? Icons.star_rounded
              : partial
              ? Icons.star_half_rounded
              : Icons.star_outline_rounded,
          color: (filled || partial) ? filledColor : Colors.grey.shade400,
          size: size,
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HELPER: interactive star selector (editable)
// ─────────────────────────────────────────────────────────────────────────────

class _StarSelector extends StatefulWidget {
  final int initial;
  final ValueChanged<int> onChanged;

  const _StarSelector({required this.initial, required this.onChanged});

  @override
  State<_StarSelector> createState() => _StarSelectorState();
}

class _StarSelectorState extends State<_StarSelector> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final active = i < _selected;
        return GestureDetector(
          onTap: () {
            setState(() => _selected = i + 1);
            widget.onChanged(i + 1);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              color: active ? const Color(0xFFFFB800) : Colors.grey.shade400,
              size: 32,
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HELPER: score slider for editable dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  const _ScoreSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.8))),
            Text('${(value * 100).round()}%',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 1,
            divisions: 20,
            activeColor: theme.colorScheme.primary,
            inactiveColor: theme.colorScheme.primary.withOpacity(0.2),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HELPER: score row for read-only displays
// ─────────────────────────────────────────────────────────────────────────────

class _ScoreRow extends StatelessWidget {
  final String label;
  final double value; // 0–1
  final Color barColor;

  const _ScoreRow({
    required this.label,
    required this.value,
    this.barColor = const Color(0xFF6C63FF),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface.withOpacity(0.75))),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value.clamp(0.0, 1.0),
                backgroundColor: barColor.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
                minHeight: 8,
              ),
            ),
          ),
          SizedBox(width: 8),
          SizedBox(
            width: 38,
            child: Text(
              '${(value * 100).round()}%',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6)),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  1. RATING INSIGHTS DIALOG  (read-only, same for all users)
// ─────────────────────────────────────────────────────────────────────────────

class RatingInsightsDialog extends ConsumerWidget {
  final String postId;

  const RatingInsightsDialog({super.key, required this.postId});

  static void show(BuildContext context, {required String postId}) {
    showDialog(
      context: context,
      builder: (_) => RatingInsightsDialog(postId: postId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(postRatingProvider(postId));

    return Dialog(
      backgroundColor: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: EdgeInsets.all(24),
        child: state.isLoading
            ? SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()))
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(
              children: [
                Icon(Icons.verified,
                    color: theme.colorScheme.primary, size: 20),
                SizedBox(width: 8),
                Text('Rating Insights',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface)),
              ],
            ),
            SizedBox(height: 20),

            // Big star + numeric average
            if (state.totalRatings == 0)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No professional ratings yet',
                      style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5),
                          fontSize: 14)),
                ),
              )
            else ...[
              Center(
                child: Column(
                  children: [
                    Text(
                      state.averageRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 52,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                        height: 1.0,
                      ),
                    ),
                    SizedBox(height: 6),
                    _StarDisplay(
                        rating: state.averageRating, size: 28),
                    SizedBox(height: 4),
                    Text(
                      '${state.totalRatings} professional rating${state.totalRatings != 1 ? 's' : ''}',
                      style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.55)),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 20),
              const Divider(),
              SizedBox(height: 12),

              // Score breakdown
              _ScoreRow(
                  label: 'Accuracy',
                  value: state.avgAccuracy,
                  barColor: const Color(0xFF4CAF50)),
              _ScoreRow(
                  label: 'Authenticity',
                  value: state.avgAuthenticity,
                  barColor: const Color(0xFF2196F3)),
              _ScoreRow(
                  label: 'Usefulness',
                  value: state.avgUsefulness,
                  barColor: const Color(0xFFFF9800)),
              SizedBox(height: 16),

              // Distribution bars
              Text('Distribution',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface
                          .withOpacity(0.65))),
              SizedBox(height: 8),
              ...List.generate(5, (i) {
                final star = 5 - i;
                final count = state.distribution[star] ?? 0;
                final frac = state.totalRatings > 0
                    ? count / state.totalRatings
                    : 0.0;
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Text('$star',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.6))),
                      SizedBox(width: 4),
                      Icon(Icons.star_rounded,
                          color: Color(0xFFFFB800), size: 14),
                      SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: frac,
                            backgroundColor:
                            Colors.grey.withOpacity(0.15),
                            valueColor:
                            const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFFB800)),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      SizedBox(width: 6),
                      SizedBox(
                        width: 20,
                        child: Text('$count',
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurface
                                    .withOpacity(0.5)),
                            textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                );
              }),
            ],

            SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close',
                    style:
                    TextStyle(color: theme.colorScheme.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  2. RANKED-BY DIALOG  (professional list + conditional "Rate This Post")
// ─────────────────────────────────────────────────────────────────────────────

class RankedByDialog extends ConsumerWidget {
  final String postId;

  const RankedByDialog({super.key, required this.postId});

  static void show(BuildContext context, {required String postId}) {
    showDialog(
      context: context,
      builder: (_) => RankedByDialog(postId: postId),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(postRatingProvider(postId));
    final isVerifiedAsync = ref.watch(isVerifiedProfessionalProvider);

    return Dialog(
      backgroundColor: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Padding(
          padding: EdgeInsets.all(0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ──────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  children: [
                    Icon(Icons.people_alt_outlined,
                        color: theme.colorScheme.primary, size: 20),
                    SizedBox(width: 8),
                    Text('Rated by Professionals',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                          size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 24),

              // ── List ─────────────────────────────────────────
              if (state.isLoading)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.reviews.isEmpty)
                Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('No professional ratings yet',
                        style: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withOpacity(0.5))),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: state.reviews.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = state.reviews[i];
                      return _ReviewTile(review: r);
                    },
                  ),
                ),

              // ── Conditional Footer ───────────────────────────
              // Use .when() so we NEVER default to false while the
              // FutureProvider is still loading — that was the bug.
              isVerifiedAsync.when(
                loading: () => Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                error: (_, __) => SizedBox(height: 16),
                data: (isVerified) => isVerified
                    ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Divider(height: 1),
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.star_outline_rounded,
                              size: 18),
                          label: Text('Rate This Post'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            EditableRatingDialog.show(context,
                                postId: postId);
                          },
                        ),
                      ),
                    ),
                  ],
                )
                    : SizedBox(height: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  final EducatorReview review;

  const _ReviewTile({required this.review});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 20,
            backgroundImage: review.profilePic != null
                ? CachedNetworkImageProvider(review.profilePic!)
                : const AssetImage('assets/plaro_logo.png') as ImageProvider,
          ),
          SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(review.username,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface),
                          overflow: TextOverflow.ellipsis),
                    ),
                    _StarDisplay(rating: review.rating.toDouble(), size: 13),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    _MiniScore(
                        label: 'Accuracy',
                        value: review.accuracyScore),
                    SizedBox(width: 10),
                    _MiniScore(
                        label: 'Auth.',
                        value: review.authenticityScore),
                    SizedBox(width: 10),
                    _MiniScore(
                        label: 'Useful',
                        value: review.usefulnessScore),
                  ],
                ),
                if (review.feedback != null &&
                    review.feedback!.isNotEmpty) ...[
                  SizedBox(height: 4),
                  Text(review.feedback!,
                      style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.6),
                          fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
                SizedBox(height: 2),
                Text(
                  _timeAgo(review.createdAt),
                  style: TextStyle(
                      fontSize: 11,
                      color:
                      theme.colorScheme.onSurface.withOpacity(0.4)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }
}

class _MiniScore extends StatelessWidget {
  final String label;
  final double value;

  const _MiniScore({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: TextStyle(
                fontSize: 11,
                color:
                Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        Text('${(value * 100).round()}%',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  3. EDITABLE RATING DIALOG  (submission only, accessed via Ranked-By flow)
// ─────────────────────────────────────────────────────────────────────────────

class EditableRatingDialog extends ConsumerStatefulWidget {
  final String postId;

  const EditableRatingDialog({super.key, required this.postId});

  static void show(BuildContext context, {required String postId}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => EditableRatingDialog(postId: postId),
    );
  }

  @override
  ConsumerState<EditableRatingDialog> createState() =>
      _EditableRatingDialogState();
}

class _EditableRatingDialogState extends ConsumerState<EditableRatingDialog> {
  // Form values
  int _rating = 3;
  double _accuracy = 0.5;
  double _authenticity = 0.5;
  double _usefulness = 0.5;
  final _feedbackCtrl = TextEditingController();

  // Prefill tracking
  String? _existingReviewId;
  bool _loadingExisting = true;

  @override
  void initState() {
    super.initState();
    _fetchExisting();
  }

  Future<void> _fetchExisting() async {
    final existing = await ref
        .read(postRatingProvider(widget.postId).notifier)
        .getMyReview();

    if (!mounted) return;
    if (existing != null) {
      setState(() {
        _existingReviewId = existing.id;
        _rating = existing.rating;
        _accuracy = existing.accuracyScore;
        _authenticity = existing.authenticityScore;
        _usefulness = existing.usefulnessScore;
        if (existing.feedback != null) {
          _feedbackCtrl.text = existing.feedback!;
        }
      });
    }
    setState(() => _loadingExisting = false);
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final success = await ref
        .read(postRatingProvider(widget.postId).notifier)
        .submitRating(
      rating: _rating,
      accuracyScore: _accuracy,
      authenticityScore: _authenticity,
      usefulnessScore: _usefulness,
      feedback: _feedbackCtrl.text.trim().isEmpty
          ? null
          : _feedbackCtrl.text.trim(),
      existingReviewId: _existingReviewId,
    );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_existingReviewId != null
              ? 'Rating updated!'
              : 'Rating submitted!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      final err = ref.read(postRatingProvider(widget.postId)).error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${err ?? 'Unknown error'}'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(postRatingProvider(widget.postId));

    return Dialog(
      backgroundColor: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: _loadingExisting
            ? SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()))
            : Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.rate_review_outlined,
                    color: theme.colorScheme.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  _existingReviewId != null
                      ? 'Update Your Rating'
                      : 'Rate This Post',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'Your rating is visible to all users',
              style: TextStyle(
                  fontSize: 12,
                  color:
                  theme.colorScheme.onSurface.withOpacity(0.45)),
            ),
            SizedBox(height: 20),

            // Overall star rating
            Center(
              child: Column(
                children: [
                  Text('Overall Rating',
                      style: TextStyle(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.7))),
                  SizedBox(height: 8),
                  _StarSelector(
                    initial: _rating,
                    onChanged: (v) => setState(() => _rating = v),
                  ),
                  SizedBox(height: 4),
                  Text('$_rating / 5',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFFB800))),
                ],
              ),
            ),
            SizedBox(height: 20),
            const Divider(),
            SizedBox(height: 12),

            // Score sliders
            Text('Breakdown',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface)),
            SizedBox(height: 8),

            _ScoreSlider(
              label: 'Accuracy',
              value: _accuracy,
              onChanged: (v) => setState(() => _accuracy = v),
            ),
            _ScoreSlider(
              label: 'Authenticity',
              value: _authenticity,
              onChanged: (v) => setState(() => _authenticity = v),
            ),
            _ScoreSlider(
              label: 'Usefulness',
              value: _usefulness,
              onChanged: (v) => setState(() => _usefulness = v),
            ),

            SizedBox(height: 16),

            // Optional feedback
            Text('Feedback (optional)',
                style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurface
                        .withOpacity(0.7))),
            SizedBox(height: 6),
            TextField(
              controller: _feedbackCtrl,
              maxLines: 3,
              maxLength: 280,
              style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Share your thoughts…',
                hintStyle: TextStyle(
                    color: theme.colorScheme.onSurface
                        .withOpacity(0.35)),
                filled: true,
                fillColor:
                theme.colorScheme.primary.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.all(12),
                counterStyle: TextStyle(
                    color: theme.colorScheme.onSurface
                        .withOpacity(0.4),
                    fontSize: 11),
              ),
            ),
            SizedBox(height: 20),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: state.isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: Text('Cancel',
                      style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.6))),
                ),
                SizedBox(width: 8),
                ElevatedButton(
                  onPressed:
                  state.isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  child: state.isSubmitting
                      ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : Text(
                      _existingReviewId != null
                          ? 'Update'
                          : 'Submit',
                      style: TextStyle(
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Post card header widgets: StarRatingIcon + RankedByIcon
// ─────────────────────────────────────────────────────────────────────────────

/// ⭐ Star icon shown in post header — opens RatingInsightsDialog (read-only)
class PostStarRatingIcon extends ConsumerWidget {
  final String postId;

  const PostStarRatingIcon({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postRatingProvider(postId));
    final theme = Theme.of(context);

    final hasRatings = state.totalRatings > 0;
    final avg = state.averageRating;

    return GestureDetector(
      onTap: () => RatingInsightsDialog.show(context, postId: postId),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasRatings ? Icons.star_rounded : Icons.star_outline_rounded,
              color: hasRatings
                  ? const Color(0xFFFFB800)
                  : theme.colorScheme.onSurface.withOpacity(0.4),
              size: 20,
            ),
            if (hasRatings) ...[
              SizedBox(width: 2),
              Text(
                avg.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFFB800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 👥 Ranked-by icon — opens RankedByDialog (conditional footer)
class PostRankedByIcon extends ConsumerWidget {
  final String postId;

  const PostRankedByIcon({super.key, required this.postId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(postRatingProvider(postId));
    final theme = Theme.of(context);
    final count = state.totalRatings;

    return GestureDetector(
      onTap: () => RankedByDialog.show(context, postId: postId),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Two overlapping circles icon
            SizedBox(
              width: 30,
              height: 20,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    child: CircleAvatar(
                      radius: 9,
                      backgroundColor:
                      theme.colorScheme.primary.withOpacity(0.2),
                      child: Icon(Icons.person,
                          size: 12,
                          color: theme.colorScheme.primary.withOpacity(0.8)),
                    ),
                  ),
                  Positioned(
                    left: 11,
                    child: CircleAvatar(
                      radius: 9,
                      backgroundColor:
                      theme.colorScheme.secondary.withOpacity(0.2),
                      child: Icon(Icons.person,
                          size: 12,
                          color:
                          theme.colorScheme.secondary.withOpacity(0.8)),
                    ),
                  ),
                ],
              ),
            ),
            if (count > 0) ...[
              SizedBox(width: 2),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}