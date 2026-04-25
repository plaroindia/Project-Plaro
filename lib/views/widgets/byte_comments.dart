import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../Viewmodels/byte_provider.dart';
import 'unified_comments_bottom_sheet.dart';

// ByteCommentsBottomSheet - Now uses unified bottom sheet
class ByteCommentsBottomSheet extends ConsumerWidget {
  final String byteId;

  const ByteCommentsBottomSheet({super.key, required this.byteId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytesState = ref.read(bytesFeedProvider);
    
    return UnifiedCommentsBottomSheet(
      contentId: byteId,
      title: 'Comments',
      commentCount: null, // Will be shown from loaded comments
      likingComments: bytesState.likingComments,
      callbacks: CommentSheetCallbacks(
        loadComments: () => ref.read(bytesFeedProvider.notifier).loadComments(byteId),
        loadReplies: (parentCommentId) => ref.read(bytesFeedProvider.notifier).loadReplies(byteId, parentCommentId),
        getRepliesCount: (parentCommentId) => ref.read(bytesFeedProvider.notifier).getRepliesCount(parentCommentId),
        addComment: (content) => ref.read(bytesFeedProvider.notifier).addComment(byteId, content),
        addReply: (parentCommentId, content) => ref.read(bytesFeedProvider.notifier).addReply(byteId, parentCommentId, content),
        toggleCommentLike: (commentId) => ref.read(bytesFeedProvider.notifier).toggleCommentLike(commentId),
        getCurrentUserId: () => Supabase.instance.client.auth.currentUser?.id,
        getUserProfile: () async {
          final user = Supabase.instance.client.auth.currentUser;
          if (user == null) return null;
          try {
            final response = await Supabase.instance.client
                .from('user_profiles')
                .select('profile_pic')
                .eq('user_id', user.id)
                .maybeSingle();
            return response;
          } catch (e) {
            debugPrint('Error fetching user profile: $e');
            return null;
          }
        },
      ),
    );
  }
}
