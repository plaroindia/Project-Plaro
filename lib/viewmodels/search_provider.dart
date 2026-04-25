import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_profile.dart';

final searchProfileProvider = StateNotifierProvider<SearchProfileNotifier, AsyncValue<List<UserProfile>>>((ref) {
  return SearchProfileNotifier();
});

class SearchProfileNotifier extends StateNotifier<AsyncValue<List<UserProfile>>> {
  SearchProfileNotifier() : super(const AsyncValue.data([]));

  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> searchUsers(String query) async {
    // If query is empty, clear results
    if (query.trim().isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();

    try {
      // Search users by username and location with case-insensitive matching
      final response = await _supabase
          .from('user_profiles')
          .select()
          .or('username.ilike.%$query%,location.ilike.%$query%,bio.ilike.%$query%,study.ilike.%$query%')
          .order('username', ascending: true) // Sort by username
          .order('location', ascending: true) // Then by location
          .limit(50); // Limit results for performance

      final List<UserProfile> users = response.map<UserProfile>((userMap) {
        return UserProfile(
          user_id: userMap['user_id'],
          username: userMap['username'],
          email: userMap['email'],
          role: userMap['role'],
          profilePic: userMap['profile_pic'],
          bio: userMap['bio'],
          study: userMap['study'],
          location: userMap['location'],
          streakCount: userMap['streak_count'],
          followersCount: userMap['followers_count'],
          followingCount: userMap['following_count'],
          createdAt: userMap['created_at'] != null
              ? DateTime.parse(userMap['created_at'])
              : null,
          isVerified: userMap['is_verified'] ?? false,
        );
      }).toList();

      state = AsyncValue.data(users);
    } catch (error) {
      state = AsyncValue.error(error, StackTrace.current);
    }
  }

  Future<void> getUserProfile(String userId) async {
    state = const AsyncValue.loading();

    try {
      final response = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        final userProfile = UserProfile(
          user_id: response['user_id'],
          username: response['username'],
          email: response['email'],
          role: response['role'],
          profilePic: response['profile_pic'],
          bio: response['bio'],
          study: response['study'],
          location: response['location'],
          streakCount: response['streak_count'],
          followersCount: response['followers_count'],
          followingCount: response['following_count'],
          createdAt: response['created_at'] != null
              ? DateTime.parse(response['created_at'])
              : null,
          isVerified: response['is_verified'] ?? false,
        );
        state = AsyncValue.data([userProfile]);
      } else {
        state = const AsyncValue.data([]);
      }
    } catch (error) {
      state = AsyncValue.error(error, StackTrace.current);
    }
  }

  void clearSearch() {
    state = const AsyncValue.data([]);
  }
}