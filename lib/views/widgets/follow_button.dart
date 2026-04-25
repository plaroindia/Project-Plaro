import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../Viewmodels/follow_provider.dart';
import '../../Viewmodels/auth_provider.dart';

class FollowButton extends ConsumerStatefulWidget {
  final String targetUserId;
  final bool compact;
  final VoidCallback? onFollowSuccess;
  final VoidCallback? onFollowError;

  const FollowButton({
    super.key,
    required this.targetUserId,
    this.compact = false,
    this.onFollowSuccess,
    this.onFollowError,
  });

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      lowerBound: 0.92,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = _animController;

    // FIX: refreshFollowingStatus now skips the DB call when the status is
    // already known (the fix lives in follow_provider.dart). This means
    // ValueKey remounts (e.g. swiping to a new byte author) no longer fire
    // an async DB round-trip that temporarily returns null and flashes
    // "Follow" even when the user is already following.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(followProvider.notifier)
            .refreshFollowingStatus(widget.targetUserId);
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleToggleFollow() async {
    // Bounce animation
    await _animController.reverse();
    _animController.forward();

    try {
      // toggleFollowWithDebounce returns true if the toggle ran,
      // false if it was swallowed by the debounce guard.
      // We only show the snackbar (and fire the callback) when a real
      // toggle happened — otherwise we'd read stale state and show a
      // misleading "Unfollowed" message.
      final didToggle = await ref
          .read(followProvider.notifier)
          .toggleFollowWithDebounce(widget.targetUserId);

      if (!didToggle) return; // debounced — nothing changed, stay silent

      widget.onFollowSuccess?.call();

      if (mounted) {
        // Read AFTER the toggle so we see the now-current optimistic state.
        final nowFollowing =
            ref.read(isFollowingProvider(widget.targetUserId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  nowFollowing
                      ? Icons.person_add_rounded
                      : Icons.person_remove_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(nowFollowing ? 'Following' : 'Unfollowed'),
              ],
            ),
            backgroundColor:
                nowFollowing ? const Color(0xFF0077FF) : Colors.grey[700],
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      widget.onFollowError?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to update follow status'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final currentUserId = authState.value?.user.id;

    // Hide for own profile or unauthenticated
    if (currentUserId == null || currentUserId == widget.targetUserId) {
      return const SizedBox.shrink();
    }

    final isFollowing = ref.watch(isFollowingProvider(widget.targetUserId));
    final isProcessing =
        ref.watch(isProcessingFollowProvider(widget.targetUserId));

    return ScaleTransition(
      scale: _scaleAnim,
      child: widget.compact
          ? _buildCompactButton(isFollowing, isProcessing)
          : _buildFullButton(isFollowing, isProcessing),
    );
  }

  Widget _buildCompactButton(bool isFollowing, bool isProcessing) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isProcessing ? null : _handleToggleFollow,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: isFollowing
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: isFollowing ? Colors.transparent : null,
          border: Border.all(
            color: isFollowing
                ? Colors.white.withOpacity(0.6)
                : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: isProcessing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                isFollowing ? 'Following' : 'Follow',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
      ),
    );
  }

  Widget _buildFullButton(bool isFollowing, bool isProcessing) {
    return GestureDetector(
      onTap: isProcessing ? null : _handleToggleFollow,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        height: 44,
        decoration: BoxDecoration(
          gradient: isFollowing
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: isFollowing ? Colors.transparent : null,
          border: Border.all(
            color: isFollowing
                ? Colors.blue.withOpacity(0.5)
                : Colors.transparent,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: isFollowing
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFF0077FF).withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Center(
          child: isProcessing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isFollowing
                          ? Icons.how_to_reg_rounded
                          : Icons.person_add_rounded,
                      color: isFollowing
                          ? Colors.blue.withOpacity(0.8)
                          : Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: isFollowing
                            ? Colors.blue.withOpacity(0.9)
                            : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}