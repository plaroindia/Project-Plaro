import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../Viewmodels/streakandpoints_provider.dart';

// =============================================================================
// StreakBadge
//
// A compact flame + number widget. Drop into AppBar, profile header, etc.
//
// Usage:
//   const StreakBadge()
//   StreakBadge(size: 20, showLabel: true)
// =============================================================================

class StreakBadge extends ConsumerWidget {
  final double size;
  final bool showLabel;

  const StreakBadge({super.key, this.size = 18, this.showLabel = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak    = ref.watch(currentStreakProvider);
    final isActive  = ref.watch(isStreakActiveTodayProvider);
    final theme     = Theme.of(context);

    final color = isActive ? const Color(0xFFFF6B35) : Colors.grey.shade400;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.local_fire_department_rounded, color: color, size: size),
        SizedBox(width: 2),
        Text(
          '$streak',
          style: theme.textTheme.labelLarge?.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.85,
          ),
        ),
        if (showLabel) ...[
          SizedBox(width: 3),
          Text(
            streak == 1 ? 'day' : 'days',
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ],
    );
  }
}

// =============================================================================
// StreakCard
//
// A richer card for the profile screen: current streak, longest streak,
// progress bar to next milestone, and "active today" indicator.
//
// Usage:
//   const StreakCard()
// =============================================================================

class StreakCard extends ConsumerWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakState = ref.watch(streakProvider);
    final current     = ref.watch(currentStreakProvider);
    final longest     = ref.watch(longestStreakProvider);
    final isActive    = ref.watch(isStreakActiveTodayProvider);
    final next        = ref.watch(nextMilestoneProvider);
    final progress    = ref.watch(milestoneProgressProvider);
    final milestones  = ref.watch(milestoneHistoryProvider);
    final theme       = Theme.of(context);

    if (streakState.isLoading && streakState.streak == null) {
      return const _StreakCardSkeleton();
    }

    final activeColor = const Color(0xFFFF6B35);
    final inactiveColor = Colors.grey.shade400;
    final flameColor = isActive ? activeColor : inactiveColor;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? activeColor.withOpacity(0.4)
              : theme.colorScheme.outline.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: isActive
                ? activeColor.withOpacity(0.08)
                : Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded, color: flameColor, size: 28),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$current ${current == 1 ? 'day' : 'days'}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: flameColor,
                    ),
                  ),
                  Text(
                    isActive ? 'Active today ✓' : 'Post or complete a taiken to continue',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isActive ? Colors.green.shade600 : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Longest streak pill
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events_rounded,
                        size: 14, color: Colors.amber.shade600),
                    SizedBox(width: 4),
                    Text(
                      '$longest best',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 14),

          // ── Progress to next milestone ─────────────────────────────────────
          if (next != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Next: ${next.key}-day streak',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 14, color: Color(0xFFFFB800)),
                    SizedBox(width: 2),
                    Text(
                      '+${next.value} pts',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: const Color(0xFFFFB800),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isActive ? activeColor : Colors.grey.shade400,
                ),
              ),
            ),
            SizedBox(height: 4),
            Text(
              '$current / ${next.key} days',
              style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey.shade500),
            ),
          ] else ...[
            // Beyond all defined milestones
            Row(
              children: [
                Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB800)),
                SizedBox(width: 6),
                Text(
                  'All milestones reached — legendary!',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFFFFB800),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          // ── Earned milestone chips ─────────────────────────────────────────
          if (milestones.isNotEmpty) ...[
            SizedBox(height: 12),
            const Divider(height: 1),
            SizedBox(height: 10),
            Text('Milestones earned',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: Colors.grey.shade500)),
            SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: milestones
                  .map((m) => _MilestoneChip(milestone: m))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MilestoneChip extends StatelessWidget {
  final MilestoneReward milestone;
  const _MilestoneChip({required this.milestone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B35).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded,
              size: 12, color: Color(0xFFFF6B35)),
          SizedBox(width: 3),
          Text(
            '${milestone.milestoneDays}d',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFFF6B35),
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakCardSkeleton extends StatelessWidget {
  const _StreakCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

// =============================================================================
// MilestoneToast
//
// An overlay widget that listens for newMilestoneProvider and displays a
// celebration banner automatically.
//
// Wrap your Scaffold body (or the whole MaterialApp subtree) with this:
//
//   MilestoneToastListener(
//     child: Scaffold(...),
//   )
// =============================================================================

class MilestoneToastListener extends ConsumerStatefulWidget {
  final Widget child;
  const MilestoneToastListener({super.key, required this.child});

  @override
  ConsumerState<MilestoneToastListener> createState() =>
      _MilestoneToastListenerState();
}

class _MilestoneToastListenerState
    extends ConsumerState<MilestoneToastListener> {
  @override
  Widget build(BuildContext context) {
    // Side-effect listener — show SnackBar when a milestone is earned.
    ref.listen<MilestoneReward?>(newMilestoneProvider, (prev, next) {
      if (next == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFFFF6B35),
          content: Row(
            children: [
              Text('🏆', style: TextStyle(fontSize: 22)),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${next.milestoneDays}-Day Streak!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '+${next.points} Plaro points awarded',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      // Clear the milestone so the toast doesn't re-show on rebuild.
      ref.read(streakProvider.notifier).clearNewMilestone();
    });

    return widget.child;
  }
}