import 'package:image_picker/image_picker.dart';
import 'comment.dart';

class Post_feed {
  String? post_id;
  String? user_id;
  String? profile_pic;
  String? username;
  String? content;
  String? caption;
  String? title;
  List<String>? tags;
  DateTime? created_at;
  int like_count;
  bool isliked;
  int comment_count;
  int? share_count;
  List<Comment> commentsList;
  List<String>? media_urls;
  List<XFile>? localMediaFiles;

  Post_feed({
    required this.post_id,
    required this.user_id,
    required this.username,
    this.profile_pic,
    this.content,
    this.caption,
    this.title,
    this.tags,
    this.created_at,
    this.like_count = 0,
    this.isliked = false,
    this.comment_count = 0,
    this.share_count = 0,
    required this.commentsList,
    this.media_urls,
    this.localMediaFiles,
  });

  factory Post_feed.fromMap(Map<String, dynamic> data) {
    return Post_feed(
      post_id: data['post_id'],
      user_id: data['user_id'],
      username: data['username'],
      profile_pic: data['profile_pic'],
      content: data['content'],
      caption: data['caption'],
      title: data['title'],
      tags: data['tags'] != null ? List<String>.from(data['tags']) : [],
      created_at: data['created_at'] != null
          ? DateTime.parse(data['created_at'])
          : null,
      like_count: data['like_count'] ?? 0,
      comment_count: data['comment_count'] ?? 0,
      share_count: data['share_count'] ?? 0,
      isliked: data['isliked'] ?? false,
      media_urls: data['media_urls'] != null
          ? List<String>.from(data['media_urls'])
          : data['image_urls'] != null // Support both 'media_urls' and 'image_urls'
          ? List<String>.from(data['image_urls'])
          : null,
      // Accept either 'comments' or 'post_comments' as the payload key
      commentsList: (data['comments'] ?? data['post_comments']) != null
          ? List.from(data['comments'] ?? data['post_comments'])
          .map((comment) => Comment.fromPostMap(comment))
          .toList()
          : [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'post_id': post_id,
      'user_id': user_id,
      'username': username,
      'profile_pic': profile_pic,
      'content': content,
      'caption': caption,
      'title': title,
      'tags': tags,
      'created_at': created_at?.toIso8601String(),
      'like_count': like_count,
      'comment_count': comment_count,
      'share_count': share_count,
      'isliked': isliked,
      'media_urls': media_urls,
      'image_urls': imageUrls, // Also store as image_urls for compatibility
      'localMediaFiles': localMediaFiles?.map((x) => x.path).toList(),
      'comments': commentsList.map((c) => c.toMap()).toList(),
    };
  }

  Post_feed copyWith({
    String? post_id,
    String? user_id,
    String? profile_pic,
    String? username,
    String? content,
    String? caption,
    String? title,
    List<String>? tags,
    DateTime? created_at,
    int? like_count,
    bool? isliked,
    int? comment_count,
    int? share_count,
    List<Comment>? commentsList,
    List<String>? media_urls,
    List<XFile>? localMediaFiles,
  }) {
    return Post_feed(
      post_id: post_id ?? this.post_id,
      user_id: user_id ?? this.user_id,
      profile_pic: profile_pic ?? this.profile_pic,
      username: username ?? this.username,
      content: content ?? this.content,
      caption: caption ?? this.caption,
      title: title ?? this.title,
      tags: tags ?? this.tags,
      created_at: created_at ?? this.created_at,
      like_count: like_count ?? this.like_count,
      isliked: isliked ?? this.isliked,
      comment_count: comment_count ?? this.comment_count,
      share_count: share_count ?? this.share_count,
      commentsList: commentsList ?? this.commentsList,
      media_urls: media_urls ?? this.media_urls,
      localMediaFiles: localMediaFiles ?? this.localMediaFiles,
    );
  }

  void toggleLike() {
    if (isliked) {
      like_count = like_count > 0 ? like_count - 1 : 0;
      isliked = false;
    } else {
      like_count++;
      isliked = true;
    }
  }

  void incrementComments() {
    comment_count++;
  }

  void incrementShares() {
    share_count = (share_count ?? 0) + 1;
  }

  /// Getter for imageUrls to maintain compatibility with profile grid
  List<String> get imageUrls => media_urls ?? [];
}