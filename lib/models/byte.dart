
// Byte model
class Byte {
  final String byteId;
  final String userId;
  final String videoUrl; // Added: video URL
  final String? thumbnailUrl; // Added: thumbnail URL for optimization
  final String? caption;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? username;
  final String? profilePic;
  final bool? isliked;

  Byte({
    required this.byteId,
    required this.userId,
    required this.videoUrl, // Added
    this.thumbnailUrl, // Added
    this.caption,
    required this.likeCount,
    required this.commentCount,
    required this.shareCount,
    required this.createdAt,
    required this.updatedAt,
    this.username,
    this.profilePic,
    this.isliked,
  });

  factory Byte.fromJson(Map<String, dynamic> json) {
    // Helper function to safely convert to int
    int safeInt(dynamic value, int defaultValue) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    // Helper function to safely convert to String
    String safeString(dynamic value, String defaultValue) {
      if (value == null) return defaultValue;
      return value.toString();
    }

    return Byte(
      byteId: safeString(json['byte_id'], ''),
      userId: safeString(json['user_id'], ''),
      videoUrl: safeString(json['video_url'] ?? json['byte'], ''), // Support both 'video_url' and 'byte' fields
      thumbnailUrl: json['thumbnail_url']?.toString(),
      caption: json['caption']?.toString(),
      likeCount: safeInt(json['like_count'], 0),
      commentCount: safeInt(json['comment_count'], 0),
      shareCount: safeInt(json['share_count'], 0),
      createdAt: DateTime.parse(
          json['created_at']?.toString() ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(
          json['updated_at']?.toString() ?? DateTime.now().toIso8601String()),
      username: json['username']?.toString(),
      profilePic: json['profile_pic']?.toString(),
      isliked: json['isliked'] == true || json['isliked'] == 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'byte_id': byteId,
      'user_id': userId,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'caption': caption,
      'like_count': likeCount,
      'comment_count': commentCount,
      'share_count': shareCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Copy with method for optimistic updates
  Byte copyWith({
    String? byteId,
    String? userId,
    String? videoUrl,
    String? thumbnailUrl,
    String? caption,
    int? likeCount,
    int? commentCount,
    int? shareCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? username,
    String? profilePic,
    bool? isliked,
  }) {
    return Byte(
      byteId: byteId ?? this.byteId,
      userId: userId ?? this.userId,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      caption: caption ?? this.caption,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      username: username ?? this.username,
      profilePic: profilePic ?? this.profilePic,
      isliked: isliked ?? this.isliked,
    );
  }

  /// Convert a list of JSON maps to a list of Byte objects
  static List<Byte> listFromJson(List<dynamic> jsonList) {
    return jsonList.map((json) => Byte.fromJson(json)).toList();
  }

  /// Debug print (for logging)
  @override
  String toString() {
    return 'Byte(byteId: $byteId, userId: $userId, videoUrl: $videoUrl, '
        'thumbnailUrl: $thumbnailUrl, caption: $caption, '
        'likes: $likeCount, comments: $commentCount, shares: $shareCount, '
        'isliked: $isliked, username: $username)';
  }

  /// Getter for imageUrls to maintain compatibility with profile grid
  List<String> get imageUrls {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return [thumbnailUrl!];
    }
    return [];
  }
}