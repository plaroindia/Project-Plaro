// dm_provider.dart - FIXED with proper state management
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';
import 'notifications_provider.dart';

// Message Model (unchanged)
class DirectMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String receiverId;
  final String content;
  final String messageType;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isRead;
  final String? replyToId;
  final Map<String, dynamic>? metadata;

  const DirectMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    this.messageType = 'text',
    required this.createdAt,
    this.updatedAt,
    this.isRead = false,
    this.replyToId,
    this.metadata,
  });

  factory DirectMessage.fromJson(Map<String, dynamic> json) {
    try {
      return DirectMessage(
        id: _parseStringField(json['id'], 'id'),
        chatId: _parseStringField(json['chat_id'], 'chat_id'),
        senderId: _parseStringField(json['sender_id'], 'sender_id'),
        receiverId: _parseStringField(json['receiver_id'], 'receiver_id'),
        content: _parseStringField(json['content'], 'content'),
        messageType: json['message_type'] as String? ?? 'text',
        createdAt: _parseDateTime(json['created_at'], 'created_at'),
        updatedAt: json['updated_at'] != null
            ? _parseDateTime(json['updated_at'], 'updated_at')
            : null,
        isRead: json['is_read'] as bool? ?? false,
        replyToId: json['reply_to_id'] as String?,
        metadata: _parseMetadata(json['metadata']),
      );
    } catch (e) {
      print('Error parsing DirectMessage from JSON: $e');
      print('JSON data: $json');
      rethrow;
    }
  }

  static String _parseStringField(dynamic value, String fieldName) {
    if (value == null) {
      throw FormatException('Required field $fieldName is null');
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  static DateTime _parseDateTime(dynamic value, String fieldName) {
    if (value == null) {
      throw FormatException('Required field $fieldName is null');
    }
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        throw FormatException('Invalid datetime format for $fieldName: $value');
      }
    }
    if (value is DateTime) {
      return value;
    }
    throw FormatException('Invalid type for $fieldName: ${value.runtimeType}');
  }

  static Map<String, dynamic>? _parseMetadata(dynamic value) {
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      } catch (e) {
        print('Error parsing metadata JSON: $e');
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'message_type': messageType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'is_read': isRead,
      'reply_to_id': replyToId,
      'metadata': metadata,
    };
  }

  DirectMessage copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? receiverId,
    String? content,
    String? messageType,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isRead,
    String? replyToId,
    Map<String, dynamic>? metadata,
  }) {
    return DirectMessage(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isRead: isRead ?? this.isRead,
      replyToId: replyToId ?? this.replyToId,
      metadata: metadata ?? this.metadata,
    );
  }
}

// FIXED Chat State - Added typing state separation
class ChatState {
  final List<DirectMessage> messages;
  final bool isInitialLoading;
  final String? error;
  final bool hasMoreMessages;
  final String? currentUserId;
  final bool isTyping;
  final DateTime? lastMessageTime;
  final bool isOtherUserTyping; // NEW: Separate typing indicator

  const ChatState({
    this.messages = const [],
    this.isInitialLoading = false,
    this.error,
    this.hasMoreMessages = true,
    this.currentUserId,
    this.isTyping = false,
    this.lastMessageTime,
    this.isOtherUserTyping = false,
  });

  ChatState copyWith({
    List<DirectMessage>? messages,
    bool? isInitialLoading,
    String? error,
    bool? hasMoreMessages,
    String? currentUserId,
    bool? isTyping,
    DateTime? lastMessageTime,
    bool? isOtherUserTyping,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isInitialLoading: isInitialLoading ?? this.isInitialLoading,
      error: error,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      currentUserId: currentUserId ?? this.currentUserId,
      isTyping: isTyping ?? this.isTyping,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      isOtherUserTyping: isOtherUserTyping ?? this.isOtherUserTyping,
    );
  }

  bool get isEmpty => messages.isEmpty && !isInitialLoading;
  bool get hasError => error != null;
}

// FIXED DM Notifier - Proper disposal and state management
class DirectMessageNotifier extends StateNotifier<ChatState> {
  final String chatId;
  final String currentUserId;
  final String receiverId;
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<List<Map<String, dynamic>>>? _messagesSubscription;
  RealtimeChannel? _readReceiptChannel;
  Timer? _typingTimer;
  Timer? _retryTimer;
  Timer? _initTimer;

  static const int _pageSize = 30;
  bool _disposed = false;
  bool _hasInitialLoad = false;
  bool _isLoadingMore = false;
  DateTime? _subscriptionStartTime;

  DirectMessageNotifier({
    required this.chatId,
    required this.currentUserId,
    required this.receiverId,
  }) : super(ChatState(currentUserId: currentUserId)) {
    print('DirectMessageNotifier: Creating for chat $chatId');
    _initializeChat();
  }

  void _initializeChat() {
    if (_disposed) return;
    print('DirectMessageNotifier: Initializing chat...');
    _loadInitialMessages();

    // Set up real-time listener after initial load with delay
    _initTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!_disposed && _hasInitialLoad) {
        _subscribeToMessages();
        _subscribeToReadReceipts();
      }
    });
  }

  static String generateChatId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  // FIXED: Always check mounted and disposed
  void _safeUpdateState(ChatState Function(ChatState) update) {
    if (_disposed || !mounted) return;

    try {
      state = update(state);
    } catch (e) {
      print('DirectMessageNotifier: State update error: $e');
    }
  }

  Future<void> _loadInitialMessages() async {
    if (_disposed || _hasInitialLoad) return;

    try {
      print('DirectMessageNotifier: Loading initial messages...');
      _safeUpdateState((state) => state.copyWith(
          isInitialLoading: true,
          error: null
      ));

      final response = await _supabase
          .from('direct_messages')
          .select('*')
          .eq('chat_id', chatId)
          .not('id', 'is', null)
          .not('sender_id', 'is', null)
          .not('receiver_id', 'is', null)
          .not('content', 'is', null)
          .not('created_at', 'is', null)
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (_disposed || !mounted) return;

      final List<DirectMessage> messages = [];
      for (final json in response as List) {
        try {
          final message = DirectMessage.fromJson(json);
          messages.add(message);
        } catch (e) {
          print('DirectMessageNotifier: Skipping invalid message: $e');
          continue;
        }
      }

      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      if (_disposed || !mounted) return;

      final lastMessageTime = messages.isNotEmpty
          ? messages.first.createdAt
          : null;

      _safeUpdateState((state) => state.copyWith(
        messages: messages,
        isInitialLoading: false,
        hasMoreMessages: messages.length == _pageSize,
        lastMessageTime: lastMessageTime,
      ));

      _hasInitialLoad = true;
      print('DirectMessageNotifier: Loaded ${messages.length} initial messages');

      // Mark messages as read without blocking
      if (!_disposed && mounted) {
        _markMessagesAsRead();
      }

    } catch (error) {
      if (!_disposed && mounted) {
        print('DirectMessageNotifier: Error loading initial messages: $error');
        _safeUpdateState((state) => state.copyWith(
          isInitialLoading: false,
          error: 'Failed to load messages',
        ));
      }
    }
  }

  Future<void> loadMoreMessages() async {
    if (_disposed || !mounted || !_hasInitialLoad || _isLoadingMore || !state.hasMoreMessages) {
      return;
    }

    _isLoadingMore = true;

    try {
      print('DirectMessageNotifier: Loading more messages...');

      final response = await _supabase
          .from('direct_messages')
          .select('*')
          .eq('chat_id', chatId)
          .not('id', 'is', null)
          .not('sender_id', 'is', null)
          .not('receiver_id', 'is', null)
          .not('content', 'is', null)
          .not('created_at', 'is', null)
          .lt('created_at', state.lastMessageTime!.toIso8601String())
          .order('created_at', ascending: false)
          .limit(_pageSize);

      if (_disposed || !mounted) return;

      final List<DirectMessage> newMessages = [];
      for (final json in response as List) {
        try {
          final message = DirectMessage.fromJson(json);
          newMessages.add(message);
        } catch (e) {
          print('DirectMessageNotifier: Skipping invalid message: $e');
          continue;
        }
      }

      if (_disposed || !mounted) return;

      newMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final updatedMessages = [...newMessages, ...state.messages];

      final newLastMessageTime = newMessages.isNotEmpty
          ? newMessages.first.createdAt
          : state.lastMessageTime;

      _safeUpdateState((state) => state.copyWith(
        messages: updatedMessages,
        hasMoreMessages: newMessages.length == _pageSize,
        lastMessageTime: newLastMessageTime,
      ));

      print('DirectMessageNotifier: Loaded ${newMessages.length} more messages');

    } catch (error) {
      print('DirectMessageNotifier: Error loading more messages: $error');
    } finally {
      _isLoadingMore = false;
    }
  }

  // FIXED: Real-time subscription with proper filtering
  void _subscribeToMessages() {
    if (_disposed || !mounted || !_hasInitialLoad) return;

    try {
      print('DirectMessageNotifier: Setting up real-time subscription...');

      _messagesSubscription?.cancel();
      _subscriptionStartTime = DateTime.now();

      _messagesSubscription = _supabase
          .from('direct_messages')
          .stream(primaryKey: ['id'])
          .eq('chat_id', chatId)
          .listen(
            (data) {
          if (_disposed || !mounted) return;

          // FIXED: Only process genuinely new messages
          final newMessages = data.where((messageData) {
            try {
              final createdAt = DateTime.parse(messageData['created_at'] as String);
              final messageId = messageData['id'] as String;

              // Check if message is newer than subscription AND not already in state
              final isNewMessage = createdAt.isAfter(_subscriptionStartTime!);
              final existingIds = state.messages.map((m) => m.id).toSet();
              final notInState = !existingIds.contains(messageId);

              return isNewMessage && notInState;
            } catch (e) {
              return false;
            }
          }).toList();

          if (newMessages.isNotEmpty && !state.isTyping) {
            // FIXED: Only update when user is not typing to prevent list refresh
            print('DirectMessageNotifier: Received ${newMessages.length} new messages (user not typing)');
            _handleNewMessages(newMessages);
          } else if (newMessages.isNotEmpty && state.isTyping) {
            print('DirectMessageNotifier: Received messages but user is typing - deferring update');
          }
        },
        onError: (error) {
          if (_disposed || !mounted) return;
          print('DirectMessageNotifier: Stream error: $error');
          _scheduleRetry();
        },
        onDone: () {
          print('DirectMessageNotifier: Stream closed');
          if (!_disposed && mounted) {
            _scheduleRetry();
          }
        },
      );

      print('DirectMessageNotifier: Real-time subscription established');

    } catch (error) {
      print('DirectMessageNotifier: Error setting up subscription: $error');
      _scheduleRetry();
    }
  }

  // Realtime channel that listens for UPDATE events on this chat's messages.
  // The .stream() subscription above only fires for INSERTs, so is_read flips
  // would never reach the sender without this dedicated channel.
  void _subscribeToReadReceipts() {
    if (_disposed || !mounted) return;

    _readReceiptChannel?.unsubscribe();

    _readReceiptChannel = _supabase
        .channel('read_receipts_$chatId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'direct_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (payload) {
            if (_disposed || !mounted) return;

            final updated = payload.newRecord;
            final updatedId = updated['id'] as String?;
            final isRead = updated['is_read'] as bool? ?? false;

            if (updatedId == null || !isRead) return;

            // Flip is_read on the matching message in local state
            final msgs = state.messages.map((m) {
              if (m.id == updatedId && !m.isRead) {
                return m.copyWith(isRead: true);
              }
              return m;
            }).toList();

            _safeUpdateState((state) => state.copyWith(messages: msgs));
            print('DirectMessageNotifier: Read receipt received for message $updatedId');
          },
        )
        .subscribe();

    print('DirectMessageNotifier: Read receipt channel subscribed for chat $chatId');
  }

  void _handleNewMessages(List<Map<String, dynamic>> data) {
    if (_disposed || !mounted) return;

    try {
      final List<DirectMessage> newMessages = [];

      for (final json in data) {
        try {
          final message = DirectMessage.fromJson(json);
          newMessages.add(message);
        } catch (e) {
          print('DirectMessageNotifier: Skipping invalid message in stream: $e');
          continue;
        }
      }

      if (newMessages.isNotEmpty) {
        print('DirectMessageNotifier: Processing ${newMessages.length} new messages');

        newMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final updatedMessages = [...state.messages, ...newMessages];

        _safeUpdateState((state) => state.copyWith(
          messages: updatedMessages,
        ));

        // Mark new messages as read
        if (!_disposed && mounted) {
          _markMessagesAsRead();
        }
      }
    } catch (error) {
      print('DirectMessageNotifier: Error handling new messages: $error');
    }
  }

  void _scheduleRetry() {
    if (_disposed || !mounted) return;

    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), () {
      if (!_disposed && mounted && _hasInitialLoad) {
        _subscribeToMessages();
        _subscribeToReadReceipts();
      }
    });
  }

  // FIXED: Send message without optimistic updates
  Future<void> sendMessage({
    required String content,
    String messageType = 'text',
    String? replyToId,
    Map<String, dynamic>? metadata,
  }) async {
    if (content.trim().isEmpty || _disposed || !mounted) return;

    final messageId = const Uuid().v4();

    try {
      print('DirectMessageNotifier: Sending message...');

      await _supabase.from('direct_messages').insert({
        'id': messageId,
        'chat_id': chatId,
        'sender_id': currentUserId,
        'receiver_id': receiverId,
        'content': content.trim(),
        'message_type': messageType,
        'reply_to_id': replyToId,
        'metadata': metadata,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      print('DirectMessageNotifier: Message sent successfully');

      // Fire-and-forget DM notification — never blocks or throws.
      // Only notifies when the receiver is not the sender (no self-chats).
      if (receiverId != currentUserId) {
        _sendDmNotification(content: content.trim());
      }

    } catch (error) {
      print('DirectMessageNotifier: Error sending message: $error');
      rethrow;
    }
  }

  // Insert a DM notification for the receiver.
  // Fetches sender's username once per send — cheap since Supabase
  // caches repeated profile lookups within the same session.
  Future<void> _sendDmNotification({required String content}) async {
    try {
      final senderRow = await _supabase
          .from('user_profiles')
          .select('username')
          .eq('user_id', currentUserId)
          .maybeSingle();

      final senderName = senderRow?['username'] as String? ?? 'Someone';

      // Truncate preview to 60 chars so long messages don't flood the notif
      final preview = content.length > 60
          ? '${content.substring(0, 60)}…'
          : content;

      await NotificationsNotifier.insert(
        targetUserId: receiverId,
        type: 'dm',
        title: senderName,
        body: preview,
        relatedType: 'user',
        relatedId: currentUserId,
      );
    } catch (e) {
      print('DirectMessageNotifier: DM notification error (non-fatal): $e');
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (_disposed || !mounted) return;

    try {
      final unreadMessages = state.messages
          .where((m) => m.senderId != currentUserId && !m.isRead)
          .map((m) => m.id)
          .toList();

      if (unreadMessages.isNotEmpty) {
        // Update DB
        await _supabase
            .from('direct_messages')
            .update({'is_read': true})
            .inFilter('id', unreadMessages);

        // Immediately reflect in local state so the sender sees blue ticks
        // via the _readReceiptChannel broadcast without a UI lag.
        if (!_disposed && mounted) {
          final ids = unreadMessages.toSet();
          final updatedMessages = state.messages.map((m) {
            if (ids.contains(m.id)) return m.copyWith(isRead: true);
            return m;
          }).toList();
          _safeUpdateState((s) => s.copyWith(messages: updatedMessages));
        }

        print('DirectMessageNotifier: Marked ${unreadMessages.length} messages as read');
      }
    } catch (error) {
      print('DirectMessageNotifier: Error marking messages as read: $error');
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (_disposed || !mounted) return;

    try {
      await _supabase
          .from('direct_messages')
          .delete()
          .eq('id', messageId)
          .eq('sender_id', currentUserId);

      // Remove from local state immediately
      if (!_disposed && mounted) {
        final updatedMessages = state.messages
            .where((m) => m.id != messageId)
            .toList();

        _safeUpdateState((state) => state.copyWith(messages: updatedMessages));
      }

    } catch (error) {
      if (!_disposed && mounted) {
        _safeUpdateState((state) => state.copyWith(
            error: 'Failed to delete message'
        ));
      }
    }
  }

  Future<void> editMessage(String messageId, String newContent) async {
    if (newContent.trim().isEmpty || _disposed || !mounted) return;

    try {
      await _supabase
          .from('direct_messages')
          .update({
        'content': newContent.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', messageId)
          .eq('sender_id', currentUserId);

      // Update local state immediately
      if (!_disposed && mounted) {
        final updatedMessages = state.messages.map((m) {
          if (m.id == messageId) {
            return m.copyWith(
              content: newContent.trim(),
              updatedAt: DateTime.now(),
            );
          }
          return m;
        }).toList();

        _safeUpdateState((state) => state.copyWith(messages: updatedMessages));
      }

    } catch (error) {
      if (!_disposed && mounted) {
        _safeUpdateState((state) => state.copyWith(
            error: 'Failed to edit message'
        ));
      }
    }
  }

  // FIXED: Typing indicator that doesn't trigger list refresh
  void setTyping(bool isTyping) {
    if (_disposed || !mounted) return;

    _safeUpdateState((state) => state.copyWith(isTyping: isTyping));

    if (isTyping) {
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        if (!_disposed && mounted) {
          _safeUpdateState((state) => state.copyWith(isTyping: false));
        }
      });
    }
  }

  void clearError() {
    if (!_disposed && mounted && state.hasError) {
      _safeUpdateState((state) => state.copyWith(error: null));
    }
  }

  void refresh() {
    if (!_disposed && mounted) {
      print('DirectMessageNotifier: Refreshing messages...');
      _hasInitialLoad = false;
      _safeUpdateState((state) => state.copyWith(messages: []));
      _loadInitialMessages();
    }
  }

  @override
  void dispose() {
    print('DirectMessageNotifier: Starting disposal for chat $chatId');

    // Set disposed flag immediately
    _disposed = true;

    // Cancel all timers
    _typingTimer?.cancel();
    _typingTimer = null;

    _retryTimer?.cancel();
    _retryTimer = null;

    _initTimer?.cancel();
    _initTimer = null;

    // Cancel subscription
    _messagesSubscription?.cancel();
    _messagesSubscription = null;

    // Unsubscribe read receipt realtime channel
    _readReceiptChannel?.unsubscribe();
    _readReceiptChannel = null;

    // FIXED: Only call super.dispose() if still mounted
    try {
      if (mounted) {
        super.dispose();
      }
      print('DirectMessageNotifier: Disposal completed for chat $chatId');
    } catch (e) {
      print('DirectMessageNotifier: Disposal error (expected): $e');
    }
  }
}

// Chat List classes (unchanged)
class ChatListState {
  final List<ChatPreview> chats;
  final bool isLoading;
  final String? error;

  const ChatListState({
    this.chats = const [],
    this.isLoading = false,
    this.error,
  });

  ChatListState copyWith({
    List<ChatPreview>? chats,
    bool? isLoading,
    String? error,
  }) {
    return ChatListState(
      chats: chats ?? this.chats,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ChatPreview {
  final String chatId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserProfilePic;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isOnline;

  const ChatPreview({
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserProfilePic,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isOnline = false,
  });

  factory ChatPreview.fromJson(Map<String, dynamic> json) {
    return ChatPreview(
      chatId: json['chat_id'] as String,
      otherUserId: json['other_user_id'] as String,
      otherUserName: json['other_user_name'] as String,
      otherUserProfilePic: json['other_user_profile_pic'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'] as String)
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
      isOnline: json['is_online'] as bool? ?? false,
    );
  }
}

class RecentChatsNotifier extends StateNotifier<ChatListState> {
  final String currentUserId;
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription? _chatsSubscription;
  bool _disposed = false;

  RecentChatsNotifier(this.currentUserId) : super(const ChatListState()) {
    print('RecentChatsNotifier: Creating for user $currentUserId');
    _loadRecentChats();

    Timer(const Duration(seconds: 2), () {
      if (!_disposed && mounted) {
        _subscribeToChats();
      }
    });
  }

  void _safeUpdateState(ChatListState Function(ChatListState) update) {
    if (_disposed || !mounted) return;

    try {
      state = update(state);
    } catch (e) {
      print('RecentChatsNotifier: State update error: $e');
    }
  }

  Future<void> _loadRecentChats() async {
    if (_disposed || !mounted) return;

    try {
      _safeUpdateState((state) => state.copyWith(isLoading: true, error: null));

      final response = await _supabase
          .from('direct_messages')
          .select('''
            chat_id,
            sender_id,
            receiver_id,
            content,
            created_at,
            user_profiles!direct_messages_sender_id_fkey(username, profile_pic),
            user_profiles!direct_messages_receiver_id_fkey(username, profile_pic)
          ''')
          .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
          .order('created_at', ascending: false)
          .limit(10);

      if (_disposed || !mounted) return;

      final Map<String, ChatPreview> chatMap = {};

      for (final message in response as List) {
        final chatId = message['chat_id'] as String;
        if (!chatMap.containsKey(chatId)) {
          final isFromSender = message['sender_id'] == currentUserId;
          final otherUser = isFromSender ? message['receiver'] : message['sender'];

          chatMap[chatId] = ChatPreview(
            chatId: chatId,
            otherUserId: isFromSender ? message['receiver_id'] : message['sender_id'],
            otherUserName: otherUser['username'] ?? 'Unknown',
            otherUserProfilePic: otherUser['profile_pic'],
            lastMessage: message['content'],
            lastMessageTime: DateTime.parse(message['created_at']),
          );
        }
      }

      final chats = chatMap.values.toList()
        ..sort((a, b) => (b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0)));

      _safeUpdateState((state) => state.copyWith(chats: chats, isLoading: false));

    } catch (error) {
      if (!_disposed && mounted) {
        _safeUpdateState((state) => state.copyWith(
          isLoading: false,
          error: 'Failed to load recent chats',
        ));
      }
    }
  }

  void _subscribeToChats() {
    if (_disposed || !mounted) return;

    _chatsSubscription = _supabase
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .listen((data) {
      if (_disposed || !mounted) return;

      final relevantMessages = data.where((message) =>
      message['sender_id'] == currentUserId ||
          message['receiver_id'] == currentUserId).toList();

      if (relevantMessages.isNotEmpty) {
        Timer(const Duration(seconds: 1), () {
          if (!_disposed && mounted) {
            _loadRecentChats();
          }
        });
      }
    },
        onError: (error) {
          if (_disposed || !mounted) return;
          print('RecentChatsNotifier: Stream error: $error');
        });
  }

  void refresh() {
    if (!_disposed && mounted) {
      _loadRecentChats();
    }
  }

  @override
  void dispose() {
    print('RecentChatsNotifier: Starting disposal');
    _disposed = true;
    _chatsSubscription?.cancel();
    _chatsSubscription = null;

    try {
      if (mounted) {
        super.dispose();
      }
      print('RecentChatsNotifier: Disposal completed');
    } catch (e) {
      print('RecentChatsNotifier: Disposal error (expected): $e');
    }
  }
}

// FIXED Providers - Better disposal handling
final directMessageProvider = StateNotifierProvider.family.autoDispose
<DirectMessageNotifier, ChatState, Map<String, String>>(
      (ref, params) {
    print('DirectMessageProvider: Creating for chat ${params['chatId']}');

    final notifier = DirectMessageNotifier(
      chatId: params['chatId']!,
      currentUserId: params['currentUserId']!,
      receiverId: params['receiverId']!,
    );

    // FIXED: Better disposal handling
    ref.onDispose(() {
      print('DirectMessageProvider: Disposing for chat ${params['chatId']}');
      try {
        notifier.dispose();
      } catch (e) {
        print('DirectMessageProvider: Disposal error (expected): $e');
      }
    });

    return notifier;
  },
);

final recentChatsProvider = StateNotifierProvider.family.autoDispose<RecentChatsNotifier, ChatListState, String>(
      (ref, currentUserId) {
    print('RecentChatsProvider: Creating for user $currentUserId');

    final notifier = RecentChatsNotifier(currentUserId);

    ref.onDispose(() {
      print('RecentChatsProvider: Disposing for user $currentUserId');
      try {
        notifier.dispose();
      } catch (e) {
        print('RecentChatsProvider: Disposal error (expected): $e');
      }
    });

    return notifier;
  },
);

Map<String, String> createChatParams({
  required String currentUserId,
  required String receiverId,
}) {
  return {
    'chatId': DirectMessageNotifier.generateChatId(currentUserId, receiverId),
    'currentUserId': currentUserId,
    'receiverId': receiverId,
  };
}