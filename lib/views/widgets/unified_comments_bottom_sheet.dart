// Unified Instagram-style comment bottom sheet for Posts, Toasts, and Bytes
// UI-only widget that accepts callbacks - no provider logic
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/comment.dart';

/// Callbacks for comment operations (provider-agnostic)
class CommentSheetCallbacks {
  final Future<List<Comment>> Function() loadComments;
  final Future<List<Comment>> Function(String parentCommentId) loadReplies;
  final Future<int> Function(String parentCommentId) getRepliesCount;
  final Future<bool> Function(String content) addComment;
  final Future<bool> Function(String parentCommentId, String content) addReply;
  final Future<void> Function(String commentId) toggleCommentLike;
  final String? Function() getCurrentUserId;
  final Future<Map<String, dynamic>?> Function() getUserProfile;

  const CommentSheetCallbacks({
    required this.loadComments,
    required this.loadReplies,
    required this.getRepliesCount,
    required this.addComment,
    required this.addReply,
    required this.toggleCommentLike,
    required this.getCurrentUserId,
    required this.getUserProfile,
  });
}

/// Unified comment bottom sheet widget
/// Uses Instagram-style design consistent across all content types
class UnifiedCommentsBottomSheet extends StatefulWidget {
  final String contentId;
  final String title;
  final int? commentCount;
  final CommentSheetCallbacks callbacks;
  final Set<String> likingComments; // For loading state

  const UnifiedCommentsBottomSheet({
    super.key,
    required this.contentId,
    this.title = 'Comments',
    this.commentCount,
    required this.callbacks,
    this.likingComments = const {},
  });

  @override
  State<UnifiedCommentsBottomSheet> createState() => _UnifiedCommentsBottomSheetState();
}

class _UnifiedCommentsBottomSheetState extends State<UnifiedCommentsBottomSheet> {
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final FocusNode _replyFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  List<Comment> _comments = [];
  final Map<String, List<Comment>> _repliesByParent = {};
  final Set<String> _loadingReplies = {};
  final Set<String> _expandedComments = {};
  String? _activeReplyParentId;
  String? _activeReplyUsername;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadComments();
      }
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    _replyController.dispose();
    _commentFocusNode.dispose();
    _replyFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final comments = await widget.callbacks.loadComments();
      if (mounted) {
        setState(() {
          _comments = comments;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading comments: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load comments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadReplies(String parentCommentId) async {
    if (_loadingReplies.contains(parentCommentId)) return;

    setState(() => _loadingReplies.add(parentCommentId));

    try {
      final replies = await widget.callbacks.loadReplies(parentCommentId);
      if (!mounted) return;

      setState(() {
        _repliesByParent[parentCommentId] = replies;
        _loadingReplies.remove(parentCommentId);
        _expandedComments.add(parentCommentId);
      });
    } catch (e) {
      debugPrint('Error loading replies: $e');
      if (mounted) {
        setState(() => _loadingReplies.remove(parentCommentId));
      }
    }
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      final success = await widget.callbacks.addComment(text);

      if (success && mounted) {
        _commentController.clear();
        _commentFocusNode.unfocus();
        await _loadComments();

        // Scroll to top to show new comment
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post comment'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error submitting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post comment'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    if (mounted) setState(() => _isSubmitting = false);
  }

  Future<void> _submitReply(String parentCommentId, String parentUsername) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSubmitting = true);

    try {
      String content = text;
      // Ensure @mention is at the start
      if (!content.startsWith('@$parentUsername')) {
        content = '@$parentUsername $content';
      }

      final success = await widget.callbacks.addReply(parentCommentId, content);

      if (success && mounted) {
        _replyController.clear();
        _replyFocusNode.unfocus();
        setState(() {
          _activeReplyParentId = null;
          _activeReplyUsername = null;
        });

        // Reload replies for this comment
        await _loadReplies(parentCommentId);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post reply'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error submitting reply: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post reply'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }

    if (mounted) setState(() => _isSubmitting = false);
  }

  Future<void> _toggleCommentLike(String commentId) async {
    try {
      await widget.callbacks.toggleCommentLike(commentId);
      // Reload to get updated like state
      await _loadComments();
    } catch (e) {
      debugPrint('Error toggling comment like: $e');
    }
  }

  String _formatTimeAgo(DateTime createdAt) {
    final Duration diff = DateTime.now().difference(createdAt);

    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}mo';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m';
    } else {
      return 'now';
    }
  }

  void _startReply(String parentCommentId, String parentUsername) {
    setState(() {
      _activeReplyParentId = parentCommentId;
      _activeReplyUsername = parentUsername;
      _replyController.text = '@$parentUsername ';
      _replyController.selection = TextSelection.fromPosition(
        TextPosition(offset: _replyController.text.length),
      );
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        FocusScope.of(context).requestFocus(_replyFocusNode);
      }
    });
  }

  void _cancelReply() {
    setState(() {
      _activeReplyParentId = null;
      _activeReplyUsername = null;
      _replyController.clear();
    });
    _replyFocusNode.unfocus();
  }

  void _toggleRepliesVisibility(String commentId) {
    setState(() {
      if (_expandedComments.contains(commentId)) {
        _expandedComments.remove(commentId);
      } else {
        _expandedComments.add(commentId);
        if (!_repliesByParent.containsKey(commentId)) {
          _loadReplies(commentId);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = widget.callbacks.getCurrentUserId();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                    if (widget.commentCount != null)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${widget.commentCount}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else if (_comments.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_comments.length}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              Divider(color: Theme.of(context).cardColor, height: 1, thickness: 1),

              // Comments list
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: Colors.blue,
                          strokeWidth: 3,
                        ),
                      )
                    : _comments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No comments yet',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Be the first to comment!',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadComments,
                            color: Colors.blue,
                            backgroundColor: Theme.of(context).cardColor,
                            child: ListView.separated(
                              controller: scrollController,
                              padding: EdgeInsets.only(top: 8, bottom: 16),
                              itemCount: _comments.length,
                              separatorBuilder: (context, index) => Divider(
                                color: Theme.of(context).scaffoldBackgroundColor,
                                height: 1,
                                thickness: 1,
                                indent: 60,
                              ),
                              itemBuilder: (context, index) {
                                final comment = _comments[index];
                                final isLiking = widget.likingComments.contains(comment.commentId.toString());
                                final isExpanded = _expandedComments.contains(comment.commentId.toString());
                                final replies = _repliesByParent[comment.commentId.toString()] ?? [];
                                final isOwnComment = currentUserId == comment.userId;

                                return _buildCommentItem(
                                  comment: comment,
                                  isLiking: isLiking,
                                  isExpanded: isExpanded,
                                  replies: replies,
                                  isOwnComment: isOwnComment,
                                  currentUserId: currentUserId,
                                );
                              },
                            ),
                          ),
              ),

              // Input section
              _buildInputSection(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCommentItem({
    required Comment comment,
    required bool isLiking,
    required bool isExpanded,
    required List<Comment> replies,
    required bool isOwnComment,
    required String? currentUserId,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              GestureDetector(
                onTap: () {
                  // Navigate to user profile
                  // Navigator.pushNamed(context, '/profile', arguments: comment.userId);
                },
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context).cardColor,
                  backgroundImage: comment.profileImage.isNotEmpty
                      ? CachedNetworkImageProvider(comment.profileImage)
                      : null,
                  child: comment.profileImage.isEmpty
                      ? Text(
                          comment.username.isNotEmpty
                              ? comment.username[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              ),
              SizedBox(width: 12),

              // Comment content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username and time
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            comment.username,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          _formatTimeAgo(comment.createdAt),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (isOwnComment) ...[
                          SizedBox(width: 6),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'You',
                              style: TextStyle(
                                color: Colors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 6),

                    // Comment text
                    Text(
                      comment.content,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 10),

                    // Action buttons
                    Row(
                      children: [
                        // Like button
                        GestureDetector(
                          onTap: isLiking ? null : () => _toggleCommentLike(comment.commentId.toString()),
                          child: Row(
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: isLiking
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                        ),
                                      )
                                    : Icon(
                                        comment.isliked ? Icons.favorite : Icons.favorite_border,
                                        size: 19,
                                        color: comment.isliked ? Colors.red : Colors.grey[400],
                                        key: ValueKey(comment.isliked),
                                      ),
                              ),
                              if (comment.likes > 0) ...[
                                SizedBox(width: 5),
                                Text(
                                  '${comment.likes}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        SizedBox(width: 20),

                        // Reply button
                        GestureDetector(
                          onTap: () => _startReply(comment.commentId.toString(), comment.username),
                          child: Row(
                            children: [
                              Icon(Icons.reply, size: 18, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
                              SizedBox(width: 4),
                              Text(
                                'Reply',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // View/Hide replies button
          if (comment.parentCommentId == null)
            Padding(
              padding: EdgeInsets.only(left: 44, top: 10),
              child: _loadingReplies.contains(comment.commentId.toString())
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    )
                  : FutureBuilder<int>(
                      future: widget.callbacks.getRepliesCount(comment.commentId.toString()),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        if (count == 0 && replies.isEmpty) return const SizedBox.shrink();

                        final displayCount = replies.isNotEmpty ? replies.length : count;

                        return GestureDetector(
                          onTap: () => _toggleRepliesVisibility(comment.commentId.toString()),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isExpanded ? Icons.remove : Icons.add,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  isExpanded
                                      ? 'Hide replies'
                                      : 'View $displayCount ${displayCount == 1 ? 'reply' : 'replies'}',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

          // Replies section
          if (isExpanded && replies.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(left: 44, top: 12),
              child: Column(
                children: replies.map((reply) {
                  final isLikingReply = widget.likingComments.contains(reply.commentId.toString());
                  final isOwnReply = currentUserId == reply.userId;

                  return _buildReplyItem(reply, isLikingReply, isOwnReply);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReplyItem(Comment reply, bool isLiking, bool isOwnReply) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).cardColor,
            backgroundImage: reply.profileImage.isNotEmpty
                ? CachedNetworkImageProvider(reply.profileImage)
                : null,
            child: reply.profileImage.isEmpty
                ? Text(
                    reply.username.isNotEmpty ? reply.username[0].toUpperCase() : 'U',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        reply.username,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      _formatTimeAgo(reply.createdAt),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                    if (isOwnReply) ...[
                      SizedBox(width: 4),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'You',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  reply.content,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 6),
                // Like button for reply
                GestureDetector(
                  onTap: isLiking ? null : () => _toggleCommentLike(reply.commentId.toString()),
                  child: Row(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: isLiking
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                                ),
                              )
                            : Icon(
                                reply.isliked ? Icons.favorite : Icons.favorite_border,
                                size: 17,
                                color: reply.isliked ? Colors.red : Colors.grey[500],
                                key: ValueKey(reply.isliked),
                              ),
                      ),
                      if (reply.likes > 0) ...[
                        SizedBox(width: 4),
                        Text(
                          '${reply.likes}',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    final isReplying = _activeReplyParentId != null;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).cardColor,
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply indicator
            if (isReplying)
              Container(
                padding: EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.subdirectory_arrow_right,
                      size: 16,
                      color: Colors.blue[300],
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Replying to @$_activeReplyUsername',
                        style: TextStyle(
                          color: Colors.blue[300],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    GestureDetector(
                      onTap: _cancelReply,
                      child: Icon(
                        Icons.close,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),

            // Input row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // User avatar
                FutureBuilder<Map<String, dynamic>?>(
                  future: widget.callbacks.getUserProfile(),
                  builder: (context, snapshot) {
                    final profilePic = snapshot.data?['profile_pic'];

                    return CircleAvatar(
                      radius: 18,
                      backgroundColor: Theme.of(context).cardColor,
                      backgroundImage: profilePic != null && profilePic.toString().isNotEmpty
                          ? CachedNetworkImageProvider(profilePic)
                          : null,
                      child: (profilePic == null || profilePic.toString().isEmpty)
                          ? Icon(Icons.person, size: 20, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))
                          : null,
                    );
                  },
                ),
                SizedBox(width: 12),

                // Text field
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 100),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: isReplying ? _replyController : _commentController,
                      focusNode: isReplying ? _replyFocusNode : _commentFocusNode,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        hintText: isReplying ? 'Write a reply...' : 'Add a comment...',
                        hintStyle: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                        isDense: true,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                SizedBox(width: 10),

                // Send button
                GestureDetector(
                  onTap: _isSubmitting
                      ? null
                      : (isReplying
                          ? () => _submitReply(_activeReplyParentId!, _activeReplyUsername!)
                          : _submitComment),
                  child: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isSubmitting ? Colors.grey[700] : Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isSubmitting
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Theme.of(context).colorScheme.onSurface,
                                strokeWidth: 2,
                              ),
                            )
                          : Icon(
                              Icons.send_rounded,
                              color: Theme.of(context).colorScheme.onSurface,
                              size: 18,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

