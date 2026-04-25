/// Unified Comment model for Posts, Toasts, and Bytes
/// Supports all comment types with a flexible structure
class Comment {
  final int commentId;
  final String? postId;      // For post comments
  final String? toastId;     // For toast comments
  final String? byteId;      // For byte comments
  final String userId;
  final String username;
  final String profileImage;
  final String content;
  int likes;
  bool isliked;              // Unified name (was 'uliked' in toast comments)
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int? parentCommentId;
  final int? replyCount;
  List<Comment> replies;     // Nested replies

  Comment({
    required this.commentId,
    this.postId,
    this.toastId,
    this.byteId,
    required this.userId,
    required this.username,
    required this.profileImage,
    required this.content,
    this.likes = 0,
    this.isliked = false,
    required this.createdAt,
    this.updatedAt,
    this.parentCommentId,
    this.replyCount,
    this.replies = const [],
  }) : assert(
          (postId != null && toastId == null && byteId == null) ||
          (postId == null && toastId != null && byteId == null) ||
          (postId == null && toastId == null && byteId != null),
          'Comment must have exactly one of: postId, toastId, or byteId',
        );

  /// Get the parent ID (post, toast, or byte)
  String? get parentId => postId ?? toastId ?? byteId;

  /// Get comment type
  CommentType get type {
    if (postId != null) return CommentType.post;
    if (toastId != null) return CommentType.toast;
    if (byteId != null) return CommentType.byte;
    throw StateError('Comment must have a parent ID');
  }

  String get timeAgo => _formatTimeAgo(createdAt);

  void toggleLike() {
    if (isliked) {
      likes = likes > 0 ? likes - 1 : 0;
      isliked = false;
    } else {
      likes++;
      isliked = true;
    }
  }

  /// Factory constructor for post comments
  factory Comment.fromPostMap(Map<String, dynamic> map) {
    return Comment(
      commentId: map['comment_id'] ?? 0,
      postId: (map['post_id'] ?? '').toString(),
      userId: map['user_id'] ?? '',
      username: map['username'] ?? 'Unknown User',
      profileImage: map['profile_pic'] ?? 'assets/plaro_logo.png',
      content: map['content'] ?? '',
      likes: map['like_count'] ?? 0,
      isliked: map['isliked'] ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : null,
      parentCommentId: map['parent_comment_id'],
      replyCount: map['reply_count'],
      replies: map['replies'] != null
          ? (map['replies'] as List)
              .map((r) => Comment.fromPostMap(r))
              .toList()
          : [],
    );
  }

  /// Factory constructor for toast comments
  factory Comment.fromToastMap(Map<String, dynamic> map) {
    return Comment(
      commentId: map['comment_id'] ?? 0,
      toastId: (map['toast_id'] ?? '').toString(),
      userId: map['user_id'] ?? '',
      username: map['username'] ?? 'Unknown User',
      profileImage: map['profile_pic'] ?? 'assets/plaro_logo.png',
      content: map['content'] ?? '',
      likes: map['like_count'] ?? 0,
      isliked: map['uliked'] ?? false, // Handle legacy 'uliked' field
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'])
          : null,
      parentCommentId: map['parent_comment_id'],
    );
  }

  /// Factory constructor for byte comments
  factory Comment.fromByteMap(Map<String, dynamic> map) {
    return Comment(
      commentId: int.tryParse(map['comment_id']?.toString() ?? '0') ?? 0,
      byteId: map['byte_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      username: map['username']?.toString() ?? 'Unknown User',
      profileImage: map['profile_pic']?.toString() ?? 'assets/plaro_logo.png',
      content: map['content']?.toString() ?? '',
      likes: map['like_count'] is int
          ? map['like_count']
          : int.tryParse(map['like_count']?.toString() ?? '0') ?? 0,
      isliked: map['isliked'] == true || map['isliked'] == 1,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'].toString())
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'].toString())
          : null,
      parentCommentId: map['parent_comment_id'] is int
          ? map['parent_comment_id'] as int
          : int.tryParse(map['parent_comment_id']?.toString() ?? ''),
    );
  }

  /// Generic factory that tries to detect the type
  factory Comment.fromMap(Map<String, dynamic> map) {
    if (map.containsKey('post_id')) {
      return Comment.fromPostMap(map);
    } else if (map.containsKey('toast_id')) {
      return Comment.fromToastMap(map);
    } else if (map.containsKey('byte_id')) {
      return Comment.fromByteMap(map);
    } else {
      throw ArgumentError('Map must contain post_id, toast_id, or byte_id');
    }
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'comment_id': commentId,
      'user_id': userId,
      'username': username,
      'profile_pic': profileImage,
      'content': content,
      'like_count': likes,
      'isliked': isliked,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
      if (parentCommentId != null) 'parent_comment_id': parentCommentId,
      if (replyCount != null) 'reply_count': replyCount,
    };

    // Add the appropriate parent ID
    if (postId != null) {
      map['post_id'] = postId;
    } else if (toastId != null) {
      map['toast_id'] = toastId;
    } else if (byteId != null) {
      map['byte_id'] = byteId;
    }

    if (replies.isNotEmpty) {
      map['replies'] = replies.map((r) => r.toMap()).toList();
    }

    return map;
  }

  Comment copyWith({
    int? commentId,
    String? postId,
    String? toastId,
    String? byteId,
    String? userId,
    String? username,
    String? profileImage,
    String? content,
    int? likes,
    bool? isliked,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? parentCommentId,
    int? replyCount,
    List<Comment>? replies,
  }) {
    return Comment(
      commentId: commentId ?? this.commentId,
      postId: postId ?? this.postId,
      toastId: toastId ?? this.toastId,
      byteId: byteId ?? this.byteId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      profileImage: profileImage ?? this.profileImage,
      content: content ?? this.content,
      likes: likes ?? this.likes,
      isliked: isliked ?? this.isliked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      replyCount: replyCount ?? this.replyCount,
      replies: replies ?? this.replies,
    );
  }

  static String _formatTimeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }
}

enum CommentType {
  post,
  toast,
  byte,
}

