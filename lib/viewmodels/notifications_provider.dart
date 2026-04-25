// ================================================================
// notifications_provider.dart
//
// Handles:
//   - Fetching paginated notifications for the current user
//   - Supabase Realtime subscription for live badge updates
//   - Mark as read (single + mark all)
//   - Inserting notifications (used by follow_provider, rating providers)
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_provider.dart';

// ── Model ────────────────────────────────────────────────────

class AppNotification {
  final String id;
  final String userId;
  final String type; // follow | new_post | new_byte | new_taiken | rating | points | match | system | dm
  final String title;
  final String body;
  final String? relatedType;
  final String? relatedId;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.relatedType,
    this.relatedId,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    return AppNotification(
      id: m['notification_id'] as String,
      userId: m['user_id'] as String,
      type: m['type'] as String,
      title: m['title'] as String,
      body: m['body'] as String,
      relatedType: m['related_type'] as String?,
      relatedId: m['related_id'] as String?,
      isRead: m['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      body: body,
      relatedType: relatedType,
      relatedId: relatedId,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

// ── State ────────────────────────────────────────────────────

class NotificationsState {
  final List<AppNotification> notifications;
  final int unreadCount;
  final bool isLoading;
  final String? error;

  const NotificationsState({
    this.notifications = const [],
    this.unreadCount = 0,
    this.isLoading = false,
    this.error,
  });

  NotificationsState copyWith({
    List<AppNotification>? notifications,
    int? unreadCount,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return NotificationsState(
      notifications: notifications ?? this.notifications,
      unreadCount: unreadCount ?? this.unreadCount,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ── Notifier ─────────────────────────────────────────────────

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;

  NotificationsNotifier() : super(const NotificationsState());

  String? get _userId => _supabase.auth.currentUser?.id;

  // Call this once when user is authenticated (e.g., in navCard initState)
  Future<void> init() async {
    if (_userId == null) return;
    await _loadNotifications();
    _subscribeRealtime();
  }

  Future<void> _loadNotifications() async {
    if (_userId == null) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final rows = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', _userId!)
          .order('created_at', ascending: false)
          .limit(50);

      final notifications = (rows as List)
          .map((r) => AppNotification.fromMap(r))
          .toList();

      final unread = notifications.where((n) => !n.isRead).length;

      state = state.copyWith(
        notifications: notifications,
        unreadCount: unread,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[Notifications] load error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  // Supabase Realtime — listens for INSERT on notifications for this user.
  // Badge count updates live without polling.
  void _subscribeRealtime() {
    if (_userId == null) return;

    _channel?.unsubscribe();

    _channel = _supabase
        .channel('notifications:${_userId!}')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: _userId!,
      ),
      callback: (payload) {
        try {
          final newNotif =
          AppNotification.fromMap(payload.newRecord);
          // Prepend to list, bump unread count
          state = state.copyWith(
            notifications: [newNotif, ...state.notifications],
            unreadCount: state.unreadCount + 1,
          );
        } catch (e) {
          debugPrint('[Notifications] realtime parse error: $e');
        }
      },
    )
        .subscribe();
  }

  // Mark a single notification as read
  Future<void> markRead(String notificationId) async {
    // Optimistic update
    final updated = state.notifications.map((n) {
      if (n.id == notificationId && !n.isRead) {
        return n.copyWith(isRead: true);
      }
      return n;
    }).toList();

    final wasUnread =
    state.notifications.any((n) => n.id == notificationId && !n.isRead);

    state = state.copyWith(
      notifications: updated,
      unreadCount:
      wasUnread ? (state.unreadCount - 1).clamp(0, 999) : state.unreadCount,
    );

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('notification_id', notificationId);
    } catch (e) {
      debugPrint('[Notifications] markRead error: $e');
    }
  }

  // Mark all as read
  Future<void> markAllRead() async {
    if (_userId == null || state.unreadCount == 0) return;

    // Optimistic update
    final updated =
    state.notifications.map((n) => n.copyWith(isRead: true)).toList();
    state = state.copyWith(notifications: updated, unreadCount: 0);

    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _userId!)
          .eq('is_read', false);
    } catch (e) {
      debugPrint('[Notifications] markAllRead error: $e');
    }
  }

  // Refresh manually (pull-to-refresh)
  Future<void> refresh() => _loadNotifications();

  // ── Static helper: insert a notification ─────────────────
  // Called from follow_provider, rating providers, etc.
  // Uses a static method so call sites don't need a ref.
  static Future<void> insert({
    required String targetUserId,
    required String type,
    required String title,
    required String body,
    String? relatedType,
    String? relatedId,
  }) async {
    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': targetUserId,
        'type': type,
        'title': title,
        'body': body,
        if (relatedType != null) 'related_type': relatedType,
        if (relatedId != null) 'related_id': relatedId,
      });
    } catch (e) {
      // Non-fatal — notifications should never crash the main flow
      debugPrint('[Notifications] insert error: $e');
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────

final notificationsProvider =
StateNotifierProvider<NotificationsNotifier, NotificationsState>(
      (ref) {
    final notifier = NotificationsNotifier();
    // Auto-init when auth user is available
    final session = ref.watch(authStateProvider).valueOrNull;
    if (session?.user != null) {
      notifier.init();
    }
    return notifier;
  },
);

// Convenience: just the unread count for the badge
final unreadNotifCountProvider = Provider<int>(
      (ref) => ref.watch(notificationsProvider).unreadCount,
);