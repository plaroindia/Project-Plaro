import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import 'auth_provider.dart';

// Provider for current authenticated user (from Supabase Auth)
final currentAuthUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (session) => session?.user,
    loading: () => null,
    error: (error, stack) => null,
  );
});

// Provider for current user ID - convenience provider for just the ID
final currentUserIdProvider = Provider<String?>((ref) {
  final user = ref.watch(currentAuthUserProvider);
  return user?.id;
});


// Provider for fetching UserProfile from database
final userProfileProvider = FutureProvider.family<UserProfile?, String>((ref, userId) async {
  try {
    debugPrint('Fetching user profile for userId: $userId');

    final response = await Supabase.instance.client
        .from('user_profiles')
        .select('''
          *,
          user_profile_rank(
            total_points,
            rank_level,
            consistency_score,
            authenticity_score,
            contribution_score,
            freelance_eligible,
            verified_educator
          )
        ''')
        .eq('user_id', userId)
        .maybeSingle();

    if (response == null) {
      debugPrint('No user profile found for userId: $userId');
      return null;
    }

    final profileData = {
      ...response,
      if (response['user_profile_rank'] != null) ...{
        'total_points': response['user_profile_rank']['total_points'],
        'rank_level': response['user_profile_rank']['rank_level'],
        'consistency_score': response['user_profile_rank']['consistency_score'],
        'authenticity_score': response['user_profile_rank']['authenticity_score'],
        'contribution_score': response['user_profile_rank']['contribution_score'],
        'freelance_eligible': response['user_profile_rank']['freelance_eligible'],
        'verified_educator': response['user_profile_rank']['verified_educator'],
      }
    };

    debugPrint('User profile fetched successfully: ${response['username']}');
    return UserProfile.fromJson(response);

  } catch (e) {
    debugPrint('Error fetching user profile: $e');
    throw Exception('Failed to fetch user profile: $e');
  }
});

// Provider for current user's profile - combines auth user and profile data
final currentUserProfileProvider = Provider<AsyncValue<UserProfile?>>((ref) {
  final userId = ref.watch(currentUserIdProvider);

  if (userId == null) {
    return const AsyncValue.data(null);
  }

  return ref.watch(userProfileProvider(userId));
});

// Repository class for user profile operations
final userProfileRepositoryProvider = Provider((ref) {
  return UserProfileRepository(ref);
});

class UserProfileRepository {
  final Ref ref;
  UserProfileRepository(this.ref);

  // Fetch user profile by ID
  // Fetch user profile by ID
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      //  Join with user_profile_rank
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('''
          *,
          user_profile_rank(
            total_points,
            rank_level,
            consistency_score,
            authenticity_score,
            contribution_score,
            freelance_eligible,
            verified_educator
          )
        ''')
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;

      // Flatten the nested rank data
      final profileData = {
        ...response,
        if (response['user_profile_rank'] != null) ...{
          'total_points': response['user_profile_rank']['total_points'],
          'rank_level': response['user_profile_rank']['rank_level'],
          'consistency_score': response['user_profile_rank']['consistency_score'],
          'authenticity_score': response['user_profile_rank']['authenticity_score'],
          'contribution_score': response['user_profile_rank']['contribution_score'],
          'freelance_eligible': response['user_profile_rank']['freelance_eligible'],
          'verified_educator': response['user_profile_rank']['verified_educator'],
        }
      };

      return UserProfile.fromJson(profileData);
    } catch (e) {
      debugPrint('Error fetching user profile: $e');
      rethrow;
    }
  }
  // Update user profile
  Future<UserProfile> updateUserProfile(UserProfile profile) async {
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .update(profile.toJson())
          .eq('user_id', profile.user_id)
          .select()
          .single();

      // Invalidate the cache to trigger a refresh
      ref.invalidate(userProfileProvider(profile.user_id));

      return UserProfile.fromJson(response);
    } catch (e) {
      debugPrint('Error updating user profile: $e');
      rethrow;
    }
  }


  // Create user profile
  Future<UserProfile> createUserProfile(UserProfile profile) async {
    try {
      final response = await Supabase.instance.client
          .from('user_profiles')
          .insert(profile.toJson())
          .select()
          .single();

      return UserProfile.fromJson(response);
    } catch (e) {
      debugPrint('Error creating user profile: $e');
      rethrow;
    }
  }

  // Delete user profile
  Future<void> deleteUserProfile(String userId) async {
    try {
      await Supabase.instance.client
          .from('user_profiles')
          .delete()
          .eq('user_id', userId);

      // Invalidate the cache
      ref.invalidate(userProfileProvider(userId));
    } catch (e) {
      debugPrint('Error deleting user profile: $e');
      rethrow;
    }
  }
}

// Convenience providers for specific user profile fields
final currentUsernameProvider = Provider<String?>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.when(
    data: (profile) => profile?.username,
    loading: () => null,
    error: (error, stack) => null,
  );
});

// Returns empty string instead of null so callers can use it as String directly.
final currentUserEmailProvider = Provider<String>((ref) {
  // Prefer the live auth email (always up-to-date after session refresh)
  // and fall back to the DB profile email.
  final authEmail =
      Supabase.instance.client.auth.currentUser?.email ?? '';
  if (authEmail.isNotEmpty) return authEmail;

  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.when(
    data: (profile) => profile?.email ?? '',
    loading: () => '',
    error: (error, stack) => '',
  );
});

final currentUserRoleProvider = Provider<String?>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.when(
    data: (profile) => profile?.role,
    loading: () => null,
    error: (error, stack) => null,
  );
});

final currentUserProfilePicProvider = Provider<String?>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  return profileAsync.when(
    data: (profile) => profile?.profilePic,
    loading: () => null,
    error: (error, stack) => null,
  );
});

// Extension to make it easier to use throughout your app
extension UserProviderExtension on WidgetRef {
  // Auth user (from Supabase Auth)
  User? get currentAuthUser => watch(currentAuthUserProvider);
  String? get currentUserId => watch(currentUserIdProvider);

  // User profile (from your database)
  AsyncValue<UserProfile?> get currentUserProfile => watch(currentUserProfileProvider);
  String? get currentUsername => watch(currentUsernameProvider);
  String get currentUserEmail => watch(currentUserEmailProvider);
  String? get currentUserRole => watch(currentUserRoleProvider);
  String? get currentUserProfilePic => watch(currentUserProfilePicProvider);
}