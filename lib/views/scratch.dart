// chat_page.dart — v2.0 — Enhanced UI with full-screen image viewer & media download
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'profile.dart';
import '../models/user_profile.dart';
import '../../Viewmodels/dm_provider.dart';
import '../Viewmodels/user_provider.dart';
import '../Viewmodels/chat_media_provider.dart';
import '../views/widgets/full_screen_image_viewer.dart';

// ─────────────────────────────────────────────────────────────
// CONSTANTS
// ─────────────────────────────────────────────────────────────
class _C {
  // Dark base palette
  static const bg = Color(0xFF0A0A0F);
  static const surface = Color(0xFF13131A);
  static const surfaceAlt = Color(0xFF1C1C26);
  static const border = Color(0xFF2A2A38);

  // Bubble colours
  static const myBubble = Color(0xFF2563EB); // blue-600
  static const myBubbleTop = Color(0xFF3B82F6); // blue-500
  static const theirBubble = Color(0xFF1E1E2E);
  static const theirBubbleTop = Color(0xFF252535);

  // Text
  static const textPrimary = Color(0xFFF1F1F5);
  static const textSecondary = Color(0xFF8888A8);
  static const textMuted = Color(0xFF55556A);

  // Accents
  static const accent = Color(0xFF3B82F6);
  static const accentGlow = Color(0x332563EB);
  static const online = Color(0xFF22C55E);
  static const editBanner = Color(0xFFD97706);

  static const inputBg = Color(0xFF1A1A28);
  static const inputBorder = Color(0xFF2E2E42);
}

// ─────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────
class IndividualChatPage extends ConsumerStatefulWidget {
  final UserProfile? receiver;
  final String receiverId;
  final String receiverName;
  final String? receiverProfilePic;

  const IndividualChatPage({
    super.key,
    required this.receiver,
    required this.receiverId,
    required this.receiverName,
    this.receiverProfilePic,
  });

  @override
  ConsumerState<IndividualChatPage> createState() => _IndividualChatPageState();
}

class _IndividualChatPageState extends ConsumerState<IndividualChatPage>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  bool _isTyping = false;
  late AnimationController _fadeController;
  late AnimationController _sendBtnController;
  String? _currentUserId;
  String? _editingMessageId;
  bool _isSendingMedia = false;

  bool _isUserScrolling = false;
  bool _shouldAutoScroll = true;
  int _lastMessageCount = 0;
  bool _keyboardVisible = false;

  // Download tracking
  final Map<String, double> _downloadProgress = {};
  final Map<String, bool> _downloading = {};

  @override
  void initState() {
    super.initState();
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..forward();

    _sendBtnController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _messageController.addListener(_onMessageChanged);
    _scrollController.addListener(_onScroll);
    _messageFocusNode.addListener(_onFocusChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom(animated: false);
    });
  }

  @override
  void dispose() {
    _messageController.removeListener(_onMessageChanged);
    _scrollController.removeListener(_onScroll);
    _messageFocusNode.removeListener(_onFocusChanged);
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _fadeController.dispose();
    _sendBtnController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_messageFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _scrollToBottomForced();
      });
      setState(() => _keyboardVisible = true);
    } else {
      setState(() => _keyboardVisible = false);
    }
  }

  void _onMessageChanged() {
    final hasText = _messageController.text.trim().isNotEmpty;
    if (hasText != _isTyping) {
      setState(() => _isTyping = hasText);
      if (hasText) {
        _sendBtnController.forward();
      } else {
        _sendBtnController.reverse();
      }
      if (_currentUserId != null) {
        final params = createChatParams(
          currentUserId: _currentUserId!,
          receiverId: widget.receiverId,
        );
        Future.microtask(() {
          if (mounted) {
            ref.read(directMessageProvider(params).notifier).setTyping(hasText);
          }
        });
      }
    }
  }

  void _onScroll() {
    _isUserScrolling = true;
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      _shouldAutoScroll = pos.pixels >= pos.maxScrollExtent - 120;

      if (pos.pixels <= 200 && _currentUserId != null) {
        final params = createChatParams(
          currentUserId: _currentUserId!,
          receiverId: widget.receiverId,
        );
        Future.microtask(() {
          if (mounted) {
            ref.read(directMessageProvider(params).notifier).loadMoreMessages();
          }
        });
      }
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _isUserScrolling = false;
    });
  }

  void _scrollToBottom({bool animated = true}) {
    if (_scrollController.hasClients && _shouldAutoScroll && !_isUserScrolling) {
      if (animated) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    }
  }

  void _scrollToBottomForced() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _currentUserId == null) return;

    final params = createChatParams(
      currentUserId: _currentUserId!,
      receiverId: widget.receiverId,
    );

    try {
      if (_editingMessageId != null) {
        await ref
            .read(directMessageProvider(params).notifier)
            .editMessage(_editingMessageId!, message);
        _cancelEdit();
      } else {
        _messageController.clear();
        setState(() => _isTyping = false);
        _sendBtnController.reverse();
        _shouldAutoScroll = true;
        _scrollToBottomForced();
        await ref
            .read(directMessageProvider(params).notifier)
            .sendMessage(content: message);
      }
    } catch (error) {
      if (_editingMessageId == null) {
        _messageController.text = message;
        setState(() => _isTyping = true);
        _sendBtnController.forward();
      }
      _showErrorSnackBar('Failed to send message: $error');
    }
  }

  Future<void> _sendMediaMessage(ChatMediaItem mediaItem) async {
    if (_currentUserId == null) return;

    final params = createChatParams(
      currentUserId: _currentUserId!,
      receiverId: widget.receiverId,
    );

    try {
      final mediaContent = mediaItem.isImage
          ? '📷 Image: ${mediaItem.fileName}'
          : '📄 File: ${mediaItem.fileName}';

      _shouldAutoScroll = true;

      await ref.read(directMessageProvider(params).notifier).sendMessage(
        content: mediaContent,
        messageType: mediaItem.isImage ? 'image' : 'file',
        metadata: {
          'media_id': mediaItem.id,
          'file_url': mediaItem.fileUrl,
          'file_name': mediaItem.fileName,
          'file_size': mediaItem.fileSize,
          'mime_type': mediaItem.mimeType,
          'media_type': mediaItem.mediaType.value,
        },
      );

      _scrollToBottomForced();
    } catch (error) {
      _showErrorSnackBar('Failed to send media: $error');
    }
  }

  void _startEdit(DirectMessage message) {
    setState(() {
      _editingMessageId = message.id;
      _messageController.text = message.content;
      _isTyping = true;
    });
    _sendBtnController.forward();
    _messageFocusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editingMessageId = null;
      _isTyping = false;
    });
    _messageController.clear();
    _sendBtnController.reverse();
  }

  void _deleteMessage(String messageId) {
    if (_currentUserId != null) {
      final params = createChatParams(
        currentUserId: _currentUserId!,
        receiverId: widget.receiverId,
      );
      Future.microtask(() {
        ref.read(directMessageProvider(params).notifier).deleteMessage(messageId);
      });
    }
  }

  // ─── Download file ───────────────────────────────────────────
  Future<void> _downloadAndOpenFile(String fileUrl, String fileName) async {
    if (_downloading[fileUrl] == true) return;

    setState(() {
      _downloading[fileUrl] = true;
      _downloadProgress[fileUrl] = 0.0;
    });

    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';
      final file = File(filePath);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(fileUrl));
      final response = await client.send(request);
      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() {
            _downloadProgress[fileUrl] = receivedBytes / totalBytes;
          });
        }
      }
      await sink.close();
      client.close();

      if (mounted) {
        setState(() {
          _downloading[fileUrl] = false;
          _downloadProgress.remove(fileUrl);
        });
        await OpenFilex.open(filePath);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading[fileUrl] = false;
          _downloadProgress.remove(fileUrl);
        });
        _showErrorSnackBar('Download failed: $e');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          ],
        ),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null) {
      return Scaffold(
        backgroundColor: _C.bg,
        body: Center(
          child: Text('Please log in to use chat',
              style: TextStyle(color: _C.textSecondary)),
        ),
      );
    }

    final params = createChatParams(
      currentUserId: _currentUserId!,
      receiverId: widget.receiverId,
    );

    final mediaParams = createMediaParams(
      chatId: DirectMessageNotifier.generateChatId(_currentUserId!, widget.receiverId),
      currentUserId: _currentUserId!,
    );

    return Scaffold(
      backgroundColor: _C.bg,
      extendBodyBehindAppBar: false,
      appBar: _buildAppBar(),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Subtle dot-grid background texture
          Positioned.fill(
            child: CustomPaint(painter: _DotGridPainter()),
          ),

          Column(
            children: [
              Expanded(
                child: FadeTransition(
                  opacity: _fadeController,
                  child: Consumer(
                    builder: (context, ref, child) {
                      final chatState = ref.watch(directMessageProvider(params));
                      final mediaState = ref.watch(chatMediaProvider(mediaParams));

                      if (mediaState.hasError) {
                        Future.microtask(() {
                          if (mounted) {
                            _showErrorSnackBar(mediaState.error!);
                            ref
                                .read(chatMediaProvider(mediaParams).notifier)
                                .clearError();
                          }
                        });
                      }

                      if (chatState.hasError) {
                        Future.microtask(() {
                          if (mounted) {
                            _showErrorSnackBar(chatState.error!);
                            ref
                                .read(directMessageProvider(params).notifier)
                                .clearError();
                          }
                        });
                      }

                      return _buildMessagesList(chatState);
                    },
                  ),
                ),
              ),
              _buildMessageInput(mediaParams),
            ],
          ),

          // Upload progress pill
          if (_isSendingMedia)
            Positioned(
              bottom: 84,
              left: 0,
              right: 0,
              child: Center(
                child: Consumer(
                  builder: (context, ref, _) {
                    final mediaState = ref.watch(chatMediaProvider(mediaParams));
                    return _UploadProgressPill(
                      progress: mediaState.uploadProgress,
                      isUploading: mediaState.isUploading,
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(64),
      child: Container(
        decoration: BoxDecoration(
          color: _C.surface,
          border: Border(
            bottom: BorderSide(color: _C.border, width: 0.5),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                // Back button
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _C.textPrimary, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),

                // Avatar + name
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => OtherProfileScreen(
                          userId: widget.receiverId,
                          initialUserData: widget.receiver,
                        ),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Row(
                        children: [
                          // Avatar with online ring
                          Stack(
                            children: [
                              Hero(
                                tag: 'profile_${widget.receiverId}',
                                child: _Avatar(
                                  url: widget.receiverProfilePic,
                                  size: 42,
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: _C.online,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: _C.surface, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.receiverName,
                                style: const TextStyle(
                                  color: _C.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: _C.online,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  const Text(
                                    'Online',
                                    style: TextStyle(
                                      color: _C.online,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded,
                      color: _C.textSecondary),
                  color: _C.surfaceAlt,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: _C.border),
                  ),
                  offset: const Offset(0, 48),
                  onSelected: _handleMenuSelection,
                  itemBuilder: (context) => [
                    _popItem('clear', Icons.delete_sweep_rounded,
                        'Clear chat', _C.textPrimary),
                    _popItem('mute', Icons.notifications_off_rounded,
                        'Mute notifications', _C.textPrimary),
                    _popItem(
                        'block', Icons.block_rounded, 'Block user', Colors.red),
                    _popItem('report', Icons.flag_rounded, 'Report',
                        Colors.orange),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _popItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ─── Messages list ───────────────────────────────────────────
  Widget _buildMessagesList(ChatState chatState) {
    if (chatState.hasError && chatState.messages.isEmpty) {
      return _buildErrorWidget(chatState.error!);
    }

    if (chatState.messages.isEmpty && chatState.isInitialLoading) {
      return _buildLoadingWidget();
    }

    if (chatState.messages.isEmpty && !chatState.isInitialLoading) {
      return _buildEmptyWidget();
    }

    final currentCount = chatState.messages.length;
    if (currentCount > _lastMessageCount) {
      if (_shouldAutoScroll || !_isUserScrolling) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottomForced();
        });
      }
    }
    _lastMessageCount = currentCount;

    return RefreshIndicator(
      onRefresh: () async {
        if (_currentUserId != null) {
          final params = createChatParams(
            currentUserId: _currentUserId!,
            receiverId: widget.receiverId,
          );
          ref.read(directMessageProvider(params).notifier).refresh();
        }
      },
      backgroundColor: _C.surfaceAlt,
      color: _C.accent,
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 16,
          bottom: _keyboardVisible ? 12 : 88,
        ),
        itemCount: chatState.messages.length,
        itemBuilder: (context, index) {
          final message = chatState.messages[index];
          final isFromMe = message.senderId == _currentUserId;
          final prev =
          index > 0 ? chatState.messages[index - 1] : null;
          final next = index < chatState.messages.length - 1
              ? chatState.messages[index + 1]
              : null;

          final isGroupStart = prev?.senderId != message.senderId;
          final isGroupEnd = next?.senderId != message.senderId;

          final showTimestamp = prev == null ||
              message.createdAt.difference(prev.createdAt).inMinutes > 30;

          return Column(
            children: [
              if (showTimestamp) _buildTimestampDivider(message.createdAt),
              _ChatBubble(
                message: message,
                isFromMe: isFromMe,
                isGroupStart: isGroupStart,
                isGroupEnd: isGroupEnd,
                receiverPic: widget.receiverProfilePic,
                currentUserId: _currentUserId,
                onLongPress: () => _showMessageOptions(message, isFromMe),
                onImageTap: (url) => FullScreenImageViewer.show(
                  context,
                  imageUrls: [url],
                ),
                onDownload: _downloadAndOpenFile,
                downloadProgress: _downloadProgress,
                isDownloading: _downloading,
              ),
            ],
          );
        },
      ),
    );
  }

  // ─── Input bar ───────────────────────────────────────────────
  Widget _buildMessageInput(ChatMediaParams mediaParams) {
    return Container(
      decoration: BoxDecoration(
        color: _C.surface,
        border: Border(top: BorderSide(color: _C.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Edit banner
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _editingMessageId != null
                    ? _EditBanner(onCancel: _cancelEdit)
                    : const SizedBox.shrink(),
              ),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attach button
                  _AttachButton(
                    busy: _isSendingMedia,
                    onTap: () => _showAttachmentOptions(mediaParams),
                  ),
                  const SizedBox(width: 8),

                  // Text field
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 130),
                      decoration: BoxDecoration(
                        color: _C.inputBg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _C.inputBorder, width: 1),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        style: const TextStyle(
                          color: _C.textPrimary,
                          fontSize: 15,
                          height: 1.4,
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: _editingMessageId != null
                              ? 'Edit message…'
                              : 'Message ${widget.receiverName}…',
                          hintStyle: const TextStyle(
                            color: _C.textMuted,
                            fontSize: 15,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 11),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send button
                  _SendButton(
                    controller: _sendBtnController,
                    isEditing: _editingMessageId != null,
                    active: _isTyping || _editingMessageId != null,
                    onTap: _sendMessage,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Attachment sheet ─────────────────────────────────────────
  Future<void> _handleMediaPick(
      ChatMediaParams mediaParams,
      Future<MediaUploadResult?> Function() pickFn,
      ) async {
    if (_isSendingMedia) return;
    setState(() => _isSendingMedia = true);
    try {
      final result = await pickFn();
      if (!mounted) return;
      if (result == null) return;
      if (!result.success || result.mediaItem == null) {
        _showErrorSnackBar(result.error ?? 'Upload failed. Please try again.');
        return;
      }
      await _sendMediaMessage(result.mediaItem!);
    } catch (e) {
      if (mounted) _showErrorSnackBar('Failed to send media: $e');
    } finally {
      if (mounted) setState(() => _isSendingMedia = false);
    }
  }

  void _showAttachmentOptions(ChatMediaParams mediaParams) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _AttachmentSheet(
        onCamera: () {
          Navigator.pop(sheetCtx);
          _handleMediaPick(
            mediaParams,
                () => ref
                .read(chatMediaProvider(mediaParams).notifier)
                .pickImageFromCamera(),
          );
        },
        onGallery: () {
          Navigator.pop(sheetCtx);
          _handleMediaPick(
            mediaParams,
                () => ref
                .read(chatMediaProvider(mediaParams).notifier)
                .pickImageFromGallery(),
          );
        },
        onDocument: () {
          Navigator.pop(sheetCtx);
          _handleMediaPick(
            mediaParams,
                () => ref
                .read(chatMediaProvider(mediaParams).notifier)
                .pickDocument(),
          );
        },
      ),
    );
  }

  // ─── Message options ─────────────────────────────────────────
  void _showMessageOptions(DirectMessage message, bool isFromMe) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MessageOptionsSheet(
        isFromMe: isFromMe,
        onEdit: isFromMe
            ? () {
          Navigator.pop(ctx);
          _startEdit(message);
        }
            : null,
        onDelete: isFromMe
            ? () {
          Navigator.pop(ctx);
          _showDeleteConfirmation(message.id);
        }
            : null,
        onCopy: () {
          Navigator.pop(ctx);
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Copied to clipboard'),
              backgroundColor: _C.surfaceAlt,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 1),
              margin:
              const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            ),
          );
        },
        onReport: !isFromMe
            ? () {
          Navigator.pop(ctx);
          _showFeatureNotAvailable('Report message');
        }
            : null,
      ),
    );
  }

  // ─── Dialogs ─────────────────────────────────────────────────
  void _showDeleteConfirmation(String messageId) {
    showDialog(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        title: 'Delete message?',
        body: 'This action cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: Colors.red,
        onConfirm: () {
          Navigator.pop(ctx);
          _deleteMessage(messageId);
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'clear':
        showDialog(
          context: context,
          builder: (ctx) => _ConfirmDialog(
            title: 'Clear chat?',
            body:
            'All messages with ${widget.receiverName} will be removed.',
            confirmLabel: 'Clear',
            confirmColor: Colors.red,
            onConfirm: () {
              Navigator.pop(ctx);
              _showFeatureNotAvailable('Clear chat');
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        );
        break;
      case 'mute':
        _showFeatureNotAvailable('Mute notifications');
        break;
      case 'block':
        showDialog(
          context: context,
          builder: (ctx) => _ConfirmDialog(
            title: 'Block ${widget.receiverName}?',
            body: "You won't receive messages from them.",
            confirmLabel: 'Block',
            confirmColor: Colors.red,
            onConfirm: () {
              Navigator.pop(ctx);
              _showFeatureNotAvailable('Block user');
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        );
        break;
      case 'report':
        showDialog(
          context: context,
          builder: (ctx) => _ConfirmDialog(
            title: 'Report ${widget.receiverName}?',
            body: 'Report for inappropriate behavior?',
            confirmLabel: 'Report',
            confirmColor: Colors.orange,
            onConfirm: () {
              Navigator.pop(ctx);
              _showFeatureNotAvailable('Report user');
            },
            onCancel: () => Navigator.pop(ctx),
          ),
        );
        break;
    }
  }

  void _showFeatureNotAvailable(String feature) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature — coming soon'),
        backgroundColor: _C.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      ),
    );
  }

  // ─── State widgets ─────────────────────────────────────────
  Widget _buildTimestampDivider(DateTime dt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(
              child: Divider(
                  color: _C.border.withOpacity(0.6), thickness: 0.5)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _C.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.border, width: 0.5),
            ),
            child: Text(
              _formatDate(dt),
              style: const TextStyle(
                  color: _C.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3),
            ),
          ),
          Expanded(
              child: Divider(
                  color: _C.border.withOpacity(0.6), thickness: 0.5)),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: _C.accent.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Loading messages…',
              style: TextStyle(
                  color: _C.textMuted, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 56, color: _C.textMuted.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text('Failed to load messages',
                style: TextStyle(
                    color: _C.textSecondary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: _C.textMuted, fontSize: 13)),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                if (_currentUserId != null) {
                  final params = createChatParams(
                      currentUserId: _currentUserId!,
                      receiverId: widget.receiverId);
                  ref
                      .read(directMessageProvider(params).notifier)
                      .refresh();
                }
              },
              style: TextButton.styleFrom(
                backgroundColor: _C.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _C.accent.withOpacity(0.08),
                border: Border.all(
                    color: _C.accent.withOpacity(0.15), width: 1.5),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  size: 36, color: _C.accent),
            ),
            const SizedBox(height: 20),
            Text(
              'Say hi to ${widget.receiverName}',
              style: const TextStyle(
                color: _C.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Messages are end-to-end encrypted',
              style: TextStyle(color: _C.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Formatters ──────────────────────────────────────────────
  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(dt.year, dt.month, dt.day);

    if (msgDay == today) return 'Today';
    if (msgDay == yesterday) return 'Yesterday';
    if (now.difference(dt).inDays < 7) {
      const days = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
      ];
      return days[dt.weekday - 1];
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────
// CHAT BUBBLE — extracted widget
// ─────────────────────────────────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final DirectMessage message;
  final bool isFromMe;
  final bool isGroupStart;
  final bool isGroupEnd;
  final String? receiverPic;
  final String? currentUserId;
  final VoidCallback onLongPress;
  final void Function(String url) onImageTap;
  final void Function(String url, String name) onDownload;
  final Map<String, double> downloadProgress;
  final Map<String, bool> isDownloading;

  const _ChatBubble({
    required this.message,
    required this.isFromMe,
    required this.isGroupStart,
    required this.isGroupEnd,
    required this.receiverPic,
    required this.currentUserId,
    required this.onLongPress,
    required this.onImageTap,
    required this.onDownload,
    required this.downloadProgress,
    required this.isDownloading,
  });

  bool get _isMedia =>
      message.messageType == 'image' || message.messageType == 'file';

  @override
  Widget build(BuildContext context) {
    // Time label
    final timeStr = _formatTime(message.createdAt);

    return Padding(
      padding: EdgeInsets.only(
        top: isGroupStart ? 6 : 2,
        bottom: isGroupEnd ? 2 : 0,
        left: isFromMe ? 48 : 0,
        right: isFromMe ? 0 : 48,
      ),
      child: Row(
        mainAxisAlignment:
        isFromMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Other's avatar — only on last in group
          if (!isFromMe) ...[
            if (isGroupEnd)
              _Avatar(url: receiverPic, size: 28)
            else
              const SizedBox(width: 28),
            const SizedBox(width: 8),
          ],

          // Bubble
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Column(
                crossAxisAlignment: isFromMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      gradient: isFromMe
                          ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_C.myBubbleTop, _C.myBubble],
                      )
                          : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_C.theirBubbleTop, _C.theirBubble],
                      ),
                      borderRadius: _bubbleRadius(),
                      boxShadow: [
                        BoxShadow(
                          color: isFromMe
                              ? _C.myBubble.withOpacity(0.25)
                              : Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Media content (no extra padding)
                        if (_isMedia && message.metadata != null)
                          _buildMediaContent(message.metadata!),

                        // Text + meta row
                        Padding(
                          padding: EdgeInsets.only(
                            left: 14,
                            right: 14,
                            top: _isMedia ? 8 : 10,
                            bottom: 8,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Don't show the auto-generated "📷 Image: …" text
                              if (!_isMedia)
                                Text(
                                  message.content,
                                  style: const TextStyle(
                                    color: _C.textPrimary,
                                    fontSize: 15,
                                    height: 1.4,
                                  ),
                                ),

                              const SizedBox(height: 5),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (message.updatedAt != null) ...[
                                    const Icon(Icons.edit_rounded,
                                        size: 11, color: _C.textMuted),
                                    const SizedBox(width: 3),
                                  ],
                                  Text(
                                    timeStr,
                                    style: const TextStyle(
                                        color: _C.textMuted,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  if (isFromMe) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      message.isRead
                                          ? Icons.done_all_rounded
                                          : Icons.done_rounded,
                                      size: 14,
                                      color: message.isRead
                                          ? const Color(0xFF60A5FA)
                                          : _C.textMuted,
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // My avatar (only on last in group)
          if (isFromMe) ...[
            const SizedBox(width: 8),
            if (isGroupEnd)
              Consumer(builder: (ctx, ref, _) {
                final profileAsync = ref.watch(
                    userProfileProvider(currentUserId ?? ''));
                return profileAsync.when(
                  data: (p) =>
                      _Avatar(url: p?.profilePic, size: 28),
                  loading: () =>
                  const SizedBox(width: 28, height: 28),
                  error: (_, __) =>
                  const _Avatar(url: null, size: 28),
                );
              })
            else
              const SizedBox(width: 28),
          ],
        ],
      ),
    );
  }

  BorderRadius _bubbleRadius() {
    const r = Radius.circular(20);
    const rSmall = Radius.circular(5);

    if (isFromMe) {
      return BorderRadius.only(
        topLeft: r,
        topRight: isGroupStart ? r : r,
        bottomLeft: r,
        bottomRight: isGroupEnd ? rSmall : r,
      );
    } else {
      return BorderRadius.only(
        topLeft: isGroupStart ? r : r,
        topRight: r,
        bottomLeft: isGroupEnd ? rSmall : r,
        bottomRight: r,
      );
    }
  }

  Widget _buildMediaContent(Map<String, dynamic> meta) {
    final mediaType = meta['media_type'] as String?;
    final fileUrl = meta['file_url'] as String?;
    final fileName = meta['file_name'] as String? ?? 'file';
    final fileSize = meta['file_size'] as int? ?? 0;

    if (fileUrl == null) return const SizedBox.shrink();

    if (mediaType == 'image') {
      return _buildImageContent(fileUrl);
    } else {
      return _buildFileContent(fileName, fileSize, fileUrl);
    }
  }

  Widget _buildImageContent(String imageUrl) {
    return GestureDetector(
      onTap: () => onImageTap(imageUrl),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          Hero(
            tag: 'chat_img_$imageUrl',
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: 240,
              height: 200,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                width: 240,
                height: 200,
                color: _C.surfaceAlt,
                child: const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _C.accent),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                width: 240,
                height: 160,
                color: _C.surfaceAlt,
                child: const Center(
                  child: Icon(Icons.broken_image_rounded,
                      color: _C.textMuted, size: 40),
                ),
              ),
            ),
          ),
          // Save button overlay
          Positioned(
            bottom: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => onDownload(imageUrl,
                  'image_${DateTime.now().millisecondsSinceEpoch}.jpg'),
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.download_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileContent(String fileName, int fileSize, String fileUrl) {
    final ext = fileName.split('.').last.toUpperCase();
    final isLoading = isDownloading[fileUrl] == true;
    final progress = downloadProgress[fileUrl] ?? 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // File icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _fileColor(ext).withOpacity(0.3),
                    _fileColor(ext).withOpacity(0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_fileIcon(ext), color: _fileColor(ext), size: 22),
            ),
            const SizedBox(width: 12),

            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      color: _C.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${ext}  •  ${_formatSize(fileSize)}',
                    style: const TextStyle(
                        color: _C.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500),
                  ),
                  if (isLoading) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      backgroundColor:
                      Colors.white.withOpacity(0.1),
                      color: _C.accent,
                      minHeight: 2,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Download button
            GestureDetector(
              onTap: isLoading ? null : () => onDownload(fileUrl, fileName),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isLoading
                      ? Colors.white.withOpacity(0.05)
                      : _C.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLoading
                        ? Colors.white.withOpacity(0.08)
                        : _C.accent.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: isLoading
                    ? const Padding(
                  padding: EdgeInsets.all(9),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _C.accent,
                  ),
                )
                    : const Icon(Icons.download_rounded,
                    color: _C.accent, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String ext) {
    switch (ext) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'DOC':
      case 'DOCX':
        return Icons.description_rounded;
      case 'XLS':
      case 'XLSX':
        return Icons.table_chart_rounded;
      case 'PPT':
      case 'PPTX':
        return Icons.slideshow_rounded;
      case 'TXT':
        return Icons.text_snippet_rounded;
      case 'ZIP':
      case 'RAR':
        return Icons.folder_zip_rounded;
      case 'MP4':
      case 'MOV':
        return Icons.video_file_rounded;
      case 'MP3':
      case 'AAC':
        return Icons.audio_file_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _fileColor(String ext) {
    switch (ext) {
      case 'PDF':
        return const Color(0xFFEF4444);
      case 'DOC':
      case 'DOCX':
        return const Color(0xFF3B82F6);
      case 'XLS':
      case 'XLSX':
        return const Color(0xFF22C55E);
      case 'PPT':
      case 'PPTX':
        return const Color(0xFFF97316);
      case 'ZIP':
      case 'RAR':
        return const Color(0xFFF59E0B);
      case 'MP4':
      case 'MOV':
        return const Color(0xFF8B5CF6);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $amPm';
  }
}

// ─────────────────────────────────────────────────────────────
// REUSABLE SMALL WIDGETS
// ─────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? url;
  final double size;
  const _Avatar({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _C.surfaceAlt,
        border: Border.all(color: _C.border, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: url?.isNotEmpty == true
          ? CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.cover,
        placeholder: (_, __) => const SizedBox(),
        errorWidget: (_, __, ___) => Icon(Icons.person_rounded,
            color: _C.textMuted, size: size * 0.5),
      )
          : Icon(Icons.person_rounded,
          color: _C.textMuted, size: size * 0.5),
    );
  }
}

class _SendButton extends StatelessWidget {
  final AnimationController controller;
  final bool isEditing;
  final bool active;
  final VoidCallback onTap;
  const _SendButton({
    required this.controller,
    required this.isEditing,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: active
              ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
          )
              : null,
          color: active ? null : _C.surfaceAlt,
          border: Border.all(
            color: active ? Colors.transparent : _C.border,
            width: 1,
          ),
          boxShadow: active
              ? [
            BoxShadow(
              color: _C.accent.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ]
              : null,
        ),
        child: Icon(
          isEditing ? Icons.check_rounded : Icons.send_rounded,
          color: active ? Colors.white : _C.textMuted,
          size: 20,
        ),
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _AttachButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: busy ? _C.surfaceAlt.withOpacity(0.5) : _C.surfaceAlt,
          border: Border.all(color: _C.border, width: 1),
        ),
        child: busy
            ? const Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(
              strokeWidth: 2, color: _C.textMuted),
        )
            : const Icon(Icons.add_rounded, color: _C.textSecondary, size: 22),
      ),
    );
  }
}

class _EditBanner extends StatelessWidget {
  final VoidCallback onCancel;
  const _EditBanner({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _C.editBanner.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.editBanner.withOpacity(0.25), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 16,
            decoration: BoxDecoration(
              color: _C.editBanner,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.edit_rounded, color: _C.editBanner, size: 15),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Editing message',
                style: TextStyle(
                    color: _C.editBanner,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close_rounded,
                color: _C.editBanner, size: 18),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ATTACHMENT SHEET
// ─────────────────────────────────────────────────────────────
class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final VoidCallback onDocument;
  const _AttachmentSheet(
      {required this.onCamera,
        required this.onGallery,
        required this.onDocument});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _C.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Share',
              style: TextStyle(
                  color: _C.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SheetOption(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                gradient: const [Color(0xFF6366F1), Color(0xFF4F46E5)],
                onTap: onCamera,
              ),
              _SheetOption(
                icon: Icons.photo_library_rounded,
                label: 'Gallery',
                gradient: const [Color(0xFFEC4899), Color(0xFFDB2777)],
                onTap: onGallery,
              ),
              _SheetOption(
                icon: Icons.description_rounded,
                label: 'Document',
                gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
                onTap: onDocument,
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;
  const _SheetOption(
      {required this.icon,
        required this.label,
        required this.gradient,
        required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: gradient.last.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  color: _C.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// MESSAGE OPTIONS SHEET
// ─────────────────────────────────────────────────────────────
class _MessageOptionsSheet extends StatelessWidget {
  final bool isFromMe;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback onCopy;
  final VoidCallback? onReport;
  const _MessageOptionsSheet(
      {required this.isFromMe,
        this.onEdit,
        this.onDelete,
        required this.onCopy,
        this.onReport});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _C.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _C.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          if (onEdit != null) _OptionTile(Icons.edit_rounded, 'Edit', _C.accent, onEdit!),
          _OptionTile(Icons.copy_rounded, 'Copy', _C.textPrimary, onCopy),
          if (onDelete != null)
            _OptionTile(Icons.delete_rounded, 'Delete', Colors.red, onDelete!),
          if (onReport != null)
            _OptionTile(Icons.flag_rounded, 'Report', Colors.orange, onReport!),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _OptionTile(this.icon, this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label,
          style: TextStyle(
              color: color, fontSize: 15, fontWeight: FontWeight.w500)),
      onTap: onTap,
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// CONFIRM DIALOG
// ─────────────────────────────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final Color confirmColor;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  const _ConfirmDialog(
      {required this.title,
        required this.body,
        required this.confirmLabel,
        required this.confirmColor,
        required this.onConfirm,
        required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _C.border, width: 0.5),
      ),
      title: Text(title,
          style: const TextStyle(
              color: _C.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 16)),
      content: Text(body,
          style: const TextStyle(color: _C.textSecondary, fontSize: 14)),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: const Text('Cancel',
              style: TextStyle(color: _C.textMuted)),
        ),
        TextButton(
          onPressed: onConfirm,
          child: Text(confirmLabel,
              style: TextStyle(
                  color: confirmColor, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// UPLOAD PROGRESS PILL
// ─────────────────────────────────────────────────────────────
class _UploadProgressPill extends StatelessWidget {
  final double progress;
  final bool isUploading;
  const _UploadProgressPill(
      {required this.progress, required this.isUploading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _C.surface.withOpacity(0.97),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _C.border, width: 0.5),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: isUploading && progress > 0 ? progress : null,
              strokeWidth: 2,
              color: _C.accent,
              backgroundColor: _C.border,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isUploading
                ? 'Uploading… ${(progress * 100).toInt()}%'
                : 'Preparing…',
            style: const TextStyle(
                color: _C.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// DOT-GRID BACKGROUND PAINTER
// ─────────────────────────────────────────────────────────────
class _DotGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E1E2E).withOpacity(0.6)
      ..style = PaintingStyle.fill;

    const spacing = 28.0;
    const radius = 1.0;

    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}