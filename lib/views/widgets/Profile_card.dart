import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../models/user_profile.dart';
import '../../Viewmodels/follow_provider.dart';


class ProfileCard extends ConsumerStatefulWidget {
  final UserProfile user;
  final VoidCallback? onTap;
  final bool showFollowButton;

  const ProfileCard({
    super.key,
    required this.user,
    this.onTap,
    this.showFollowButton = true,
  });

  @override
  ConsumerState<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<ProfileCard> {
  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;
  bool get _isCurrentUser => _currentUserId == widget.user.user_id;

  @override
  Widget build(BuildContext context) {
    final isFollowing = ref.watch(isFollowingProvider(widget.user.user_id));
    final isProcessing = ref.watch(isProcessingFollowProvider(widget.user.user_id));

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).cardColor,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Profile Picture
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                border: Border.all(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  width: 2,
                ),
              ),
              child: widget.user.profilePic != null
                  ? ClipOval(
                child: Image.network(
                  widget.user.profilePic!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.person,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      size: 24,
                    );
                  },
                ),
              )
                  : Icon(
                Icons.person,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                size: 24,
              ),
            ),
            SizedBox(width: 12),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.user.username,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.user.isVerified == true) ...[
                        SizedBox(width: 4),
                        Icon(
                          Icons.verified,
                          color: Colors.blue[400],
                          size: 16,
                        ),
                      ],
                    ],
                  ),
                  if (widget.user.role != null) ...[
                    SizedBox(height: 4),
                    Text(
                      widget.user.role!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (widget.user.location != null) ...[
                    SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          size: 12,
                        ),
                        SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            widget.user.location!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Stats and Follow Button
            Column(
              children: [
                if (widget.user.followersCount != null) ...[
                  Column(
                    children: [
                      Text(
                        _formatCount(widget.user.followersCount!),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Followers',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                ],

                // Follow/Unfollow Button
                if (widget.showFollowButton && !_isCurrentUser && _currentUserId != null)
                  _buildFollowButton(isFollowing, isProcessing),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowButton(bool isFollowing, bool isProcessing) {
    return SizedBox(
      width: 90,
      height: 32,
      child: ElevatedButton(
        onPressed: isProcessing ? null : () => _handleFollowToggle(),
        style: ElevatedButton.styleFrom(
          backgroundColor: isFollowing ? Colors.grey[800] : Colors.blue,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          padding: EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: isFollowing
                ? BorderSide(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), width: 1)
                : BorderSide.none,
          ),
        ),
        child: isProcessing
            ? SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white.withOpacity(0.8),
            ),
          ),
        )
            : Text(
          isFollowing ? 'Following' : 'Follow',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _handleFollowToggle() {
    final followNotifier = ref.read(followProvider.notifier);
    followNotifier.toggleFollow(widget.user.user_id);

    // Provide haptic feedback
    // HapticFeedback.lightImpact();
  }

  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
  }
}