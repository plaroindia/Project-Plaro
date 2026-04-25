import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';
import 'post_rating_provider.dart';
import 'account_switcher_provider.dart';

final supAuthProv = Provider((ref) => Supabase.instance.client.auth);

final authStateProvider = StreamProvider((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map(
        (event) => event.session,
  );
});

final authControllerProvider = Provider((ref) {
  return AuthController(ref);
});

class AuthController {
  final Ref ref;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    serverClientId: AppConfig.googleSignInServerClientId,
  );

  AuthController(this.ref);

  Future<bool> login({required String email, required String password}) async {
    try {
      final response = await ref
          .read(supAuthProv)
          .signInWithPassword(email: email, password: password);

      return response.session != null;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  /// Email Signup with OTP
  Future<Map<String, dynamic>> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      // ✅ Call Edge Function with password to create user and send OTP
      final response = await Supabase.instance.client.functions.invoke(
        'send-otp',
        body: {
          'email': email,
          'password': password, // ✅ Include password
          'purpose': 'signup',
        },
      );

      if (response.data['success'] == true) {
        return {
          'success': true,
          'userId': response.data['userId'],
          'requiresVerification': true,
        };
      } else {
        throw Exception(response.data['error'] ?? 'Signup failed');
      }
    } catch (e) {
      debugPrint('Signup error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Google Sign-In with onboarding check
  Future<Map<String, dynamic>> googleSignIn() async {
    try {
      await _googleSignIn.signOut();

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return {'success': false, 'cancelled': true};
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception('Failed to get Google ID token');
      }

      final response = await ref
          .read(supAuthProv)
          .signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.session != null) {
        // Check if this is a new user by checking metadata
        final user = response.user;
        final isNewUser = user?.userMetadata?['onboarding_complete'] == null;

        if (isNewUser) {
          // Set initial metadata
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(
              data: {'onboarding_complete': false},
            ),
          );
        }

        // Register this account in the switcher list so it shows up immediately
        // Use a microtask to avoid blocking the return value
        Future.microtask(
              () => ref.read(accountSwitcherProvider.notifier).saveCurrentAccount(),
        );

        return {
          'success': true,
          'isNewUser': isNewUser,
          'requiresOnboarding': !_checkOnboardingComplete(user),
        };
      }

      return {'success': false, 'error': 'No session created'};
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check if onboarding is complete
  bool _checkOnboardingComplete(User? user) {
    if (user == null) return false;

    // Check user metadata
    final metadata = user.userMetadata?['onboarding_complete'];
    return metadata == true;
  }

  /// Check onboarding status (public method)
  Future<bool> isOnboardingComplete() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return false;

      // Also check database for redundancy
      final response = await Supabase.instance.client
          .from('user_profiles')
          .select('onboarding_complete')
          .eq('user_id', user.id)
          .maybeSingle();

      return response?['onboarding_complete'] == true;
    } catch (e) {
      debugPrint('Error checking onboarding: $e');
      return false;
    }
  }

  /// Mark onboarding as complete
  Future<void> completeOnboarding() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('No user logged in');

      // Update metadata
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {'onboarding_complete': true},
        ),
      );

      // Also update database
      await Supabase.instance.client
          .from('user_profiles')
          .update({'onboarding_complete': true})
          .eq('user_id', user.id);

      debugPrint('Onboarding completed');
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await ref.read(supAuthProv).signOut();
      debugPrint('User logged out from Supabase');

      // Also disconnect from Google to clear session cache
      await _googleSignIn.signOut();
      await _googleSignIn.disconnect();
      debugPrint('Google session disconnected');

      // Belt-and-suspenders: explicitly bust the role cache so the next user
      // never sees a stale professional/educator status from the previous session.
      // The primary fix is that isVerifiedProfessionalProvider watches
      // authStateProvider, but this handles any edge-cases (e.g. token expiry
      // or navigation flows that bypass the stream).
      ref.invalidate(isVerifiedProfessionalProvider);
      debugPrint('Role provider cache cleared');
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }
}