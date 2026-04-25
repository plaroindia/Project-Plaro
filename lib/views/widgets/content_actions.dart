// Shared content action system for Posts, Toasts, and Bytes
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Content types supported by the action menu
enum ContentType {
  post,
  toast,
  byte,
}

/// Available actions for content items
enum ContentAction {
  edit,
  delete,
  hide,
  unhide,
  share,
}

/// Metadata for content action menu
class ContentActionData {
  final String contentId;
  final String userId;
  final ContentType contentType;
  final bool isHidden;
  final String? shareText;
  final String? shareUrl;

  const ContentActionData({
    required this.contentId,
    required this.userId,
    required this.contentType,
    this.isHidden = false,
    this.shareText,
    this.shareUrl,
  });
}

/// Callbacks for content actions
class ContentActionCallbacks {
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onToggleHide;
  final VoidCallback? onShare;

  const ContentActionCallbacks({
    this.onEdit,
    this.onDelete,
    this.onToggleHide,
    this.onShare,
  });
}

/// Reusable action menu widget for content items
class ContentActionMenu extends StatelessWidget {
  final ContentActionData data;
  final ContentActionCallbacks callbacks;
  final String currentUserId;

  const ContentActionMenu({
    super.key,
    required this.data,
    required this.callbacks,
    required this.currentUserId,
  });

  bool get _isOwner => currentUserId == data.userId;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.more_vert, color: Theme.of(context).iconTheme.color),
      onPressed: () => _showActionSheet(context),
    );
  }

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardTheme.color,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Owner-only actions
            if (_isOwner) ...[
              _buildActionTile(
                context,
                icon: Icons.edit_outlined,
                title: 'Edit $_contentTypeName',
                color: Colors.blue,
                onTap: () {
                  Navigator.pop(context);
                  callbacks.onEdit?.call();
                },
              ),
              _buildActionTile(
                context,
                icon: data.isHidden ? Icons.visibility : Icons.visibility_off,
                title: data.isHidden ? 'Unhide $_contentTypeName' : 'Hide $_contentTypeName',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(context);
                  callbacks.onToggleHide?.call();
                },
              ),
              _buildActionTile(
                context,
                icon: Icons.delete_outline,
                title: 'Delete $_contentTypeName',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context);
                },
              ),
            ],

            // Share - available to all
            _buildActionTile(
              context,
              icon: Icons.share_outlined,
              title: 'Share',
              color: Colors.blue,
              onTap: () {
                Navigator.pop(context);
                _handleShare(context);
              },
            ),

            // Report/Block for non-owners
            if (!_isOwner) ...[
              _buildActionTile(
                context,
                icon: Icons.report_outlined,
                title: 'Report $_contentTypeName',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(context);
                  _showReportDialog(context);
                },
              ),
              _buildActionTile(
                context,
                icon: Icons.block_outlined,
                title: 'Block User',
                color: Colors.orange,
                onTap: () {
                  Navigator.pop(context);
                  _showBlockDialog(context);
                },
              ),
            ],

            SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
      onTap: onTap,
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color,
        title: Text('Delete $_contentTypeName', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Are you sure you want to delete this ${_contentTypeName.toLowerCase()}? This action cannot be undone.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              callbacks.onDelete?.call();
            },
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleShare(BuildContext context) {
    if (callbacks.onShare != null) {
      callbacks.onShare!();
    } else {
      // Default share behavior - copy link
      final shareUrl = data.shareUrl ?? 'https://yourapp.com/${data.contentType.name}/${data.contentId}';
      Clipboard.setData(ClipboardData(text: shareUrl));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copied to clipboard'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showReportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color,
        title: Text('Report Content', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'Thank you for helping keep our community safe. We will review this content.',
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
                  content: Text('Content reported'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: Text('Report', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color,
        title: Text('Block User', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
          'You will no longer see content from this user.',
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
                  content: Text('User blocked'),
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

  String get _contentTypeName {
    switch (data.contentType) {
      case ContentType.post:
        return 'Post';
      case ContentType.toast:
        return 'Toast';
      case ContentType.byte:
        return 'Byte';
    }
  }
}