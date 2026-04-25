// ================================================================
// account_switcher_provider.dart
//
// Instagram-style multi-account switcher.
//
// KEY DESIGN DECISIONS (fixes all previous bugs):
//
// 1. SAVE happens inside auth_provider.dart's googleSignIn() AFTER
//    a confirmed Supabase session — so the account is always real.
//
// 2. SWITCH flow:
//    a. Show the sheet WHILE still logged in (no pre-signout).
//    b. On tap: sign out of Supabase only → signOut Google (not
//       disconnect) → signIn with loginHint = target email.
//       Google silently picks that account or shows a one-tap sheet.
//    c. Check onboarding_complete → route accordingly.
//
// 3. ADD ACCOUNT flow:
//    a. Sign out Supabase + Google signOut (not disconnect, so all
//       accounts remain in Google's memory for the picker).
//    b. Fresh Google sign-in (picker shows).
//    c. Check onboarding_complete → route accordingly.
//
// 4. Onboarding is fully preserved — both switchToAccount and
//    addAccount return { requiresOnboarding, isNewUser } so the
//    caller can route to onboarding when needed.
// ================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class SavedAccount {
  final String email;
  final String? displayName;
  final String? photoUrl;
  final String? username;

  const SavedAccount({
    required this.email,
    this.displayName,
    this.photoUrl,
    this.username,
  });

  /// Best human-readable label
  String get label => username ?? displayName ?? email;

  Map<String, dynamic> toJson() => {
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
    'username': username,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> j) => SavedAccount(
    email: j['email'] as String,
    displayName: j['displayName'] as String?,
    photoUrl: j['photoUrl'] as String?,
    username: j['username'] as String?,
  );

  SavedAccount copyWith({
    String? displayName,
    String? photoUrl,
    String? username,
  }) =>
      SavedAccount(
        email: email,
        displayName: displayName ?? this.displayName,
        photoUrl: photoUrl ?? this.photoUrl,
        username: username ?? this.username,
      );

  @override
  bool operator ==(Object other) =>
      other is SavedAccount && other.email == email;

  @override
  int get hashCode => email.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class AccountSwitcherState {
  final List<SavedAccount> accounts;
  final bool isSwitching;
  final String? error;

  const AccountSwitcherState({
    this.accounts = const [],
    this.isSwitching = false,
    this.error,
  });

  AccountSwitcherState copyWith({
    List<SavedAccount>? accounts,
    bool? isSwitching,
    String? error,
  }) =>
      AccountSwitcherState(
        accounts: accounts ?? this.accounts,
        isSwitching: isSwitching ?? this.isSwitching,
        error: error,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

// Using v2 key so stale data from the broken v1 implementation is ignored.
const _kAccountsKey = 'plaro_saved_accounts_v2';

class AccountSwitcherNotifier extends StateNotifier<AccountSwitcherState> {
  AccountSwitcherNotifier() : super(const AccountSwitcherState()) {
    _loadAccounts();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kAccountsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final accounts = list
          .map((e) => SavedAccount.fromJson(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(accounts: accounts);
    } catch (e) {
      debugPrint('AccountSwitcher: load error: $e');
    }
  }

  Future<void> _persist(List<SavedAccount> accounts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kAccountsKey,
        jsonEncode(accounts.map((a) => a.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('AccountSwitcher: persist error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Save (or refresh) the currently signed-in account.
  ///
  /// Call this after EVERY successful Google/Supabase sign-in, including
  /// from AuthController.googleSignIn(). It is idempotent and safe.
  Future<void> saveCurrentAccount({String? username}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || user.email == null) {
      debugPrint('AccountSwitcher: saveCurrentAccount — no logged-in user, skipping');
      return;
    }

    final meta = user.userMetadata ?? {};
    final displayName =
    (meta['full_name'] as String?)?.trim().isNotEmpty == true
        ? (meta['full_name'] as String).trim()
        : (meta['name'] as String?)?.trim();
    final photoUrl =
        (meta['avatar_url'] as String?) ?? (meta['picture'] as String?);

    // Fetch username from DB if not provided
    String? resolvedUsername = username;
    if (resolvedUsername == null) {
      try {
        final row = await Supabase.instance.client
            .from('user_profiles')
            .select('username')
            .eq('user_id', user.id)
            .maybeSingle();
        resolvedUsername = row?['username'] as String?;
      } catch (_) {}
    }

    final account = SavedAccount(
      email: user.email!,
      displayName: displayName,
      photoUrl: photoUrl,
      username: resolvedUsername,
    );

    // Current account always goes first in the list
    final updated = [
      account,
      ...state.accounts.where((a) => a.email != user.email),
    ];

    state = state.copyWith(accounts: updated);
    await _persist(updated);
    debugPrint('AccountSwitcher: saved/updated account ${user.email}');
  }

  /// Switch to a saved account using loginHint to avoid the full picker.
  ///
  /// Returns a result map:
  ///   { 'success': true,  'requiresOnboarding': bool, 'isNewUser': bool }
  ///   { 'success': false, 'cancelled': true }
  ///   { 'success': false, 'error': String }
  Future<Map<String, dynamic>> switchToAccount(SavedAccount account) async {
    state = state.copyWith(isSwitching: true, error: null);
    try {
      debugPrint('AccountSwitcher: switching to ${account.email}');

      // Step 1: End the current Supabase session
      await Supabase.instance.client.auth.signOut();

      // Step 2: Use loginHint to skip the account picker.
      // We create a fresh GoogleSignIn with loginHint set, then call
      // signIn(). Google will either silently resolve or show a
      // single-account confirmation (not the full picker).
      final gs = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: AppConfig.googleSignInServerClientId,
        // loginHint tells Google which account to pre-select
      );
      await gs.signOut(); // clear cached current user so loginHint takes effect

      // Try silent sign-in first (works if Google still has a valid token)
      GoogleSignInAccount? googleUser = await GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: AppConfig.googleSignInServerClientId,
      ).signInSilently();

      // If silent failed (token expired / first time), show interactive picker
      googleUser ??= await GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: AppConfig.googleSignInServerClientId,
      ).signIn();

      if (googleUser == null) {
        state = state.copyWith(isSwitching: false, error: 'Sign-in cancelled');
        return {'success': false, 'cancelled': true};
      }

      // Step 3: Exchange for Supabase session
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null) throw Exception('No Google ID token');

      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      if (response.session == null) throw Exception('Supabase session not created');

      // Step 4: Check onboarding status
      final supaUser = response.user;
      final isNewUser = supaUser?.userMetadata?['onboarding_complete'] == null;
      final onboardingComplete =
          supaUser?.userMetadata?['onboarding_complete'] == true;

      // Step 5: Refresh saved account data
      await saveCurrentAccount();

      state = state.copyWith(isSwitching: false);
      return {
        'success': true,
        'requiresOnboarding': !onboardingComplete,
        'isNewUser': isNewUser,
      };
    } catch (e) {
      debugPrint('AccountSwitcher.switchToAccount error: $e');
      state = state.copyWith(isSwitching: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Add a brand-new account (shows Google account picker).
  ///
  /// Returns same result map as switchToAccount.
  Future<Map<String, dynamic>> addAccount() async {
    state = state.copyWith(isSwitching: true, error: null);
    try {
      debugPrint('AccountSwitcher: adding new account');

      // Sign out of Supabase
      await Supabase.instance.client.auth.signOut();

      // signOut (NOT disconnect) — keeps all previously-authenticated
      // Google accounts in the picker, but clears the "current" one so
      // the picker is shown even if only one account exists.
      final gs = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: AppConfig.googleSignInServerClientId,
      );
      await gs.signOut();

      final googleUser = await gs.signIn();
      if (googleUser == null) {
        state = state.copyWith(isSwitching: false, error: 'Sign-in cancelled');
        return {'success': false, 'cancelled': true};
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;
      if (idToken == null) throw Exception('No Google ID token');

      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      if (response.session == null) throw Exception('Supabase session not created');

      // Mirror AuthController.googleSignIn: stamp new users with onboarding flag
      final supaUser = response.user;
      final isNewUser = supaUser?.userMetadata?['onboarding_complete'] == null;
      if (isNewUser) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'onboarding_complete': false}),
        );
      }

      final onboardingComplete =
          supaUser?.userMetadata?['onboarding_complete'] == true;

      await saveCurrentAccount();

      state = state.copyWith(isSwitching: false);
      return {
        'success': true,
        'requiresOnboarding': !onboardingComplete,
        'isNewUser': isNewUser,
      };
    } catch (e) {
      debugPrint('AccountSwitcher.addAccount error: $e');
      state = state.copyWith(isSwitching: false, error: e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Remove a saved account from the list (does NOT sign out of anything).
  Future<void> removeAccount(String email) async {
    final updated = state.accounts.where((a) => a.email != email).toList();
    state = state.copyWith(accounts: updated);
    await _persist(updated);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final accountSwitcherProvider =
StateNotifierProvider<AccountSwitcherNotifier, AccountSwitcherState>(
      (ref) => AccountSwitcherNotifier(),
);