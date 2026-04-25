import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/comment.dart';

class CommentCard extends ConsumerWidget {
  final Comment comment;
  final VoidCallback onLike;
  final VoidCallback? onReply;

  const CommentCard({
    super.key,
    required this.comment,
    required this.onLike,
    this.onReply,
  });



  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: NetworkImage(comment.profileImage),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            comment.username,
            style: TextStyle(color: Colors.blue, fontSize: 12),
          ),
          Text(
            comment.timeAgo,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            comment.content,
            style: TextStyle(color: Colors.grey.shade300),
          ),
          SizedBox(height: 5),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  comment.isliked ? Icons.favorite : Icons.favorite_border,
                  size: 16,
                  color: Colors.blue,
                ),
                onPressed: onLike,
              ),
              Text(
                '${comment.likes}',
                style: TextStyle(color: Colors.white54),
              ),
              SizedBox(width: 10),
              IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.reply, size: 16, color: Colors.blue),
                onPressed: onReply,
              ),
              Text('Reply', style: TextStyle(color: Colors.white54)),
            ],
          ),
        ],
      ),
      onTap: () {
        // Optional interaction handler
      },
    );
  }
}