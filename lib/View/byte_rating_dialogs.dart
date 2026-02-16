import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../ViewModel/byte_rating_provider.dart';
import '../ViewModel/post_rating_provider.dart';

// ── Shared helpers (copied from post_rating_dialogs — same visuals) ──────────

class _StarDisplay extends StatelessWidget {
  final double rating;
  final double size;
  final Color filledColor;
  const _StarDisplay({required this.rating, this.size = 18,
    this.filledColor = const Color(0xFFFFB800)});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.floor();
        final partial = !filled && i < rating;
        return Icon(
          filled ? Icons.star_rounded
              : partial ? Icons.star_half_rounded : Icons.star_outline_rounded,
          color: (filled || partial) ? filledColor : Colors.grey.shade400,
          size: size,
        );
      }),
    );
  }
}

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
  void initState() { super.initState(); _selected = widget.initial; }
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final active = i < _selected;
        return GestureDetector(
          onTap: () { setState(() => _selected = i + 1); widget.onChanged(i + 1); },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
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

class _ScoreSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _ScoreSlider({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.8))),
        Text('${(value * 100).round()}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
      ]),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 4,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: Slider(
          value: value, min: 0, max: 1, divisions: 20,
          activeColor: theme.colorScheme.primary,
          inactiveColor: theme.colorScheme.primary.withOpacity(0.2),
          onChanged: onChanged,
        ),
      ),
    ]);
  }
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final double value;
  final Color barColor;
  const _ScoreRow({required this.label, required this.value, this.barColor = const Color(0xFF6C63FF)});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.75)))),
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            backgroundColor: barColor.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 8,
          ),
        )),
        const SizedBox(width: 8),
        SizedBox(width: 38, child: Text('${(value * 100).round()}%',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.6)),
            textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _MiniScore extends StatelessWidget {
  final String label;
  final double value;
  const _MiniScore({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Text('$label ${(value * 100).round()}%',
        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.55)));
  }
}

String _timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  return '${diff.inMinutes}m ago';
}

// ── 1. Insights dialog (read-only) ──────────────────────────────────────────

class ByteRatingInsightsDialog extends ConsumerWidget {
  final String byteId;
  const ByteRatingInsightsDialog({super.key, required this.byteId});

  static void show(BuildContext context, {required String byteId}) {
    showDialog(context: context,
        builder: (_) => ByteRatingInsightsDialog(byteId: byteId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(byteRatingProvider(byteId));
    return Dialog(
      backgroundColor: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: state.isLoading
            ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.verified, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Byte Insights', style: TextStyle(fontSize: 18,
                      fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                ]),
                const SizedBox(height: 20),
                if (state.totalRatings == 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('No professional ratings yet',
                        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 14))),
                  )
                else ...[
                  Center(child: Column(children: [
                    Text(state.averageRating.toStringAsFixed(1),
                        style: TextStyle(fontSize: 52, fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface, height: 1.0)),
                    const SizedBox(height: 6),
                    _StarDisplay(rating: state.averageRating, size: 28),
                    const SizedBox(height: 4),
                    Text('${state.totalRatings} professional rating${state.totalRatings != 1 ? "s" : ""}',
                        style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.55))),
                  ])),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  _ScoreRow(label: 'Accuracy', value: state.avgAccuracy, barColor: const Color(0xFF4CAF50)),
                  _ScoreRow(label: 'Authenticity', value: state.avgAuthenticity, barColor: const Color(0xFF2196F3)),
                  _ScoreRow(label: 'Usefulness', value: state.avgUsefulness, barColor: const Color(0xFFFF9800)),
                  const SizedBox(height: 16),
                  Text('Distribution', style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.65))),
                  const SizedBox(height: 8),
                  ...List.generate(5, (i) {
                    final star = 5 - i;
                    final count = state.distribution[star] ?? 0;
                    final frac = state.totalRatings > 0 ? count / state.totalRatings : 0.0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Text('$star', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.6))),
                        const SizedBox(width: 4),
                        const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 14),
                        const SizedBox(width: 6),
                        Expanded(child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: frac,
                              backgroundColor: Colors.grey.withOpacity(0.15),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFB800)),
                              minHeight: 6),
                        )),
                        const SizedBox(width: 6),
                        SizedBox(width: 20, child: Text('$count',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                            textAlign: TextAlign.right)),
                      ]),
                    );
                  }),
                ],
                const SizedBox(height: 20),
                Align(alignment: Alignment.centerRight,
                    child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Close', style: TextStyle(color: theme.colorScheme.primary)))),
              ]),
        ),
      ),
    );
  }
}

// ── 2. Ranked-by dialog ──────────────────────────────────────────────────────

class ByteRankedByDialog extends ConsumerWidget {
  final String byteId;
  const ByteRankedByDialog({super.key, required this.byteId});

  static void show(BuildContext context, {required String byteId}) {
    showDialog(context: context,
        builder: (_) => ByteRankedByDialog(byteId: byteId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(byteRatingProvider(byteId));
    final isVerifiedAsync = ref.watch(isVerifiedProfessionalProvider);

    return Dialog(
      backgroundColor: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
        // Column with mainAxisSize.min + Flexible inside a ConstrainedBox can
        // swallow the footer when reviews are present. Fix: use a Column that
        // fills the constrained box via CrossAxisAlignment and lets the list
        // take available space with Expanded, while the header and footer are
        // always intrinsically sized.
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header — always shown, intrinsic height
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(children: [
                  Icon(Icons.people_alt_outlined, color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text('Rated by Professionals', style: TextStyle(fontSize: 17,
                      fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurface.withOpacity(0.5), size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
                ]),
              ),
              const Divider(height: 24),

              // Review list — loading / empty / populated
              if (state.isLoading)
                const Padding(padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()))
              else if (state.reviews.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(child: Text('No professional ratings yet',
                      style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)))),
                )
              else
              // Use Flexible (not Expanded) so the column can still be min-sized
              // when there are few reviews, but scroll when there are many.
                Flexible(child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: state.reviews.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ReviewTile(review: state.reviews[i]),
                )),

              // Footer — always rendered OUTSIDE the Flexible so it is never clipped
              isVerifiedAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
                ),
                error: (_, __) => const SizedBox(height: 16),
                data: (isVerified) => isVerified
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.star_outline_rounded, size: 18),
                        label: const Text('Rate This Byte'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          ByteEditableRatingDialog.show(context, byteId: byteId);
                        },
                      ),
                    ),
                  ),
                ])
                    : const SizedBox(height: 16),
              ),
            ]),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: review.profilePic != null
              ? CachedNetworkImageProvider(review.profilePic!)
              : const AssetImage('assets/plaro_logo.png') as ImageProvider,
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(review.username,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface),
                overflow: TextOverflow.ellipsis)),
            _StarDisplay(rating: review.rating.toDouble(), size: 13),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _MiniScore(label: 'Accuracy', value: review.accuracyScore),
            const SizedBox(width: 10),
            _MiniScore(label: 'Auth.', value: review.authenticityScore),
            const SizedBox(width: 10),
            _MiniScore(label: 'Useful', value: review.usefulnessScore),
          ]),
          if (review.feedback != null && review.feedback!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(review.feedback!,
                style: TextStyle(fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontStyle: FontStyle.italic),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 2),
          Text(_timeAgo(review.createdAt),
              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withOpacity(0.4))),
        ])),
      ]),
    );
  }
}

// ── 3. Editable rating dialog ────────────────────────────────────────────────

class ByteEditableRatingDialog extends ConsumerStatefulWidget {
  final String byteId;
  const ByteEditableRatingDialog({super.key, required this.byteId});

  static void show(BuildContext context, {required String byteId}) {
    showDialog(context: context, builder: (_) => ByteEditableRatingDialog(byteId: byteId));
  }

  @override
  ConsumerState<ByteEditableRatingDialog> createState() => _ByteEditableRatingDialogState();
}

class _ByteEditableRatingDialogState extends ConsumerState<ByteEditableRatingDialog> {
  int _rating = 3;
  double _accuracy = 0.5;
  double _authenticity = 0.5;
  double _usefulness = 0.5;
  final _feedbackCtrl = TextEditingController();
  String? _existingReviewId;
  bool _loadingExisting = true;

  @override
  void initState() {
    super.initState();
    _fetchExisting();
  }

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchExisting() async {
    final existing = await ref.read(byteRatingProvider(widget.byteId).notifier).getMyReview();
    if (mounted && existing != null) {
      setState(() {
        _existingReviewId = existing.id;
        _rating = existing.rating;
        _accuracy = existing.accuracyScore;
        _authenticity = existing.authenticityScore;
        _usefulness = existing.usefulnessScore;
        _feedbackCtrl.text = existing.feedback ?? '';
      });
    }
    if (mounted) setState(() => _loadingExisting = false);
  }

  Future<void> _submit() async {
    final ok = await ref.read(byteRatingProvider(widget.byteId).notifier).submitRating(
      rating: _rating,
      accuracyScore: _accuracy,
      authenticityScore: _authenticity,
      usefulnessScore: _usefulness,
      feedback: _feedbackCtrl.text.trim().isEmpty ? null : _feedbackCtrl.text.trim(),
      existingReviewId: _existingReviewId,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Rating submitted!' : 'Failed to submit rating'),
        backgroundColor: ok ? Colors.green : Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(byteRatingProvider(widget.byteId));

    if (_loadingExisting) {
      return const Dialog(child: Padding(padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator())));
    }

    return Dialog(
      backgroundColor: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_existingReviewId != null ? 'Update Your Rating' : 'Rate This Byte',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface)),
              const SizedBox(height: 20),
              Center(child: _StarSelector(initial: _rating,
                  onChanged: (v) => setState(() => _rating = v))),
              const SizedBox(height: 8),
              Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.star_rounded, color: const Color(0xFFFFB800), size: 16),
                const SizedBox(width: 4),
                Text('$_rating / 5', style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600, color: Color(0xFFFFB800))),
              ])),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              Text('Breakdown', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface)),
              const SizedBox(height: 8),
              _ScoreSlider(label: 'Accuracy', value: _accuracy,
                  onChanged: (v) => setState(() => _accuracy = v)),
              _ScoreSlider(label: 'Authenticity', value: _authenticity,
                  onChanged: (v) => setState(() => _authenticity = v)),
              _ScoreSlider(label: 'Usefulness', value: _usefulness,
                  onChanged: (v) => setState(() => _usefulness = v)),
              const SizedBox(height: 16),
              Text('Feedback (optional)', style: TextStyle(fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.7))),
              const SizedBox(height: 6),
              TextField(
                controller: _feedbackCtrl,
                maxLines: 3, maxLength: 280,
                style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Share your thoughts…',
                  hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.35)),
                  filled: true,
                  fillColor: theme.colorScheme.primary.withOpacity(0.06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.all(12),
                  counterStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 11),
                ),
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(
                  onPressed: state.isSubmitting ? null : () => Navigator.of(context).pop(),
                  child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6))),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: state.isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: state.isSubmitting
                      ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_existingReviewId != null ? 'Update' : 'Submit',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ]),
            ]),
      ),
    );
  }
}

// ── Side action widgets (used in ByteVideoPlayer) ────────────────────────────

/// Star icon → insights dialog (read-only)
class ByteStarRatingIcon extends ConsumerWidget {
  final String byteId;
  const ByteStarRatingIcon({super.key, required this.byteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(byteRatingProvider(byteId));
    final hasRatings = state.totalRatings > 0;

    return GestureDetector(
      onTap: () => ByteRatingInsightsDialog.show(context, byteId: byteId),
      child: _SideActionItem(
        icon: hasRatings ? Icons.star_rounded : Icons.star_outline_rounded,
        iconColor: hasRatings ? const Color(0xFFFFB800) : Colors.white70,
        label: hasRatings ? state.averageRating.toStringAsFixed(1) : '',
      ),
    );
  }
}

/// People icon → ranked-by dialog (+ conditional Rate button for professionals)
class ByteRankedByIcon extends ConsumerWidget {
  final String byteId;
  const ByteRankedByIcon({super.key, required this.byteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(byteRatingProvider(byteId));
    final count = state.totalRatings;

    return GestureDetector(
      onTap: () => ByteRankedByDialog.show(context, byteId: byteId),
      child: _SideActionItem(
        icon: Icons.people_alt_outlined,
        iconColor: Colors.white70,
        label: count > 0 ? '$count' : '',
      ),
    );
  }
}

/// Reusable vertical action item for the right-side column
class _SideActionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _SideActionItem({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          )),
        ],
      ],
    );
  }
}