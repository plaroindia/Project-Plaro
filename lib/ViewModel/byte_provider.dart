import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import '../Model/byte.dart';
import '../Model/comment.dart';
import 'streakandpoints_provider.dart';


// Byte create state
class ByteCreateState {
  final XFile? selectedVideo;
  final String caption;
  final bool isLoading;
  final String? error;
  final bool isUploading;
  final double uploadProgress;
  final List<String> tags;
  final String? domain;

  ByteCreateState({
    this.selectedVideo,
    this.caption = '',
    this.isLoading = false,
    this.error,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.tags = const [],
    this.domain,
  });

  ByteCreateState copyWith({
    XFile? selectedVideo,
    String? caption,
    bool? isLoading,
    String? error,
    bool? isUploading,
    double? uploadProgress,
    List<String>? tags,
    String? domain,
  }) {
    return ByteCreateState(
      selectedVideo: selectedVideo ?? this.selectedVideo,
      caption: caption ?? this.caption,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      tags: tags ?? this.tags,
      domain: domain ?? this.domain,
    );
  }
}

// Bytes feed state
class BytesFeedState {
  final List<Byte> bytes;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final Set<String> likingBytes;
  final Set<String> likingComments;
  final bool hasMore;
  final int currentPage;
  final Map<String, List<Comment>> commentsByByteId;
  final Set<String> loadingComments;
  // Recommendation cursor fields (keyset pagination)
  final double? nextCursorScore;
  final String? nextCursorId;
  final DateTime? lastFetchTime;

  const BytesFeedState({
    this.bytes = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
    this.likingBytes = const {},
    this.likingComments = const {},
    this.hasMore = true,
    this.currentPage = 0,
    this.commentsByByteId = const {},
    this.loadingComments = const {},
    this.nextCursorScore,
    this.nextCursorId,
    this.lastFetchTime,
  });

  BytesFeedState copyWith({
    List<Byte>? bytes,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    Set<String>? likingBytes,
    Set<String>? likingComments,
    bool? hasMore,
    int? currentPage,
    Map<String, List<Comment>>? commentsByByteId,
    Set<String>? loadingComments,
    double? nextCursorScore,
    String? nextCursorId,
    DateTime? lastFetchTime,
    bool clearCursor = false,
  }) {
    return BytesFeedState(
      bytes: bytes ?? this.bytes,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: error,
      likingBytes: likingBytes ?? this.likingBytes,
      likingComments: likingComments ?? this.likingComments,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      commentsByByteId: commentsByByteId ?? this.commentsByByteId,
      loadingComments: loadingComments ?? this.loadingComments,
      nextCursorScore: clearCursor ? null : (nextCursorScore ?? this.nextCursorScore),
      nextCursorId:    clearCursor ? null : (nextCursorId    ?? this.nextCursorId),
      lastFetchTime:  lastFetchTime ?? this.lastFetchTime,
    );
  }
}

// Byte create provider
class ByteCreateNotifier extends StateNotifier<ByteCreateState> {
  ByteCreateNotifier(this._pointsService, this._ref) : super(ByteCreateState());

  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final PlaroPointsService _pointsService;
  final Ref _ref;

  void updateCaption(String caption) {
    state = state.copyWith(caption: caption);
  }

  void updateTags(List<String> tags) {
    state = state.copyWith(tags: tags);
  }

  void updateDomain(String domain) {
    state = state.copyWith(domain: domain);
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  void clearVideo() {
    state = state.copyWith(selectedVideo: null);
  }

  Future<void> pickVideo({bool fromCamera = false}) async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(minutes: 1),
        preferredCameraDevice: CameraDevice.rear,
      );

      if (video != null) {
        final File videoFile = File(video.path);
        final int fileSizeInBytes = await videoFile.length();
        final double fileSizeInMB = fileSizeInBytes / (1024 * 1024);

        if (fileSizeInMB > 50) {
          state = state.copyWith(error: 'Video file size must be less than 50MB');
          return;
        }

        state = state.copyWith(selectedVideo: video, error: null);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick video: ${e.toString()}');
    }
  }

  Future<String?> _uploadVideo(XFile video) async {
    try {
      final String fileName = 'byte_${DateTime.now().millisecondsSinceEpoch}_${_supabase.auth.currentUser?.id}.mp4';
      final File videoFile = File(video.path);

      state = state.copyWith(isUploading: true, uploadProgress: 0.0);

      await _supabase.storage.from('bytes').uploadBinary(
        fileName,
        await videoFile.readAsBytes(),
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );

      final String publicUrl = _supabase.storage.from('bytes').getPublicUrl(fileName);

      state = state.copyWith(uploadProgress: 1.0);
      return publicUrl;
    } catch (e) {
      state = state.copyWith(error: 'Failed to upload video: ${e.toString()}');
      return null;
    } finally {
      state = state.copyWith(isUploading: false);
    }
  }

  Future<bool> createByte() async {
    if (state.selectedVideo == null) {
      state = state.copyWith(error: 'Please select a video');
      return false;
    }

    // DOMAIN VALIDATION
    if (state.domain == null || state.domain!.isEmpty) {
      state = state.copyWith(error: 'Please select a domain');
      return false;
    }

    // TAGS VALIDATION
    if (state.tags.isEmpty) {
      state = state.copyWith(error: 'Please add at least one tag to help categorize your byte');
      return false;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      state = state.copyWith(error: 'Please log in to create a byte');
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      debugPrint('Starting byte creation...');

      final String? videoUrl = await _uploadVideo(state.selectedVideo!);
      if (videoUrl == null) {
        debugPrint('Video upload failed');
        return false;
      }

      debugPrint('Video uploaded: $videoUrl');
      debugPrint('Inserting into database...');

      final response = await _supabase.from('bytes').insert({
        'user_id': user.id,
        'byte': videoUrl,
        'caption': state.caption.trim().isEmpty ? null : state.caption.trim(),
        'tags': state.tags,
        'domain': state.domain,
        'like_count': 0,
        'comment_count': 0,
        'share_count': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select('byte_id').single();

      debugPrint('Database response: $response');

      // Award points for creating byte
      final byteId = response['byte_id'];
      debugPrint('Byte created successfully with ID: $byteId');

      try {
        await _pointsService.awardPointsForContent(
          userId: user.id,
          contentType: 'byte',
          contentId: byteId,
        );

        debugPrint('✅ Points awarded successfully for byte $byteId');

      } catch (pointsError, pointsStack) {
        debugPrint('❌ Failed to award points for byte $byteId: $pointsError');
        debugPrint('Points stack trace: $pointsStack');
        // Don't fail the whole operation if points fail
      }
      _ref.read(streakProvider.notifier).logByteCreated(
        byteId: (byteId as num).toInt(),
        domain: state.domain,
      );
      state = ByteCreateState();
      return true;

    } catch (e, stackTrace) {
      debugPrint('Error creating byte: $e');
      debugPrint('Stack trace: $stackTrace');
      state = state.copyWith(error: 'Failed to create byte: ${e.toString()}');
      return false;
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<bool> deleteByte(String byteId) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final byteResponse = await _supabase
          .from('bytes')
          .select('user_id, byte')
          .eq('byte_id', byteId)
          .single();

      if (byteResponse['user_id'] != user.id) {
        throw Exception('You can only delete your own bytes');
      }

      final String videoUrl = byteResponse['byte'];
      final String fileName = videoUrl.split('/').last;
      await _supabase.storage.from('bytes').remove([fileName]);

      await _supabase.from('bytes').delete().eq('byte_id', byteId);

      return true;
    } catch (e) {
      state = state.copyWith(error: 'Failed to delete byte: ${e.toString()}');
      return false;
    }
  }
}

// Bytes feed provider
class BytesFeedNotifier extends StateNotifier<BytesFeedState> {
  BytesFeedNotifier() : super(const BytesFeedState());

  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _pageSize = 20;

  // ── Feed loading via recommendation RPC ──────────────────────────────────

  Future<void> loadBytes() async {
    if (state.isLoading) return;

    // Cache hit: don't refetch within 5 minutes
    if (state.lastFetchTime != null &&
        DateTime.now().difference(state.lastFetchTime!) < const Duration(minutes: 5) &&
        state.bytes.isNotEmpty) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null, clearCursor: true);

    try {
      final data = await _supabase.rpc('get_user_feed', params: {
        'p_limit':         _pageSize,
        'p_content_types': ['byte'],
      }) as Map<String, dynamic>;

      final items = _parseFeedItems(data);

      // Fallback: recommendations empty, fetch directly
      if (items.isEmpty) {
        await _loadBytesDirect();
        return;
      }

      final likedIds = await _batchCheckLikes(items);
      final bytes = items.map((i) => _feedItemToByte(i, likedIds.contains(i['contentId']))).toList();

      state = state.copyWith(
        bytes:          bytes,
        isLoading:      false,
        hasMore:        items.length == _pageSize,
        currentPage:    1,
        lastFetchTime:  DateTime.now(),
        nextCursorScore: data['nextCursorScore'] as double?,
        nextCursorId:    data['nextCursorId']    as String?,
        error: null,
      );
    } catch (e) {
      debugPrint('[BytesFeed] RPC failed, using direct fallback: $e');
      await _loadBytesDirect();
    }
  }

  Future<void> loadMoreBytes() async {
    if (state.isLoadingMore || !state.hasMore) return;
    if (state.nextCursorScore == null) return;

    state = state.copyWith(isLoadingMore: true, error: null);

    try {
      final data = await _supabase.rpc('get_user_feed', params: {
        'p_cursor_score':  state.nextCursorScore,
        'p_cursor_id':     state.nextCursorId,
        'p_limit':         _pageSize,
        'p_content_types': ['byte'],
      }) as Map<String, dynamic>;

      final items = _parseFeedItems(data);
      final likedIds = await _batchCheckLikes(items);
      final newBytes = items.map((i) => _feedItemToByte(i, likedIds.contains(i['contentId']))).toList();

      // De-duplicate
      final existingIds = state.bytes.map((b) => b.byteId).toSet();
      final deduped = newBytes.where((b) => !existingIds.contains(b.byteId)).toList();

      state = state.copyWith(
        bytes:           [...state.bytes, ...deduped],
        isLoadingMore:   false,
        hasMore:         newBytes.length == _pageSize,
        currentPage:     state.currentPage + 1,
        nextCursorScore: data['nextCursorScore'] as double?,
        nextCursorId:    data['nextCursorId']    as String?,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingMore: false,
        error: 'Failed to load more bytes: $e',
      );
    }
  }



  Future<void> refreshBytes() async {
    state = const BytesFeedState();
    await loadBytes();
  }

  // ── Direct fallback: used when pearl_content_recommendations is empty ──────
  Future<void> _loadBytesDirect() async {
    try {
      final user = _supabase.auth.currentUser;
      final response = await _supabase
          .from('bytes')
          .select('*, user_profiles!bytes_user_id_fkey(username, profile_pic)')
          .eq('is_hidden', false)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      final byteIds = (response as List).map((r) => r['byte_id'] as int).toList();
      Set<String> likedIds = {};
      if (user != null && byteIds.isNotEmpty) {
        try {
          final liked = await _supabase
              .from('byte_likes')
              .select('byte_id')
              .eq('user_id', user.id)
              .inFilter('byte_id', byteIds);
          likedIds = (liked as List).map((r) => (r['byte_id'] as int).toString()).toSet();
        } catch (_) {}
      }

      final bytes = (response).map((b) {
        final profile = b['user_profiles'];
        return Byte.fromJson({
          'byte_id':       b['byte_id'],
          'user_id':       b['user_id'],
          'byte':          b['byte'],
          'caption':       b['caption'],
          'like_count':    b['like_count'],
          'comment_count': b['comment_count'],
          'share_count':   b['share_count'],
          'created_at':    b['created_at'],
          'updated_at':    b['updated_at'],
          'username':      profile?['username'],
          'profile_pic':   profile?['profile_pic'],
          'isliked':       likedIds.contains((b['byte_id'] as int).toString()),
        });
      }).toList();

      state = state.copyWith(
        bytes:         bytes,
        isLoading:     false,
        isLoadingMore: false,
        hasMore:       bytes.length == _pageSize,
        currentPage:   1,
        lastFetchTime: DateTime.now(),
        nextCursorScore: null,
        nextCursorId:    null,
        error: null,
      );
      debugPrint('[BytesFeed] Fallback loaded \${bytes.length} bytes directly');
    } catch (e) {
      state = state.copyWith(
        isLoading:     false,
        isLoadingMore: false,
        error: 'Failed to load bytes: \$e',
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _parseFeedItems(Map<String, dynamic> data) {
    final list = data['items'] as List? ?? [];
    return list.cast<Map<String, dynamic>>()
        .where((i) => i['contentType'] == 'byte')
        .toList();
  }

  Future<Set<String>> _batchCheckLikes(List<Map<String, dynamic>> items) async {
    final user = _supabase.auth.currentUser;
    if (user == null || items.isEmpty) return {};
    try {
      final ids = items
          .map((i) => int.tryParse(i['contentId'] as String? ?? ''))
          .whereType<int>()
          .toList();
      if (ids.isEmpty) return {};
      final rows = await _supabase
          .from('byte_likes')
          .select('byte_id')
          .eq('user_id', user.id)
          .inFilter('byte_id', ids);
      return (rows as List).map((r) => (r['byte_id'] as int).toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Byte _feedItemToByte(Map<String, dynamic> item, bool isLiked) {
    // mediaUrls[0] = video URL (set in get_user_feed bytes CTE)
    final mediaUrls = (item['mediaUrls'] as List?)?.cast<String>() ?? [];
    final videoUrl = mediaUrls.isNotEmpty ? mediaUrls[0] : '';
    return Byte.fromJson({
      'byte_id':       int.tryParse(item['contentId'] as String? ?? '0') ?? 0,
      'user_id':       '',              // not needed for display
      'byte':          videoUrl,        // video URL
      'caption':       item['body'],
      'like_count':    item['likeCount']    ?? 0,
      'comment_count': item['commentCount'] ?? 0,
      'share_count':   item['shareCount']   ?? 0,
      'created_at':    item['createdAt'],
      'updated_at':    item['createdAt'],
      'username':      item['username']  ?? 'Unknown',
      'profile_pic':   item['profilePic'],
      'thumbnail_url': item['thumbnailUrl'],
      'isliked':       isLiked,
    });
  }




  Future<void> toggleLike(String byteId) async {
    if (state.likingBytes.contains(byteId)) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('❌ No authenticated user for like');
      return;
    }

    final byteIndex = state.bytes.indexWhere((byte) => byte.byteId == byteId);
    if (byteIndex == -1) {
      debugPrint('❌ Byte not found: $byteId');
      return;
    }

    final currentByte = state.bytes[byteIndex];
    final currentlyliked = currentByte.isliked ?? false;

    debugPrint('🔄 Toggling like for byte $byteId, currently liked: $currentlyliked');

    // ✅ Optimistic UI update - only isLiked, not count
    final newBytes = [...state.bytes];
    newBytes[byteIndex] = currentByte.copyWith(isliked: !currentlyliked);

    state = state.copyWith(
      bytes: newBytes,
      likingBytes: {...state.likingBytes, byteId},
    );

    try {
      final byteIdInt = int.tryParse(byteId);
      if (byteIdInt == null) {
        throw Exception('Invalid byteId: $byteId');
      }

      // ✅ Check if like already exists to avoid conflicts
      final existingLike = await _supabase
          .from('byte_likes')
          .select('byte_like_id')
          .eq('byte_id', byteIdInt)
          .eq('user_id', user.id)
          .maybeSingle()
          .catchError((e) {
        debugPrint('❌ Error checking existing like: $e');
        return null;
      });

      if (currentlyliked) {
        // Unlike: Delete the like
        if (existingLike != null) {
          await _supabase
              .from('byte_likes')
              .delete()
              .eq('byte_id', byteIdInt)
              .eq('user_id', user.id);
          debugPrint('✅ Removed like from byte $byteId');
        }
      } else {
        // Like: Add new like if not already exists
        if (existingLike == null) {
          await _supabase.from('byte_likes').insert({
            'byte_id': byteIdInt,
            'user_id': user.id,
            'liked_at': DateTime.now().toIso8601String(),
          });
          debugPrint('✅ Added like to byte $byteId');
        }
      }

      // ✅ Wait for trigger to update count
      await Future.delayed(const Duration(milliseconds: 100));

      // ✅ Force refresh the specific byte
      await _reloadSingleByte(byteId, byteIndex);

      state = state.copyWith(
        likingBytes: {...state.likingBytes}..remove(byteId),
      );

      debugPrint('✅ Like operation completed for byte $byteId');

    } catch (error, stackTrace) {
      debugPrint('❌ Error in toggleLike: $error');
      debugPrint('Stack trace: $stackTrace');

      // ✅ Revert optimistic update
      final revertedBytes = [...state.bytes];
      revertedBytes[byteIndex] = currentByte.copyWith(isliked: currentlyliked);

      state = state.copyWith(
        bytes: revertedBytes,
        likingBytes: {...state.likingBytes}..remove(byteId),
        error: 'Failed to update like: ${error.toString()}',
      );
    }
  }

  Future<void> _reloadSingleByte(String byteId, int index) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final byteIdInt = int.tryParse(byteId);
      if (byteIdInt == null) {
        debugPrint('❌ Invalid byteId in reload: $byteId');
        return;
      }

      debugPrint('🔄 Reloading byte $byteId from database...');

      final response = await _supabase
          .from('bytes')
          .select('''
            *,
            user_profiles!bytes_user_id_fkey(username, profile_pic)
          ''')
          .eq('byte_id', byteIdInt)
          .single();

      // Check like status
      final isliked = await _supabase
          .from('byte_likes')
          .select('byte_like_id')
          .eq('byte_id', byteIdInt)
          .eq('user_id', user.id)
          .maybeSingle()
          .then((result) => result != null)
          .catchError((e) {
        debugPrint('❌ Error checking like status: $e');
        return false;
      });

      final updatedByte = Byte.fromJson({
        ...response,
        'byte_id': response['byte_id'],
        'username': response['user_profiles']?['username'],
        'profile_pic': response['user_profiles']?['profile_pic'],
        'isliked': isliked,
      });

      final newBytes = [...state.bytes];
      if (index < newBytes.length) {
        newBytes[index] = updatedByte;
        state = state.copyWith(bytes: newBytes);
        debugPrint('✅ Byte $byteId reloaded successfully');
      }
    } catch (error) {
      debugPrint('❌ Error reloading byte $byteId: $error');
    }
  }

  // Load comments for a byte
  Future<List<Comment>> loadComments(String byteId) async {
    // Return cached comments immediately if available
    final cachedComments = state.commentsByByteId[byteId];
    if (cachedComments != null && cachedComments.isNotEmpty) {
      debugPrint('📦 Returning ${cachedComments.length} cached comments');
      return cachedComments;
    }

    if (state.loadingComments.contains(byteId)) {
      debugPrint('⏳ Already loading comments for $byteId');
      return state.commentsByByteId[byteId] ?? [];
    }

    // ✅ Schedule state update for next frame to avoid build-time modification
    Future.microtask(() {
      state = state.copyWith(
        loadingComments: {...state.loadingComments, byteId},
      );
    });

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        Future.microtask(() {
          state = state.copyWith(
            loadingComments: {...state.loadingComments}..remove(byteId),
          );
        });
        return [];
      }

      final byteIdInt = int.tryParse(byteId);
      if (byteIdInt == null) {
        debugPrint('Error: Invalid byteId: $byteId');
        Future.microtask(() {
          state = state.copyWith(
            loadingComments: {...state.loadingComments}..remove(byteId),
          );
        });
        return [];
      }

      debugPrint('🔄 Loading comments for byte $byteId...');

      final response = await _supabase
          .from('byte_comments')
          .select('''
          *,
          user_profiles!fk_byte_comment_user(username, profile_pic)
        ''')
          .eq('byte_id', byteIdInt)
          .isFilter('parent_comment_id', null)
          .order('created_at', ascending: false);

      debugPrint('✅ Fetched ${response.length} raw comment records');

      final List<Comment> comments = [];

      for (var commentData in response) {
        try {
          final int commentId = commentData['comment_id'] is int
              ? commentData['comment_id']
              : int.tryParse(commentData['comment_id'].toString()) ?? 0;
          final userProfile = commentData['user_profiles'];

          bool isliked = false;
          try {
            final likeResponse = await _supabase
                .from('byte_comment_likes')
                .select('byte_comment_like_id')
                .eq('comment_id', commentId)
                .eq('user_id', user.id)
                .maybeSingle();

            isliked = likeResponse != null;
          } catch (e) {
            debugPrint('Error checking comment like status: $e');
          }

          final comment = Comment.fromByteMap({
            ...commentData,
            'username': userProfile?['username'] ?? 'Unknown',
            'profile_pic': userProfile?['profile_pic'],
            'isliked': isliked,
          });

          comments.add(comment);
          debugPrint('✅ Processed comment ${comment.commentId}');
        } catch (e, stack) {
          debugPrint('❌ Error processing comment: $e\n$stack');
          continue;
        }
      }

      // ✅ Update state after build completes
      Future.microtask(() {
        final updatedComments = Map<String, List<Comment>>.from(state.commentsByByteId);
        updatedComments[byteId] = comments;

        state = state.copyWith(
          commentsByByteId: updatedComments,
          loadingComments: {...state.loadingComments}..remove(byteId),
        );
      });

      debugPrint('✅ Successfully loaded ${comments.length} comments for byte $byteId');
      return comments;
    } catch (e, stack) {
      debugPrint('❌ Error loading comments: $e\n$stack');
      Future.microtask(() {
        state = state.copyWith(
          loadingComments: {...state.loadingComments}..remove(byteId),
        );
      });
      return state.commentsByByteId[byteId] ?? [];
    }
  }


  // Load replies for a parent comment
  Future<List<Comment>> loadReplies(String byteId, String parentCommentIdStr) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      // Convert IDs to int for database query
      final byteIdInt = int.tryParse(byteId);
      final parentCommentId = int.tryParse(parentCommentIdStr);
      if (byteIdInt == null || parentCommentId == null) {
        debugPrint('Error: Invalid ID format - byteId: $byteId, parentCommentId: $parentCommentIdStr');
        return [];
      }

      final response = await _supabase
          .from('byte_comments')
          .select('''
          *,
          user_profiles!fk_byte_comment_user(username, profile_pic)
          ''')
          .eq('byte_id', byteIdInt)
          .eq('parent_comment_id', parentCommentId)
          .order('created_at', ascending: true);

      final List<Comment> replies = [];

      for (var replyData in response) {
        final int commentId = replyData['comment_id'] is int
            ? replyData['comment_id']
            : int.tryParse(replyData['comment_id'].toString()) ?? 0;
        final userProfile = replyData['user_profiles'];

        bool isliked = false;
        try {
          final likeResponse = await _supabase
              .from('byte_comment_likes')
              .select('byte_comment_like_id')
              .eq('comment_id', commentId)
              .eq('user_id', user.id)
              .maybeSingle();

          isliked = likeResponse != null;
        } catch (e) {
          debugPrint('Error checking reply like status: $e');
        }

        final reply = Comment.fromByteMap({
          ...replyData,
          'username': userProfile?['username'] ?? 'Unknown',
          'profile_pic': userProfile?['profile_pic'],
          'isliked': isliked,
        });

        replies.add(reply);
      }

      return replies;
    } catch (e) {
      debugPrint('Error loading replies: $e');
      return [];
    }
  }

  Future<int> getRepliesCount(String parentCommentIdStr) async {
    try {
      final parentCommentId = int.tryParse(parentCommentIdStr);
      if (parentCommentId == null) return 0;

      final countResponse = await _supabase
          .from('byte_comments')
          .select('comment_id')
          .eq('parent_comment_id', parentCommentId);

      return (countResponse as List).length;
    } catch (e) {
      debugPrint('Error getting replies count: $e');
      return 0;
    }
  }

  // Add a reply to a comment
  Future<bool> addReply(String byteId, String parentCommentId, String content) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      // Convert IDs to int (database expects integers)
      final byteIdInt = int.tryParse(byteId);
      final parentCommentIdInt = int.tryParse(parentCommentId);
      if (byteIdInt == null || parentCommentIdInt == null) {
        debugPrint('Error: Invalid ID format - byteId: $byteId, parentCommentId: $parentCommentId');
        return false;
      }

      if (content.trim().isEmpty) {
        debugPrint('❌ Reply content is empty');
        return false;
      }

      debugPrint('📝 Adding reply to comment $parentCommentId on byte $byteId');

      await _supabase.from('byte_comments').insert({
        'byte_id': byteIdInt,
        'user_id': user.id,
        'content': content.trim(),
        'parent_comment_id': parentCommentIdInt,
        'like_count': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // ✅ Wait for trigger to update counts
      await Future.delayed(const Duration(milliseconds: 100));

      // ✅ Refresh comments
      await loadComments(byteId);

      // ✅ Also reload the byte
      final byteIndex = state.bytes.indexWhere((b) => b.byteId == byteId);
      if (byteIndex != -1) {
        await _reloadSingleByte(byteId, byteIndex);
      }

      debugPrint('✅ Added reply to comment $parentCommentId');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error adding reply: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  // Add a new comment
  Future<bool> addComment(String byteId, String content) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        debugPrint('❌ No user authenticated');
        return false;
      }

      final byteIdInt = int.tryParse(byteId);
      if (byteIdInt == null) {
        debugPrint('❌ Invalid byteId format: $byteId');
        return false;
      }

      if (content.trim().isEmpty) {
        debugPrint('❌ Comment content is empty');
        return false;
      }

      debugPrint('💬 Adding comment to byte $byteId: ${content.trim()}');

      await _supabase.from('byte_comments').insert({
        'byte_id': byteIdInt,
        'user_id': user.id,
        'content': content.trim(),
        'like_count': 0,
        'parent_comment_id': null,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // ✅ Wait for trigger to update the byte's comment_count
      await Future.delayed(const Duration(milliseconds: 100));

      // ✅ Refresh comments list
      await loadComments(byteId);

      // ✅ Refresh byte to get updated comment_count
      final byteIndex = state.bytes.indexWhere((b) => b.byteId == byteId);
      if (byteIndex != -1) {
        await _reloadSingleByte(byteId, byteIndex);
      }

      debugPrint('✅ Comment added successfully to byte $byteId');
      return true;
    } catch (e, stackTrace) {
      debugPrint('❌ Error adding comment: $e');
      debugPrint('Stack trace: $stackTrace');
      return false;
    }
  }

  Future<void> toggleCommentLike(String commentIdStr) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        debugPrint('❌ No user for comment like');
        return;
      }

      if (state.likingComments.contains(commentIdStr)) {
        debugPrint('⏳ Already liking comment $commentIdStr');
        return;
      }

      // Add to liking set
      state = state.copyWith(
        likingComments: {...state.likingComments, commentIdStr},
      );

      final int commentId = int.tryParse(commentIdStr) ?? 0;
      if (commentId == 0) {
        debugPrint('❌ Invalid commentId: $commentIdStr');
        state = state.copyWith(
          likingComments: {...state.likingComments}..remove(commentIdStr),
        );
        return;
      }

      // Find the comment and byte
      Comment? targetComment;
      String? targetByteId;

      for (var entry in state.commentsByByteId.entries) {
        try {
          final comment = entry.value.firstWhere(
                (c) => c.commentId.toString() == commentIdStr,
            orElse: () => throw Exception('Not found'),
          );
          targetComment = comment;
          targetByteId = entry.key;
          break;
        } catch (_) {
          continue;
        }
      }

      if (targetComment == null || targetByteId == null) {
        debugPrint('❌ Comment $commentIdStr not found in cache');
        state = state.copyWith(
          likingComments: {...state.likingComments}..remove(commentIdStr),
        );
        return;
      }

      final currentlyliked = targetComment.isliked;
      debugPrint('🔄 Toggling comment like: $commentIdStr, currently liked: $currentlyliked');

      // ✅ Optimistic UI update (only isliked, not count)
      final updatedComments = state.commentsByByteId[targetByteId]!.map((comment) {
        if (comment.commentId.toString() == commentIdStr) {
          return comment.copyWith(isliked: !currentlyliked);
        }
        return comment;
      }).toList();

      state = state.copyWith(
        commentsByByteId: {
          ...state.commentsByByteId,
          targetByteId: updatedComments,
        },
      );

      // Check if like already exists
      final existingLike = await _supabase
          .from('byte_comment_likes')
          .select('byte_comment_like_id')
          .eq('comment_id', commentId)
          .eq('user_id', user.id)
          .maybeSingle()
          .catchError((e) {
        debugPrint('❌ Error checking existing like: $e');
        return null;
      });

      if (currentlyliked) {
        // Unlike
        if (existingLike != null) {
          await _supabase
              .from('byte_comment_likes')
              .delete()
              .eq('comment_id', commentId)
              .eq('user_id', user.id);
          debugPrint('✅ Removed like from comment $commentIdStr');
        }
      } else {
        // Like
        if (existingLike == null) {
          await _supabase.from('byte_comment_likes').insert({
            'comment_id': commentId,
            'user_id': user.id,
          });
          debugPrint('✅ Added like to comment $commentIdStr');
        }
      }

      // ✅ Wait for trigger to update comment like_count
      await Future.delayed(const Duration(milliseconds: 50));

      // ✅ Reload comments to get updated like counts
      await loadComments(targetByteId);

      state = state.copyWith(
        likingComments: {...state.likingComments}..remove(commentIdStr),
      );

      debugPrint('✅ Comment like toggled successfully for $commentIdStr');

    } catch (e, stackTrace) {
      debugPrint('❌ Error toggling comment like: $e');
      debugPrint('Stack trace: $stackTrace');

      // Revert optimistic update on error
      state = state.copyWith(
        likingComments: {...state.likingComments}..remove(commentIdStr),
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

final byteCreateProvider =
StateNotifierProvider<ByteCreateNotifier, ByteCreateState>((ref) {
  final pointsService = ref.read(plaroPointsServiceProvider);
  return ByteCreateNotifier(pointsService, ref);
});

final bytesFeedProvider = StateNotifierProvider<BytesFeedNotifier, BytesFeedState>(
      (ref) => BytesFeedNotifier(),
);