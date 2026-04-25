
// widgets/comment_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../Viewmodels/post_feed_provider.dart';
import '../../models/comment.dart';

class CommentCard extends ConsumerStatefulWidget {
  final Comment comment;
  final String postId;
  final VoidCallback? onTap;
  final bool showReplies;

  const CommentCard({
    super.key,
    required this.comment,
    required this.postId,
    this.onTap,
    this.showReplies = true,
  });

  @override
  ConsumerState<CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends ConsumerState<CommentCard> {
  bool _showReplyField = false;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  bool _isSubmittingReply = false; // Track reply submission state
  bool _repliesExpanded = false;
  bool _isLoadingReplies = false;
  List<Comment> _replies = [];
  int _replyCount = 0;

  @override
  void dispose() {
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider to rebuild on state changes
    final postFeedState = ref.watch(postFeedProvider);
    // Use provider's likingComments to show per-comment loading state if needed
    final isLiking = postFeedState.likingComments.contains(widget.comment.commentId.toString());

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main comment content
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Profile picture
                  CircleAvatar(
                    backgroundImage: widget.comment.profileImage.isNotEmpty
                        ? NetworkImage(widget.comment.profileImage)
                        : const AssetImage('assets/plaro new logo.png') as ImageProvider,
                    radius: 16,
                  ),
                  SizedBox(width: 12),

                  // Comment content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Username and timestamp
                        Row(
                          children: [
                            Text(
                              widget.comment.username,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              widget.comment.timeAgo,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),

                        // Comment text
                        Text(
                          widget.comment.content,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                            height: 1.3,
                          ),
                        ),
                        SizedBox(height: 8),

                        // Action buttons
                        Row(
                          children: [
                            // Like button
                            _CommentActionButton(
                              icon: widget.comment.isliked
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              label: widget.comment.likes > 0
                                  ? '${widget.comment.likes}'
                                  : '',
                              color: widget.comment.isliked
                                  ? Colors.red
                                  : Colors.grey,
                              isLoading: isLiking,
                              onPressed: () async {
                                // Optimistic toggle
                                setState(() {
                                  widget.comment.toggleLike();
                                });
                                await ref.read(postFeedProvider.notifier).toggleCommentLike(widget.comment.commentId);
                              },
                            ),
                            SizedBox(width: 16),

                            // Reply button
                            _CommentActionButton(
                              icon: Icons.reply_outlined,
                              label: 'Reply',
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              onPressed: () {
                                setState(() {
                                  _showReplyField = !_showReplyField;
                                });
                                if (_showReplyField) {
                                  // Prefill mention like Instagram and focus
                                  if (!_replyController.text.startsWith('@${widget.comment.username}')) {
                                    _replyController.text = '@${widget.comment.username} ';
                                  }
                                  _replyController.selection = TextSelection.fromPosition(
                                    TextPosition(offset: _replyController.text.length),
                                  );
                                  FocusScope.of(context).requestFocus(_replyFocusNode);
                                }
                              },
                            ),
                            SizedBox(width: 16),

                            // More options button
                            _CommentActionButton(
                              icon: Icons.more_horiz,
                              label: '',
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                              onPressed: () {
                                _showCommentOptions(context);
                              },
                            ),
                          ],
                        ),

                        // View replies / Hide replies toggle, Instagram-style
                        Padding(
                          padding: EdgeInsets.only(top: 4.0, left: 0),
                          child: Row(
                            children: [
                              FutureBuilder<int>(
                                future: ref.read(postFeedProvider.notifier).getRepliesCount(widget.comment.commentId),
                                builder: (context, snapshot) {
                                  final count = snapshot.data ?? _replyCount;
                                  _replyCount = count;
                                  if (count <= 0) return const SizedBox.shrink();

                                  return TextButton(
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                    onPressed: _repliesExpanded ? _hideReplies : _loadReplies,
                                    child: Text(
                                      _repliesExpanded ? 'Hide replies' : 'View replies ($count)',
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 13),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),

                        // Reply field
                        if (_showReplyField)
                          Container(
                            margin: EdgeInsets.only(top: 12),
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _replyController,
                                    focusNode: _replyFocusNode,
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                    decoration: InputDecoration(
                                      hintText: 'Reply to ${widget.comment.username}...',
                                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    maxLines: null,
                                  ),
                                ),
                                SizedBox(width: 8),
                                IconButton(
                                  onPressed: _isSubmittingReply ? null : () { _submitReply(); },
                                  icon: _isSubmittingReply
                                      ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue),
                                  )
                                      : Icon(Icons.send, color: Colors.blue, size: 20),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // Replies section (if enabled)
              if (widget.showReplies)
                _buildRepliesSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRepliesSection() {
    if (!_repliesExpanded) return const SizedBox.shrink();

    if (_isLoadingReplies) {
      return Padding(
        padding: EdgeInsets.only(left: 52.0, top: 8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_replies.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(left: 52.0, top: 8), // indent under avatar, Instagram style
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _replies.map((reply) {
          return Padding(
            padding: EdgeInsets.only(bottom: 10.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundImage: reply.profileImage.isNotEmpty
                      ? NetworkImage(reply.profileImage)
                      : const AssetImage('assets/plaro new logo.png') as ImageProvider,
                  radius: 12, // smaller avatar for replies
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            reply.username,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 6),
                          Text(
                            reply.timeAgo,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5), fontSize: 11),
                          ),
                        ],
                      ),
                      SizedBox(height: 3),
                      Text(
                        reply.content,
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 13, height: 1.3),
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          _CommentActionButton(
                            icon: reply.isliked ? Icons.favorite : Icons.favorite_border,
                            label: reply.likes > 0 ? '${reply.likes}' : '',
                            color: reply.isliked ? Colors.red : Colors.grey,
                            onPressed: () async {
                              await ref.read(postFeedProvider.notifier).toggleCommentLike(reply.commentId);
                              // Optimistic UI update
                              setState(() {
                                reply.toggleLike();
                              });
                            },
                          ),
                          SizedBox(width: 12),
                          _CommentActionButton(
                            icon: Icons.reply_outlined,
                            label: 'Reply',
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            onPressed: () {
                              // Set replying to this reply's author
                              setState(() {
                                _showReplyField = true;
                              });
                              _replyController.text = '@${reply.username} ';
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _submitReply() {
    if (_replyController.text.trim().isEmpty) return;

    final replyText = _replyController.text.trim();

    // Set loading state
    setState(() {
      _isSubmittingReply = true;
    });

    // Add the reply tagged to the parent comment, Instagram-style threads
    final replyContent = "@${widget.comment.username} $replyText";

    ref.read(postFeedProvider.notifier).addReply(widget.postId, widget.comment.commentId, replyContent).then((success) {
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reply submitted successfully'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        // Reload replies
        _loadReplies();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit reply'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (mounted) {
        setState(() {
          _isSubmittingReply = false;
          _showReplyField = false;
          _replyController.clear();
        });
      }
    });
  }

  void _loadReplies() async {
    setState(() {
      _isLoadingReplies = true;
      _repliesExpanded = true;
    });
    final replies = await ref.read(postFeedProvider.notifier).loadReplies(widget.postId, widget.comment.commentId);
    if (!mounted) return;
    setState(() {
      _replies = replies;
      _isLoadingReplies = false;
    });
  }

  void _hideReplies() {
    setState(() {
      _repliesExpanded = false;
    });
  }

  void _showCommentOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.copy_outlined, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                title: Text('Copy Comment', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _copyComment();
                },
              ),
              ListTile(
                leading: Icon(Icons.report_outlined, color: Colors.red),
                title: Text('Report Comment', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _reportComment();
                },
              ),
              ListTile(
                leading: Icon(Icons.block_outlined, color: Colors.orange),
                title: Text('Block User', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
                onTap: () {
                  Navigator.pop(context);
                  _blockUser();
                },
              ),
              SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _copyComment() {
    // TODO: Implement copy to clipboard
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Comment copied to clipboard'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _reportComment() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Report Comment', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Are you sure you want to report this comment? We will review it and take appropriate action.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Comment reported successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text('Report', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _blockUser() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: Text('Block User', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Are you sure you want to block ${widget.comment.username}? You won\'t see their comments anymore.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('User blocked successfully'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: Text('Block', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _CommentActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _CommentActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            else
              Icon(icon, color: color, size: 16),
            if (label.isNotEmpty) ...[
              SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
