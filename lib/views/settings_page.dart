import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../Viewmodels/auth_provider.dart';
import '../Viewmodels/user_provider.dart';
import '../Viewmodels/theme_provider.dart';
import 'login_page.dart';
import 'set_profile.dart';
import 'OTPVerificationPage.dart';
import 'legal_page.dart';

// ─── Settings state ───────────────────────────────────────────────────────────
class _SettingsState {
  final bool pushNotifications;
  final bool emailNotifications;
  final bool privateAccount;
  final bool showActivityStatus;
  final bool loaded;

  const _SettingsState({
    this.pushNotifications = true,
    this.emailNotifications = false,
    this.privateAccount = false,
    this.showActivityStatus = true,
    this.loaded = false,
  });

  _SettingsState copyWith({
    bool? pushNotifications,
    bool? emailNotifications,
    bool? privateAccount,
    bool? showActivityStatus,
    bool? loaded,
  }) =>
      _SettingsState(
        pushNotifications: pushNotifications ?? this.pushNotifications,
        emailNotifications: emailNotifications ?? this.emailNotifications,
        privateAccount: privateAccount ?? this.privateAccount,
        showActivityStatus: showActivityStatus ?? this.showActivityStatus,
        loaded: loaded ?? this.loaded,
      );
}

class _SettingsNotifier extends StateNotifier<_SettingsState> {
  _SettingsNotifier() : super(const _SettingsState());

  Future<void> loadOnce() async {
    if (state.loaded) return;
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final row = await Supabase.instance.client
          .from('user_profiles')
          .select('push_notifications, email_notifications, private_account, show_activity_status')
          .eq('user_id', uid)
          .maybeSingle();
      state = _SettingsState(
        pushNotifications: row?['push_notifications'] ?? true,
        emailNotifications: row?['email_notifications'] ?? false,
        privateAccount: row?['private_account'] ?? false,
        showActivityStatus: row?['show_activity_status'] ?? true,
        loaded: true,
      );
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> toggle(String field, bool value) async {
    switch (field) {
      case 'push_notifications': state = state.copyWith(pushNotifications: value); break;
      case 'email_notifications': state = state.copyWith(emailNotifications: value); break;
      case 'private_account': state = state.copyWith(privateAccount: value); break;
      case 'show_activity_status': state = state.copyWith(showActivityStatus: value); break;
    }
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      await Supabase.instance.client
          .from('user_profiles')
          .update({field: value}).eq('user_id', uid);
    } catch (e) {
      debugPrint('Settings toggle error: $e');
    }
  }
}

final settingsProvider =
StateNotifierProvider<_SettingsNotifier, _SettingsState>((_) => _SettingsNotifier());

// ─── Settings Page ────────────────────────────────────────────────────────────
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(settingsProvider.notifier).loadOnce());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final username = profileAsync.maybeWhen(data: (p) => p?.username ?? 'User', orElse: () => '...');
    final profilePic = profileAsync.maybeWhen(data: (p) => p?.profilePic, orElse: () => null);

    // FIX: Always read the live email from Supabase auth, not the cached provider.
    // The provider may lag after an email change because Supabase updates the auth
    // session asynchronously. auth.currentUser?.email is always up-to-date once the
    // session refreshes, and we force that refresh on email change success.
    final liveEmail = Supabase.instance.client.auth.currentUser?.email ?? '';
    // Fall back to provider email if auth hasn't hydrated yet (e.g. first load)
    final providerEmail = profileAsync.maybeWhen(data: (p) => p?.email ?? '', orElse: () => '');
    final displayEmail = liveEmail.isNotEmpty ? liveEmail : providerEmail;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings',
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // Profile card → opens SetProfile
          _ProfileCard(
            username: username, email: displayEmail, profilePic: profilePic, theme: theme,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SetProfile())),
          ),
          const SizedBox(height: 24),

          // _SectionLabel('Appearance', theme),
          // _ToggleTile(
          //   icon: themeMode == ThemeMode.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
          //   label: 'Dark Mode',
          //   value: themeMode == ThemeMode.dark,
          //   theme: theme,
          //   onChanged: (v) => ref.read(themeNotifierProvider.notifier).toggleTheme(v),
          // ),
          // const SizedBox(height: 20),

          _SectionLabel('Privacy', theme),
          _ToggleTile(
            icon: Icons.lock_person_outlined,
            label: 'Private Account',
            subtitle: 'Only followers can see your content',
            value: settings.privateAccount,
            theme: theme,
            onChanged: (v) => ref.read(settingsProvider.notifier).toggle('private_account', v),
          ),
          _ToggleTile(
            icon: Icons.radio_button_checked_outlined,
            label: 'Show Activity Status',
            subtitle: 'Let others see when you were last active',
            value: settings.showActivityStatus,
            theme: theme,
            onChanged: (v) => ref.read(settingsProvider.notifier).toggle('show_activity_status', v),
          ),
          const SizedBox(height: 20),

          _SectionLabel('Notifications', theme),
          _ToggleTile(
            icon: Icons.notifications_outlined,
            label: 'Push Notifications',
            value: settings.pushNotifications,
            theme: theme,
            onChanged: (v) => ref.read(settingsProvider.notifier).toggle('push_notifications', v),
          ),
          _ToggleTile(
            icon: Icons.mail_outline_rounded,
            label: 'Email Notifications',
            value: settings.emailNotifications,
            theme: theme,
            onChanged: (v) => ref.read(settingsProvider.notifier).toggle('email_notifications', v),
          ),
          const SizedBox(height: 20),

          _SectionLabel('Account', theme),
          _ActionTile(
            icon: Icons.lock_outline_rounded,
            label: 'Change Password',
            theme: theme,
            onTap: () => _sendPasswordResetOTP(context, theme, displayEmail),
          ),
          _ActionTile(
            icon: Icons.email_outlined,
            label: 'Change Email',
            subtitle: displayEmail.isNotEmpty ? displayEmail : null,
            theme: theme,
            onTap: () => _showChangeEmailSheet(context, theme),
          ),
          const SizedBox(height: 20),

          _SectionLabel('About', theme),
          _ActionTile(
            icon: Icons.help_outline_rounded,
            label: 'Help & FAQ',
            theme: theme,
            onTap: () => _launchUrl('https://plaro-website.vercel.app/contact.html'),
          ),
          _ActionTile(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            theme: theme,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LegalPage(showTerms: false))),
          ),
          _ActionTile(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            theme: theme,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LegalPage(showTerms: true))),
          ),
          const SizedBox(height: 20),

          _SectionLabel('Danger Zone', theme),
          _ActionTile(
            icon: Icons.delete_forever_outlined,
            label: 'Delete Account',
            labelColor: Colors.red,
            iconColor: Colors.red,
            theme: theme,
            onTap: () => _confirmDeleteAccount(context),
          ),
          const SizedBox(height: 36),
          Center(
            child: Text('Plaro v1.0.0',
                style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.2),
                    fontSize: 11, letterSpacing: 0.5)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Change Password via OTP ───────────────────────────────────────────────
  Future<void> _sendPasswordResetOTP(
      BuildContext context, ThemeData theme, String email) async {
    if (email.isEmpty) {
      _snack(context, 'No email on file', error: true);
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _Sheet(
        title: 'Change Password',
        theme: theme,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'We\'ll send a 6-digit verification code to:\n$email\n\nEnter the code on the next screen to set a new password.',
              style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 20),
            _PrimaryBtn(
              label: 'Send Code',
              loading: false,
              onPressed: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sending verification code…'),
          behavior: SnackBarBehavior.floating),
    );

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'send-otp',
        body: {'email': email, 'purpose': 'password_reset'},
      );
      if (response.data['success'] != true) {
        throw Exception(response.data['error'] ?? 'Failed to send code');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OTPVerificationPage(
              email: email,
              userId: response.data['userId'] ?? '',
              purpose: 'password_reset',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _snack(context, 'Error: $e', error: true);
      }
    }
  }

  // ── Change Email via OTP ──────────────────────────────────────────────────
  // FIX: Read the current email fresh from Supabase auth at call time, not
  // from a captured closure variable. This prevents the stale-email bug where
  // the old email is still shown / used after a successful change.
  void _showChangeEmailSheet(BuildContext context, ThemeData theme) {
    // Read live email right now, at the moment the sheet is opened.
    final currentEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';

    final emailCtrl = TextEditingController();
    bool loading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => _Sheet(
          title: 'Change Email',
          theme: theme,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter your new email address. A 6-digit code will be sent to your CURRENT email ($currentEmail) to confirm the change.',
                style: TextStyle(
                    color: theme.colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              _Field(label: 'New email address', ctrl: emailCtrl, theme: theme),
              const SizedBox(height: 20),
              _PrimaryBtn(
                label: 'Send Verification Code',
                loading: loading,
                onPressed: () async {
                  final newEmail = emailCtrl.text.trim();
                  if (!newEmail.contains('@')) {
                    _snack(ctx, 'Enter a valid email', error: true);
                    return;
                  }
                  if (newEmail.toLowerCase() == currentEmail.toLowerCase()) {
                    _snack(ctx, 'That\'s already your current email', error: true);
                    return;
                  }
                  setModal(() => loading = true);
                  try {
                    final response = await Supabase.instance.client.functions.invoke(
                      'send-otp',
                      body: {
                        'email': currentEmail,
                        'purpose': 'email_change',
                        'new_email': newEmail,
                      },
                    );
                    if (response.data['success'] != true) {
                      throw Exception(response.data['error'] ?? 'Failed to send code');
                    }
                    if (ctx.mounted) {
                      Navigator.pop(ctx); // close sheet
                      final result = await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OTPVerificationPage(
                            email: currentEmail,
                            userId: response.data['userId'] ?? '',
                            purpose: 'email_change',
                            newEmail: newEmail,
                          ),
                        ),
                      );
                      if (result == true && context.mounted) {
                        // FIX: Force the Supabase session to refresh so
                        // auth.currentUser?.email reflects the new email
                        // immediately. Without this the old email lingers in
                        // the local session until the token naturally expires.
                        try {
                          final session =
                              Supabase.instance.client.auth.currentSession;
                          final rt = session?.refreshToken;
                          if (rt != null) {
                            await Supabase.instance.client.auth
                                .setSession(rt);
                          }
                        } catch (refreshErr) {
                          debugPrint('Session refresh after email change: $refreshErr');
                        }
                        // Bust the profile cache so the UI picks up the new email
                        ref.invalidate(currentUserProfileProvider);
                        _snack(context, 'Email updated to $newEmail');
                      }
                    }
                  } catch (e) {
                    setModal(() => loading = false);
                    if (ctx.mounted) _snack(ctx, 'Error: $e', error: true);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Delete Account ────────────────────────────────────────────────────────
  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Account',
        body: 'This permanently deletes your account, profile, and all content. This cannot be undone.',
        confirmLabel: 'Delete Forever',
        confirmColor: Colors.red,
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await ref.read(authControllerProvider).logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
      }
    } catch (e) {
      if (mounted) _snack(context, 'Error: $e', error: true);
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _snack(BuildContext ctx, String msg, {bool error = false}) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String username; final String email; final String? profilePic;
  final ThemeData theme; final VoidCallback onTap;
  const _ProfileCard({required this.username, required this.email,
    required this.profilePic, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.cardColor,
          borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        CircleAvatar(
          radius: 26,
          backgroundColor: theme.colorScheme.primary.withOpacity(0.2),
          backgroundImage: profilePic != null ? NetworkImage(profilePic!) : null,
          child: profilePic == null
              ? Text(username.isNotEmpty ? username[0].toUpperCase() : '?',
              style: TextStyle(color: theme.colorScheme.primary,
                  fontSize: 20, fontWeight: FontWeight.bold))
              : null,
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(username, style: TextStyle(color: theme.colorScheme.onSurface,
              fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('Edit profile', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
        ])),
        Icon(Icons.chevron_right_rounded,
            color: theme.colorScheme.onSurface.withOpacity(0.3)),
      ]),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text; final ThemeData theme;
  const _SectionLabel(this.text, this.theme);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(text.toUpperCase(),
        style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4),
            fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3)),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon; final String label; final String? subtitle;
  final Color? labelColor; final Color? iconColor;
  final ThemeData theme; final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label,
    required this.theme, required this.onTap,
    this.subtitle, this.labelColor, this.iconColor});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon,
          color: iconColor ?? theme.colorScheme.onSurface.withOpacity(0.7), size: 20),
      title: Text(label, style: TextStyle(
          color: labelColor ?? theme.colorScheme.onSurface,
          fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 11),
          overflow: TextOverflow.ellipsis)
          : null,
      trailing: Icon(Icons.chevron_right_rounded,
          color: theme.colorScheme.onSurface.withOpacity(0.25), size: 18),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon; final String label; final String? subtitle;
  final bool value; final ThemeData theme; final ValueChanged<bool> onChanged;
  const _ToggleTile({required this.icon, required this.label,
    required this.value, required this.theme, required this.onChanged, this.subtitle});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(
        color: theme.cardTheme.color ?? theme.cardColor,
        borderRadius: BorderRadius.circular(12)),
    child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Icon(icon, color: theme.colorScheme.onSurface.withOpacity(0.7), size: 20),
      title: Text(label, style: TextStyle(color: theme.colorScheme.onSurface,
          fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.4), fontSize: 11))
          : null,
      trailing: CupertinoSwitch(
          value: value, onChanged: onChanged, activeColor: theme.colorScheme.primary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class _Sheet extends StatelessWidget {
  final String title; final Widget child; final ThemeData theme;
  const _Sheet({required this.title, required this.child, required this.theme});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4,
                decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(color: theme.colorScheme.onSurface,
                fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 18),
            child,
          ]),
    );
  }
}

class _Field extends StatelessWidget {
  final String label; final TextEditingController ctrl; final ThemeData theme;
  const _Field({required this.label, required this.ctrl, required this.theme});

  @override
  Widget build(BuildContext context) => TextField(
    controller: ctrl,
    style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 14),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontSize: 13),
      filled: true, fillColor: theme.cardColor,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
    ),
  );
}

class _PrimaryBtn extends StatelessWidget {
  final String label; final bool loading; final VoidCallback onPressed;
  const _PrimaryBtn({required this.label, required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
        child: loading
            ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  final String title, body, confirmLabel; final Color confirmColor;
  const _ConfirmDialog({required this.title, required this.body,
    required this.confirmLabel, required this.confirmColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: TextStyle(color: theme.colorScheme.onSurface,
          fontSize: 17, fontWeight: FontWeight.w700)),
      content: Text(body, style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 13, height: 1.5)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel',
              style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: confirmColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0),
          child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}