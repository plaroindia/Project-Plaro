import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'streakandpoints_provider.dart';
import 'notifications_provider.dart';
import '../service/moderation_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class PostCreateState {
  final bool isLoading;
  final String? error;
  final String? successMessage;
  final List<XFile> selectedMedia;
  final String content;
  final String title;
  final String caption;
  final List<String> tags;
  final String? domain;
  final bool isModerating;
  final String? moderationStatus;

  // ── Freelance fields ──────────────────────────────────────────────────────
  final bool isFreelance;
  final String? freelanceBudget;
  final DateTime? freelanceDeadline;
  final String freelanceMinRank;   // beginner | intermediate | advanced | expert | master
  final bool requiresPro;

  PostCreateState({
    this.isLoading = false,
    this.error,
    this.successMessage,
    this.selectedMedia = const [],
    this.content = '',
    this.title = '',
    this.caption = '',
    this.tags = const [],
    this.domain,
    this.isModerating = false,
    this.moderationStatus,
    // Freelance defaults
    this.isFreelance      = false,
    this.freelanceBudget,
    this.freelanceDeadline,
    this.freelanceMinRank = 'beginner',
    this.requiresPro      = false,
  });

  PostCreateState copyWith({
    bool? isLoading,
    String? error,
    String? successMessage,
    List<XFile>? selectedMedia,
    String? content,
    String? title,
    String? caption,
    List<String>? tags,
    String? domain,
    bool? isModerating,
    String? moderationStatus,
    bool? isFreelance,
    String? freelanceBudget,
    DateTime? freelanceDeadline,
    String? freelanceMinRank,
    bool? requiresPro,
    bool clearFreelanceDeadline = false,
  }) {
    return PostCreateState(
      isLoading:         isLoading         ?? this.isLoading,
      error:             error,
      successMessage:    successMessage,
      selectedMedia:     selectedMedia     ?? this.selectedMedia,
      content:           content           ?? this.content,
      title:             title             ?? this.title,
      caption:           caption           ?? this.caption,
      tags:              tags              ?? this.tags,
      domain:            domain            ?? this.domain,
      isModerating:      isModerating      ?? this.isModerating,
      moderationStatus:  moderationStatus  ?? this.moderationStatus,
      isFreelance:       isFreelance       ?? this.isFreelance,
      freelanceBudget:   freelanceBudget   ?? this.freelanceBudget,
      freelanceDeadline: clearFreelanceDeadline
          ? null
          : (freelanceDeadline ?? this.freelanceDeadline),
      freelanceMinRank:  freelanceMinRank  ?? this.freelanceMinRank,
      requiresPro:       requiresPro       ?? this.requiresPro,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class PostCreateNotifier extends StateNotifier<PostCreateState> {
  PostCreateNotifier(this._pointsService, this._ref) : super(PostCreateState()) {
    _initModeration();
  }

  final SupabaseClient     _supabase     = Supabase.instance.client;
  final ImagePicker        _imagePicker  = ImagePicker();
  final PlaroPointsService _pointsService;
  final Ref                _ref;

  Future<void> _initModeration() async {
    try {
      await _ref.read(moderationServiceProvider).init();
    } catch (e) {
      debugPrint('[Moderation] Failed to preload models: $e');
    }
  }

  // ── Media picking ─────────────────────────────────────────────────────────

  Future<void> pickMedia({bool fromCamera = false}) async {
    try {
      final List<XFile> pickedFiles = [];
      if (fromCamera) {
        final photo = await _imagePicker.pickImage(
          source: ImageSource.camera, imageQuality: 80,
        );
        if (photo != null) pickedFiles.add(photo);
      } else {
        final photos = await _imagePicker.pickMultiImage(imageQuality: 80);
        pickedFiles.addAll(photos);
      }
      if (pickedFiles.isNotEmpty) {
        state = state.copyWith(
          selectedMedia: [...state.selectedMedia, ...pickedFiles],
        );
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick media: $e');
    }
  }

  Future<void> pickVideo({bool fromCamera = false}) async {
    try {
      final video = await _imagePicker.pickVideo(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxDuration: const Duration(minutes: 1),
      );
      if (video != null) {
        state = state.copyWith(selectedMedia: [...state.selectedMedia, video]);
      }
    } catch (e) {
      state = state.copyWith(error: 'Failed to pick video: $e');
    }
  }

  void removeMedia(int index) {
    final updated = List<XFile>.from(state.selectedMedia)..removeAt(index);
    state = state.copyWith(selectedMedia: updated);
  }

  void updateContent(String v) => state = state.copyWith(content: v);
  void updateTitle(String v)   => state = state.copyWith(title: v);
  void updateCaption(String v) => state = state.copyWith(caption: v);
  void updateTags(List<String> v) => state = state.copyWith(tags: v);
  void updateDomain(String v)  => state = state.copyWith(domain: v);

  // ── Freelance field setters ───────────────────────────────────────────────

  void toggleFreelance(bool v) => state = state.copyWith(isFreelance: v);
  void updateFreelanceBudget(String? v) =>
      state = state.copyWith(freelanceBudget: v);
  void updateFreelanceDeadline(DateTime? v) => v == null
      ? state = state.copyWith(clearFreelanceDeadline: true)
      : state = state.copyWith(freelanceDeadline: v);
  void updateFreelanceMinRank(String v) =>
      state = state.copyWith(freelanceMinRank: v);
  void toggleRequiresPro(bool v) => state = state.copyWith(requiresPro: v);

  // ── Image upload + per-image NSFW check ──────────────────────────────────

  Future<String?> _uploadFile(XFile file) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) throw Exception('User not authenticated');

    final ext     = file.path.split('.').last.toLowerCase();
    final isImage = const {'jpg','jpeg','png','gif','webp','heic'}.contains(ext);

    if (isImage) {
      try {
        final moderation = _ref.read(moderationServiceProvider);
        final result     = await moderation.moderateImage(file.path);

        debugPrint(
          '[Moderation] Image: nsfw=${result.nsfwScore.toStringAsFixed(3)} '
              'verdict=${result.verdict.name}',
        );

        if (result.isBlocked) {
          state = state.copyWith(
            error: result.reason ?? 'One of your images was flagged as inappropriate.',
          );
          return null;
        }
      } catch (e) {
        debugPrint('[Moderation] Image check error (non-fatal): $e');
      }
    }

    final bytes    = await file.readAsBytes();
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${currentUserId.substring(0, 8)}.$ext';
    final filePath = '$currentUserId/$fileName';

    await _supabase.storage.from('post-media').uploadBinary(
      filePath, bytes,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
    );

    return _supabase.storage.from('post-media').getPublicUrl(filePath);
  }

  // ── Heuristic educational value ───────────────────────────────────────────

  double _estimateEducationalValue({
    required String content,
    required String title,
    required List<String> tags,
    required int mediaCount,
  }) {
    final wordCount = content.trim().split(RegExp(r'\s+')).length;
    double score = 0.3;
    if (wordCount >= 200)      score += 0.20;
    else if (wordCount >= 100) score += 0.15;
    else if (wordCount >= 50)  score += 0.10;
    else if (wordCount >= 20)  score += 0.05;
    if (title.trim().length >= 10) score += 0.10;
    if (tags.length >= 2)      score += 0.10;
    else if (tags.isNotEmpty)  score += 0.05;
    if (mediaCount >= 1)       score += 0.05;
    return score.clamp(0.0, 1.0);
  }

  // ── Create post ───────────────────────────────────────────────────────────

  Future<bool> createPost() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    debugPrint('[PostProvider] currentUser=$currentUserId');
    debugPrint('[PostProvider] streakNotifier userId=${_ref.read(streakProvider.notifier).debugUserId}');

    if (currentUserId == null) {
      state = state.copyWith(error: 'User not authenticated');
      return false;
    }

    if (state.domain == null || state.domain!.isEmpty) {
      state = state.copyWith(error: 'Please select a domain');
      return false;
    }

    if (state.tags.isEmpty) {
      state = state.copyWith(
        error: 'Please add at least one tag to help categorise your content',
      );
      return false;
    }

    if (state.content.isEmpty && state.selectedMedia.isEmpty) {
      state = state.copyWith(error: 'Please add some content or media');
      return false;
    }

    if (state.content.isNotEmpty) {
      final wordCount = state.content.trim().split(RegExp(r'\s+')).length;
      if (wordCount < 5) {
        state = state.copyWith(
          error: 'Please add a bit more content — at least a few sentences.',
        );
        return false;
      }
    }

    // ── Freelance validation ──────────────────────────────────────────────
    if (state.isFreelance) {
      if (state.title.trim().isEmpty) {
        state = state.copyWith(error: 'Freelance posts require a title.');
        return false;
      }
    }

    state = state.copyWith(isLoading: true, error: null);

    // ── Step 1: Text moderation ───────────────────────────────────────────
    if (state.content.isNotEmpty || state.title.isNotEmpty || state.tags.isNotEmpty) {
      state = state.copyWith(
        isModerating: true, moderationStatus: 'Checking content…',
      );

      try {
        final moderation = _ref.read(moderationServiceProvider);
        final textResult = await moderation.moderatePost(
          title:   state.title,
          content: state.content,
          tags:    state.tags,
        );

        debugPrint(
          '[Moderation] Text: nsfw=${textResult.nsfwScore.toStringAsFixed(3)} '
              'verdict=${textResult.verdict.name} '
              'wordlist=${textResult.fromWordlist}',
        );

        if (textResult.isBlocked) {
          state = state.copyWith(
            isLoading:    false,
            isModerating: false,
            moderationStatus: null,
            error: textResult.reason ?? 'Your post contains inappropriate content.',
          );
          return false;
        }
      } catch (e) {
        debugPrint('[Moderation] Text check error (non-fatal): $e');
      }

      state = state.copyWith(isModerating: false, moderationStatus: null);
    }

    // ── Step 2: Media upload ──────────────────────────────────────────────
    state = state.copyWith(
      isModerating: true, moderationStatus: 'Checking media…',
    );

    final List<String> mediaUrls = [];
    for (int i = 0; i < state.selectedMedia.length; i++) {
      try {
        final url = await _uploadFile(state.selectedMedia[i]);
        if (url == null) {
          state = state.copyWith(
            isLoading: false, isModerating: false, moderationStatus: null,
          );
          return false;
        }
        mediaUrls.add(url);
      } catch (uploadError) {
        debugPrint('Failed to upload file ${i + 1}: $uploadError');
        state = state.copyWith(
          isLoading: false, isModerating: false,
          error: 'Failed to upload media. Please try again.',
        );
        return false;
      }
    }

    state = state.copyWith(isModerating: false, moderationStatus: null);

    // ── Step 3: Educational value heuristic ──────────────────────────────
    final educationalValue = _estimateEducationalValue(
      content:    state.content,
      title:      state.title,
      tags:       state.tags,
      mediaCount: mediaUrls.length,
    );

    // ── Step 4: DB insert ─────────────────────────────────────────────────
    final postData = <String, dynamic>{
      'user_id':           currentUserId,
      'title':             state.title.isEmpty   ? null : state.title,
      'content':           state.content.isEmpty ? null : state.content,
      'tags':              state.tags,
      'domain':            state.domain,
      'is_published':      true,
      'is_hidden':         false,
      'media_urls':        mediaUrls.isEmpty ? null : mediaUrls,
      'educational_value': educationalValue,
      'created_at':        DateTime.now().toIso8601String(),
      // ── Freelance columns (always written; default false/null is safe) ──
      'is_freelance':       state.isFreelance,
      if (state.isFreelance) ...{
        if (state.freelanceBudget != null && state.freelanceBudget!.isNotEmpty)
          'freelance_budget': state.freelanceBudget,
        if (state.freelanceDeadline != null)
          'freelance_deadline': state.freelanceDeadline!.toIso8601String(),
        'freelance_min_rank': state.freelanceMinRank,
        'requires_pro':       state.requiresPro,
      },
    };

    late final int postId;
    try {
      final response = await _supabase
          .from('post')
          .insert(postData)
          .select('post_id')
          .single();
      postId = response['post_id'] as int;
    } catch (e) {
      debugPrint('DB insert error: $e');
      String msg = 'Failed to create post';
      if (e.toString().contains('StorageException')) {
        msg = 'Failed to upload media. Please check your permissions.';
      } else if (e.toString().contains('row-level security')) {
        msg = 'Permission denied. Please contact support.';
      }
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }

    // ── Step 5: Background score patch ───────────────────────────────────
    _patchModerationScores(
      postId: postId, educationalValue: educationalValue, domain: state.domain!,
    );

    // ── Step 6: Award points ──────────────────────────────────────────────
    try {
      await _pointsService.awardPointsForContent(
        userId: currentUserId, contentType: 'post', contentId: postId,
      );
    } catch (e) {
      debugPrint('Failed to award points: $e');
    }

    final capturedDomain = state.domain;

    // ── Step 7: Log streak ────────────────────────────────────────────────
    _ref.read(streakProvider.notifier).logPostCreated(
      postId: postId, domain: capturedDomain,
    );

    // ── Step 8: Freelance post-creation notification (self-notify) ────────
    // Notifies the poster that their freelance post is live.
    // Bulk-notifying followers is deferred to a future server-side job.
    if (state.isFreelance) {
      NotificationsNotifier.insert(
        targetUserId: currentUserId,
        type:         'freelance',
        title:        'Your freelance post is live 💼',
        body:         'Eligible users can now see and apply to your post',
        relatedType:  'post',
        relatedId:    postId.toString(),
      );
    }

    // ── Reset ─────────────────────────────────────────────────────────────
    state = state.copyWith(
      isLoading: false, successMessage: 'Post created successfully!',
      selectedMedia: [], content: '', title: '', caption: '',
      tags: [], domain: null, isModerating: false, moderationStatus: null,
      isFreelance: false, freelanceBudget: null,
      clearFreelanceDeadline: true,
      freelanceMinRank: 'beginner', requiresPro: false,
    );

    return true;
  }

  // ── Background score patch ────────────────────────────────────────────────

  Future<void> _patchModerationScores({
    required int postId,
    required double educationalValue,
    required String domain,
  }) async {
    try {
      final combined = '${state.title} ${state.content}'.trim();
      if (combined.isEmpty) return;

      final moderation = _ref.read(moderationServiceProvider);
      final textResult = await moderation.moderatePost(
        title: state.title, content: state.content, tags: [],
      );

      if (textResult.nsfwScore < 0.10) return;

      await _supabase.from('content_rank_scores').update({
        'toxicity_score': textResult.nsfwScore,
        'academic_score': educationalValue * (1.0 - (textResult.nsfwScore * 0.5)),
        'last_computed':  DateTime.now().toIso8601String(),
      })
          .eq('content_type', 'post')
          .eq('content_id_int', postId);
    } catch (e) {
      debugPrint('[Moderation] Background score patch failed (non-fatal): $e');
    }
  }

  void clearError()   => state = state.copyWith(error: null);
  void clearSuccess() => state = state.copyWith(successMessage: null);
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final postCreateProvider =
StateNotifierProvider<PostCreateNotifier, PostCreateState>((ref) {
  final pointsService = ref.read(plaroPointsServiceProvider);
  return PostCreateNotifier(pointsService, ref);
});