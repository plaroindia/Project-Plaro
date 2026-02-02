import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Model/user_profile.dart';

// Provider for managing user profile state
final setProfileProvider = StateNotifierProvider<SetProfileNotifier, AsyncValue<UserProfile?>>((ref) {
  return SetProfileNotifier();
});

class SetProfileNotifier extends StateNotifier<AsyncValue<UserProfile?>> {
  SetProfileNotifier() : super(const AsyncValue.data(null));

  final SupabaseClient _supabase = Supabase.instance.client;

  // Create or update user profile
  Future<void> saveProfile({
    required String user_id,
    required String username,
    String? email,
    String? role,
    String? profilePic,
    String? bio,
    String? study,
    String? location,
    int? streakCount,
    int? followersCount,
    int? followingCount,
    bool? isVerified,
  }) async {
    state = const AsyncValue.loading();

    try {
      // Check if user_profiles table exists, create if not
      await _ensureTableExists();

      // Create UserProfile object
      final userProfile = UserProfile(
        user_id: user_id,
        username: username,
        email: email,
        role: role,
        profilePic: profilePic,
        bio: bio,
        study: study,
        location: location,
        streakCount: streakCount ?? 0,
        followersCount: followersCount ?? 0,
        followingCount: followingCount ?? 0,
        createdAt: DateTime.now(),
        isVerified: isVerified ?? false,
      );

      // Check if profile exists
      final existingProfile = await _supabase
          .from('user_profiles')
          .select()
          .eq('user_id', user_id)
          .maybeSingle();

      if (existingProfile == null) {
        // Create new profile
        await _supabase.from('user_profiles').insert({
          'user_id': userProfile.user_id,
          'username': userProfile.username,
          'email': userProfile.email,
          'role': userProfile.role,
          'profile_pic': userProfile.profilePic,
          'bio': userProfile.bio,
          'study': userProfile.study,
          'location': userProfile.location,
          'streak_count': userProfile.streakCount,
          'followers_count': userProfile.followersCount,
          'following_count': userProfile.followingCount,
          'created_at': userProfile.createdAt?.toIso8601String(),
          'is_verified': userProfile.isVerified,
        });
      } else {
        // Update existing profile
        await _supabase.from('user_profiles').update({
          'username': userProfile.username,
          'email': userProfile.email,
          'role': userProfile.role,
          'profile_pic': userProfile.profilePic,
          'bio': userProfile.bio,
          'study': userProfile.study,
          'location': userProfile.location,
          'streak_count': userProfile.streakCount,
          'followers_count': userProfile.followersCount,
          'following_count': userProfile.followingCount,
          'is_verified': userProfile.isVerified,
        }).eq('user_id', user_id);
      }

      state = AsyncValue.data(userProfile);
    } catch (error) {
      state = AsyncValue.error(error, StackTrace.current);
      rethrow;
    }
  }

// Get user profile
  Future<void> getUserProfile(String user_id) async {
    state = const AsyncValue.loading();

    try {
      final response = await _supabase
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
          .eq('user_id', user_id)
          .maybeSingle();

      if (response != null) {
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

        // Use fromJson instead of manual construction
        final userProfile = UserProfile.fromJson(profileData);
        state = AsyncValue.data(userProfile);
      } else {
        state = const AsyncValue.data(null);
      }
    } catch (error) {
      state = AsyncValue.error(error, StackTrace.current);
    }
  }

  // Ensure the user_profiles table exists
  Future<void> _ensureTableExists() async {
    try {
      // Try to query the table to check if it exists
      await _supabase.from('user_profiles').select('user_id').limit(1);
    } catch (error) {
      // If table doesn't exist, create it
      // Note: In production, you should create tables through Supabase dashboard
      // or migration scripts. This is just for development purposes.
      throw Exception('user_profiles table does not exist. Please create it in Supabase dashboard with the following columns:\n'
          '- user_id (text, primary key)\n'
          '- username (text, not null)\n'
          '- email (text)\n'
          '- role (text)\n'
          '- profile_pic (text)\n'
          '- bio (text)\n'
          '- study (text)\n'
          '- location (text)\n'
          '- streak_count (integer, default 0)\n'
          '- followers_count (integer, default 0)\n'
          '- following_count (integer, default 0)\n'
          '- created_at (timestamp with time zone, default now())\n'
          '- is_verified (boolean, default false)');
    }
  }

  // Reset state
  void reset() {
    state = const AsyncValue.data(null);
  }

  void clearProfile() {
    // Reset to initial state - adjust this based on your actual state structure
    state = const AsyncValue.data(null); // or whatever your initial state is
  }
}