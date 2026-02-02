// Enhanced chat_list_provider.dart with message integration
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../Model/user_profile.dart';

// Enhanced ChatUserProfile model
class ChatUserProfile extends UserProfile {
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isLastMessageFromMe;
  final String? lastMessageId;

  ChatUserProfile({
    required super.user_id,
    required super.username,
    required super.email,
    super.role,
    super.profilePic,
    super.bio,
    super.study,
    super.location,
    super.isVerified,
    super.followersCount,
    super.followingCount,
    super.streakCount,
    super.createdAt,
    super.updatedAt,
    // ✅ ADD THESE RANK PARAMETERS
    super.totalPoints,
    super.rankLevel,
    super.consistencyScore,
    super.authenticityScore,
    super.contributionScore,
    super.freelanceEligible,
    super.verifiedEducator,
    // Chat-specific
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isLastMessageFromMe = false,
    this.lastMessageId,
  });

  factory ChatUserProfile.fromUserProfile(
      UserProfile user, {
        String? lastMessage,
        DateTime? lastMessageTime,
        int unreadCount = 0,
        bool isLastMessageFromMe = false,
        String? lastMessageId,
      }) {
    return ChatUserProfile(
      user_id: user.user_id,
      username: user.username,
      email: user.email,
      role: user.role,
      profilePic: user.profilePic,
      bio: user.bio,
      study: user.study,
      location: user.location,
      isVerified: user.isVerified,
      followersCount: user.followersCount,
      followingCount: user.followingCount,
      streakCount: user.streakCount,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      // ✅ ADD THESE RANK FIELDS
      totalPoints: user.totalPoints,
      rankLevel: user.rankLevel,
      consistencyScore: user.consistencyScore,
      authenticityScore: user.authenticityScore,
      contributionScore: user.contributionScore,
      freelanceEligible: user.freelanceEligible,
      verifiedEducator: user.verifiedEducator,
      // Chat-specific
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
      unreadCount: unreadCount,
      isLastMessageFromMe: isLastMessageFromMe,
      lastMessageId: lastMessageId,
    );
  }

// Override copyWith to include all UserProfile parameters plus chat-specific ones
  @override
  ChatUserProfile copyWith({
    String? user_id,
    String? username,
    String? email,
    String? role,
    String? profilePic,
    String? bio,
    String? study,
    String? location,
    bool? isVerified,
    int? followersCount,
    int? followingCount,
    int? streakCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    // ✅ ADD THESE NEW PARAMETERS
    int? totalPoints,
    String? rankLevel,
    double? consistencyScore,
    double? authenticityScore,
    double? contributionScore,
    bool? freelanceEligible,
    bool? verifiedEducator,
    // Chat-specific parameters
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isLastMessageFromMe,
    String? lastMessageId,
  }) {
    return ChatUserProfile(
      user_id: user_id ?? this.user_id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      profilePic: profilePic ?? this.profilePic,
      bio: bio ?? this.bio,
      study: study ?? this.study,
      location: location ?? this.location,
      isVerified: isVerified ?? this.isVerified,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      streakCount: streakCount ?? this.streakCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      // ✅ ADD THESE TO THE CONSTRUCTOR CALL
      totalPoints: totalPoints ?? this.totalPoints,
      rankLevel: rankLevel ?? this.rankLevel,
      consistencyScore: consistencyScore ?? this.consistencyScore,
      authenticityScore: authenticityScore ?? this.authenticityScore,
      contributionScore: contributionScore ?? this.contributionScore,
      freelanceEligible: freelanceEligible ?? this.freelanceEligible,
      verifiedEducator: verifiedEducator ?? this.verifiedEducator,
      // Chat-specific fields
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isLastMessageFromMe: isLastMessageFromMe ?? this.isLastMessageFromMe,
      lastMessageId: lastMessageId ?? this.lastMessageId,
    );
  }
}
// Enhanced state class for chat users with message data
class EnhancedChatListState {
  final List<ChatUserProfile> users;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final bool hasMore;
  final DateTime? lastFetched;

  const EnhancedChatListState({
    this.users = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.hasMore = true,
    this.lastFetched,
  });

  EnhancedChatListState copyWith({
    List<ChatUserProfile>? users,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool? hasMore,
    DateTime? lastFetched,
  }) {
    return EnhancedChatListState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      lastFetched: lastFetched ?? this.lastFetched,
    );
  }

  bool get isEmpty => users.isEmpty && !isLoading;
  bool get hasError => error != null;
  bool get shouldShowLoading => isLoading && users.isEmpty;
}

// Enhanced ChatListNotifier with message integration
class EnhancedChatListNotifier extends StateNotifier<EnhancedChatListState> {
  final String userId;
  final SupabaseClient _supabase = Supabase.instance.client;
  static const int _pageSize = 20;
  static const Duration _cacheTimeout = Duration(minutes: 5);

  EnhancedChatListNotifier(this.userId) : super(const EnhancedChatListState());

  String _generateChatId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }

  Future<void> fetchChatUsersWithMessages({bool refresh = false}) async {
    try {
      // Prevent multiple simultaneous requests
      if (state.isLoading && !refresh) return;
      if (!state.hasMore && !refresh) return;

      // Check cache validity for refresh
      if (refresh && _isCacheValid() && state.users.isNotEmpty) {
        return;
      }

      state = state.copyWith(
        isLoading: true,
        isRefreshing: refresh,
        error: null,
      );

      final offset = refresh ? 0 : state.users.length;

      // First, get the combined users (followers + following)
      final combinedUsers = await _fetchCombinedUsers().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Request timed out. Please try again.'),
      );

      // Then, fetch message data for these users
      final usersWithMessages = await _enrichWithMessageData(combinedUsers);

      // Apply pagination
      final paginatedUsers = _applyPagination(usersWithMessages, offset, refresh);
      final hasMore = usersWithMessages.length > paginatedUsers.length;

      state = state.copyWith(
        users: paginatedUsers,
        isLoading: false,
        isRefreshing: false,
        hasMore: hasMore,
        lastFetched: DateTime.now(),
        error: null,
      );

    } catch (error) {
      final errorMessage = _getErrorMessage(error);
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: errorMessage,
      );
    }
  }

  Future<List<UserProfile>> _fetchCombinedUsers() async {
    // Create futures for parallel execution
    final followersQuery = _supabase
        .from('user_follows')
        .select('''
          follower_id,
          followed_at,
          follower:user_profiles!fk_follower(
            user_id,
            username,
            email,
            role,
            profile_pic,
            bio,
            study,
            location,
            is_verified,
            followers_count,
            following_count,
            streak_count,
            created_at,
            updated_at
          )
        ''')
        .eq('followee_id', userId)
        .order('followed_at', ascending: false)
        .limit(100);

    final followingQuery = _supabase
        .from('user_follows')
        .select('''
          followee_id,
          followed_at,
          following:user_profiles!fk_followee(
            user_id,
            username,
            email,
            role,
            profile_pic,
            bio,
            study,
            location,
            is_verified,
            followers_count,
            following_count,
            streak_count,
            created_at,
            updated_at
          )
        ''')
        .eq('follower_id', userId)
        .order('followed_at', ascending: false)
        .limit(100);

    // Execute queries in parallel
    final results = await Future.wait([followersQuery, followingQuery]);
    final followersData = results[0] as List;
    final followingData = results[1] as List;

    return _processCombinedData(followersData, followingData);
  }

  List<UserProfile> _processCombinedData(List followersData, List followingData) {
    final Map<String, UserProfile> uniqueUsers = {};
    final Map<String, DateTime> userActivityMap = {};

    // Process followers
    for (final item in followersData) {
      final followerData = item['follower'];
      final followedAt = DateTime.parse(item['followed_at'] ?? DateTime.now().toIso8601String());

      if (followerData != null) {
        final user = UserProfile.fromJson(followerData);
        uniqueUsers[user.user_id] = user;

        if (!userActivityMap.containsKey(user.user_id) ||
            followedAt.isAfter(userActivityMap[user.user_id]!)) {
          userActivityMap[user.user_id] = followedAt;
        }
      }
    }

    // Process following
    for (final item in followingData) {
      final followingUserData = item['following'];
      final followedAt = DateTime.parse(item['followed_at'] ?? DateTime.now().toIso8601String());

      if (followingUserData != null) {
        final user = UserProfile.fromJson(followingUserData);
        uniqueUsers[user.user_id] = user;

        if (!userActivityMap.containsKey(user.user_id) ||
            followedAt.isAfter(userActivityMap[user.user_id]!)) {
          userActivityMap[user.user_id] = followedAt;
        }
      }
    }

    final List<UserProfile> combinedUsers = uniqueUsers.values.toList();
    combinedUsers.sort((a, b) {
      final aActivity = userActivityMap[a.user_id] ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bActivity = userActivityMap[b.user_id] ?? DateTime.fromMillisecondsSinceEpoch(0);

      final activityComparison = bActivity.compareTo(aActivity);
      if (activityComparison != 0) return activityComparison;

      return a.username.toLowerCase().compareTo(b.username.toLowerCase());
    });

    return combinedUsers;
  }

  Future<List<ChatUserProfile>> _enrichWithMessageData(List<UserProfile> users) async {
    if (users.isEmpty) return [];

    try {
      // Create a map to store message data for each user
      final Map<String, Map<String, dynamic>> messageDataMap = {};

      // For each user, get their last message and unread count
      for (final user in users) {
        final chatId = _generateChatId(userId, user.user_id);

        try {
          // Get last message for this chat
          final lastMessageResponse = await _supabase
              .from('direct_messages')
              .select('id, content, created_at, sender_id, message_type')
              .eq('chat_id', chatId)
              .order('created_at', ascending: false)
              .limit(1);

          // Get unread count for messages from this user
          final unreadCountResponse = await _supabase
              .from('direct_messages')
              .select('id')
              .eq('chat_id', chatId)
              .eq('sender_id', user.user_id)
              .eq('is_read', false);

          final lastMessageData = lastMessageResponse as List;
          final unreadCountData = unreadCountResponse as List;

          String? lastMessage;
          DateTime? lastMessageTime;
          bool isLastMessageFromMe = false;
          String? lastMessageId;

          if (lastMessageData.isNotEmpty) {
            final messageData = lastMessageData.first;
            lastMessage = _formatMessageContent(
              messageData['content'] as String,
              messageData['message_type'] as String?,
            );
            lastMessageTime = DateTime.parse(messageData['created_at'] as String);
            isLastMessageFromMe = messageData['sender_id'] == userId;
            lastMessageId = messageData['id'] as String;
          }

          messageDataMap[user.user_id] = {
            'lastMessage': lastMessage,
            'lastMessageTime': lastMessageTime,
            'unreadCount': unreadCountData.length,
            'isLastMessageFromMe': isLastMessageFromMe,
            'lastMessageId': lastMessageId,
          };
        } catch (e) {
          print('Error fetching message data for user ${user.user_id}: $e');
          // Set default values if there's an error
          messageDataMap[user.user_id] = {
            'lastMessage': null,
            'lastMessageTime': null,
            'unreadCount': 0,
            'isLastMessageFromMe': false,
            'lastMessageId': null,
          };
        }
      }

      // Convert users to ChatUserProfile with message data
      final List<ChatUserProfile> chatUsers = users.map((user) {
        final messageData = messageDataMap[user.user_id] ?? {};
        return ChatUserProfile.fromUserProfile(
          user,
          lastMessage: messageData['lastMessage'],
          lastMessageTime: messageData['lastMessageTime'],
          unreadCount: messageData['unreadCount'] ?? 0,
          isLastMessageFromMe: messageData['isLastMessageFromMe'] ?? false,
          lastMessageId: messageData['lastMessageId'],
        );
      }).toList();

      // Sort by last message time (most recent first), then by activity
      chatUsers.sort((a, b) {
        // Users with messages should appear first
        if (a.lastMessageTime != null && b.lastMessageTime == null) {
          return -1;
        } else if (a.lastMessageTime == null && b.lastMessageTime != null) {
          return 1;
        } else if (a.lastMessageTime != null && b.lastMessageTime != null) {
          return b.lastMessageTime!.compareTo(a.lastMessageTime!);
        } else {
          // Both have no messages, sort by username
          return a.username.toLowerCase().compareTo(b.username.toLowerCase());
        }
      });

      return chatUsers;

    } catch (error) {
      print('Error enriching with message data: $error');
      // Return users without message data if there's an error
      return users.map((user) => ChatUserProfile.fromUserProfile(user)).toList();
    }
  }

  String _formatMessageContent(String content, String? messageType) {
    switch (messageType) {
      case 'image':
        return '📷 Image';
      case 'video':
        return '🎥 Video';
      case 'audio':
        return '🎵 Audio';
      case 'file':
        return '📎 File';
      default:
        return content;
    }
  }

  List<ChatUserProfile> _applyPagination(List<ChatUserProfile> allUsers, int offset, bool refresh) {
    if (refresh) {
      return allUsers.take(_pageSize).toList();
    } else {
      final existingUsers = state.users;
      final newUsers = allUsers.skip(offset).take(_pageSize).toList();

      // Merge and remove duplicates
      final Map<String, ChatUserProfile> uniqueUserMap = {};

      for (final user in existingUsers) {
        uniqueUserMap[user.user_id] = user;
      }

      for (final user in newUsers) {
        uniqueUserMap[user.user_id] = user;
      }

      return uniqueUserMap.values.toList();
    }
  }

  bool _isCacheValid() {
    if (state.lastFetched == null) return false;
    return DateTime.now().difference(state.lastFetched!) < _cacheTimeout;
  }

  String _getErrorMessage(dynamic error) {
    if (error is PostgrestException) {
      switch (error.code) {
        case '42P01':
          return 'Database table not found. Please contact support.';
        case '42703':
          return 'Invalid data structure. Please update the app.';
        default:
          return 'Database error: ${error.message}';
      }
    } else if (error.toString().contains('timeout')) {
      return 'Connection timeout. Please check your internet connection.';
    } else if (error.toString().contains('SocketException')) {
      return 'No internet connection. Please check your network.';
    } else {
      return 'Failed to load chats. Please try again.';
    }
  }

  Future<void> refresh() async {
    await fetchChatUsersWithMessages(refresh: true);
  }

  void clearError() {
    if (state.hasError) {
      state = state.copyWith(error: null);
    }
  }

  // Update specific user's message data (for real-time updates)
  void updateUserMessageData({
    required String userId,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isLastMessageFromMe,
  }) {
    final updatedUsers = state.users.map((user) {
      if (user.user_id == userId) {
        return user.copyWith(
          lastMessage: lastMessage,
          lastMessageTime: lastMessageTime,
          unreadCount: unreadCount,
          isLastMessageFromMe: isLastMessageFromMe,
        );
      }
      return user;
    }).toList();

    // Re-sort after update
    updatedUsers.sort((a, b) {
      if (a.lastMessageTime != null && b.lastMessageTime == null) {
        return -1;
      } else if (a.lastMessageTime == null && b.lastMessageTime != null) {
        return 1;
      } else if (a.lastMessageTime != null && b.lastMessageTime != null) {
        return b.lastMessageTime!.compareTo(a.lastMessageTime!);
      } else {
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      }
    });

    state = state.copyWith(users: updatedUsers);
  }

  void markMessagesAsRead(String otherUserId) {
    final updatedUsers = state.users.map((user) {
      if (user.user_id == otherUserId) {
        return user.copyWith(unreadCount: 0);
      }
      return user;
    }).toList();

    state = state.copyWith(users: updatedUsers);
  }

  void removeUserFromList(String userId) {
    final updatedUsers = state.users.where((user) => user.user_id != userId).toList();
    state = state.copyWith(users: updatedUsers);
  }
}

// Enhanced provider
final enhancedChatListProvider = StateNotifierProvider.family<EnhancedChatListNotifier, EnhancedChatListState, String>(
      (ref, userId) => EnhancedChatListNotifier(userId),
);

// Compatibility provider that wraps the enhanced provider for existing code
final chatListProvider = StateNotifierProvider.family<ChatListNotifierWrapper, ChatListState, String>(
      (ref, userId) => ChatListNotifierWrapper(ref, userId),
);

// Wrapper class to maintain compatibility with existing ChatListState
class ChatListNotifierWrapper extends StateNotifier<ChatListState> {
  final Ref _ref;
  final String _userId;
  late final EnhancedChatListNotifier _enhancedNotifier;

  ChatListNotifierWrapper(this._ref, this._userId) : super(const ChatListState()) {
    _enhancedNotifier = _ref.read(enhancedChatListProvider(_userId).notifier);

    // Listen to enhanced state changes and convert them
    _ref.listen(enhancedChatListProvider(_userId), (previous, next) {
      state = ChatListState(
        users: next.users.map((chatUser) => chatUser as UserProfile).toList(),
        isLoading: next.isLoading,
        isRefreshing: next.isRefreshing,
        error: next.error,
        hasMore: next.hasMore,
        lastFetched: next.lastFetched,
      );
    });
  }

  Future<void> fetchChatUsers({bool refresh = false}) async {
    await _enhancedNotifier.fetchChatUsersWithMessages(refresh: refresh);
  }

  Future<void> refresh() async {
    await _enhancedNotifier.refresh();
  }

  void clearError() {
    _enhancedNotifier.clearError();
  }

  void updateUserInList(UserProfile updatedUser) {
    // Convert to ChatUserProfile and update
    final existingChatUser = _enhancedNotifier.state.users
        .firstWhere((u) => u.user_id == updatedUser.user_id,
        orElse: () => ChatUserProfile.fromUserProfile(updatedUser));

    final updatedChatUser = ChatUserProfile.fromUserProfile(
      updatedUser,
      lastMessage: existingChatUser.lastMessage,
      lastMessageTime: existingChatUser.lastMessageTime,
      unreadCount: existingChatUser.unreadCount,
      isLastMessageFromMe: existingChatUser.isLastMessageFromMe,
    );

    final updatedUsers = _enhancedNotifier.state.users.map((user) {
      return user.user_id == updatedUser.user_id ? updatedChatUser : user;
    }).toList();

    _enhancedNotifier.state = _enhancedNotifier.state.copyWith(users: updatedUsers);
  }

  void removeUserFromList(String userId) {
    _enhancedNotifier.removeUserFromList(userId);
  }
}

// Keep existing state classes for backwards compatibility
class ChatListState {
  final List<UserProfile> users;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final bool hasMore;
  final DateTime? lastFetched;

  const ChatListState({
    this.users = const [],
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.hasMore = true,
    this.lastFetched,
  });

  ChatListState copyWith({
    List<UserProfile>? users,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool? hasMore,
    DateTime? lastFetched,
  }) {
    return ChatListState(
      users: users ?? this.users,
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      error: error,
      hasMore: hasMore ?? this.hasMore,
      lastFetched: lastFetched ?? this.lastFetched,
    );
  }

  bool get isEmpty => users.isEmpty && !isLoading;
  bool get hasError => error != null;
  bool get shouldShowLoading => isLoading && users.isEmpty;
}