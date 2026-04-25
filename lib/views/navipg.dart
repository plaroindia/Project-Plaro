// ================================================================
// navipg.dart  (UPDATED)
//
// Changes vs previous version:
//   1. Profile tab icon = circular cached avatar with blue ring
//      when selected (Instagram-style).
//   2. Long-pressing the profile avatar opens AccountSwitcherSheet.
//   3. AccountSwitcherSheet no longer pre-signs-out — it shows
//      the full list WHILE the user is still logged in, exactly
//      like Instagram.
//   4. After a switch/add, onboarding is checked before routing.
// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:plaro_3/views/post_page.dart';
import 'package:plaro_3/views/taiken_create_page.dart';
import 'home_page.dart';
import 'profile.dart';
import '../Viewmodels/setProfileProvider.dart';
import '../Viewmodels/user_feed_provider.dart';
import '../Viewmodels/follow_provider.dart';
import '../Viewmodels/notifications_provider.dart';
import '../Viewmodels/user_provider.dart';
import '../Viewmodels/auth_provider.dart';
import '../Viewmodels/account_switcher_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'byte_page.dart';
import 'byte_viewer.dart';
import 'taiken_list_page.dart';
import 'login_page.dart';

void main() => runApp(MaterialApp(home: navCard()));

// ════════════════════════════════════════════════════════════════════════════
// navCard — main app shell
// ════════════════════════════════════════════════════════════════════════════

class navCard extends ConsumerStatefulWidget {
  const navCard({super.key});

  @override
  ConsumerState<navCard> createState() => _navCardState();
}

class _navCardState extends ConsumerState<navCard> {
  int _selectedIndex = 0;
  final SupabaseClient _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationsProvider.notifier).init();
      // Ensure the currently-logged-in account is always in the list.
      // This covers first-launch after install before any account picker
      // interaction has happened.
      ref.read(accountSwitcherProvider.notifier).saveCurrentAccount();
    });
  }

  // ── Pages ─────────────────────────────────────────────────────────────────

  Widget _getPageForIndex(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return ByteViewerPage();
      case 2:
        return TaikensListPage();
      case 3:
        return Container();
      case 4:
        return _buildProfileScreen();
      default:
        return const HomeScreen();
    }
  }

  Widget _buildProfileScreen() {
    final user = currentUser;
    if (user == null) return _buildAuthRequiredScreen();
    return OtherProfileScreen(
      userId: null,
      key: ValueKey('own_profile_${user.id}'),
    );
  }

  Widget _buildAuthRequiredScreen() {
    return Container(
      color: Colors.transparent,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, color: Colors.grey[400], size: 64),
            const SizedBox(height: 16),
            const Text(
              'Please log in to view profile',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text('Log In'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  void _onItemTapped(int index) {
    if (index == 3) {
      _showCreateModal();
    } else {
      if (index == 4) _clearProfileState();
      setState(() => _selectedIndex = index);
    }
  }

  void _clearProfileState() {
    ref.read(setProfileProvider.notifier).clearProfile();
    ref.read(profileFeedProvider.notifier).clearFeed();
    ref.read(followProvider.notifier).clear();
  }

  void _showCreateModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.7),
      isScrollControlled: true,
      builder: (context) => const CreateModalSheet(),
    );
  }

  void _showAccountSwitcher() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (_) => AccountSwitcherSheet(
        onAfterSwitch: _handleAfterSwitch,
      ),
    );
  }

  /// Called after a successful switch or add-account.
  /// Handles onboarding check and navigation.
  void _handleAfterSwitch(Map<String, dynamic> result) {
    if (!mounted) return;
    final requiresOnboarding = result['requiresOnboarding'] == true;

    if (requiresOnboarding) {
      // Route to onboarding — same pattern used by login_page.dart
      Navigator.pushReplacementNamed(context, '/onboarding');
    } else {
      // Full restart of the app shell to reload all providers cleanly
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const navCard()),
            (_) => false,
      );
    }
  }

  // ── Profile nav icon ──────────────────────────────────────────────────────

  Widget _buildProfileNavIcon(bool isSelected) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final photoUrl = profileAsync.when(
      data: (p) => p?.profilePic,
      loading: () => null,
      error: (_, __) => null,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: _showAccountSwitcher,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipOval(
          child: photoUrl != null && photoUrl.isNotEmpty
              ? CachedNetworkImage(
            imageUrl: photoUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => _profileFallback(),
            errorWidget: (_, __, ___) => _profileFallback(),
          )
              : _profileFallback(),
        ),
      ),
    );
  }

  Widget _profileFallback() => Container(
    color: Colors.grey[850],
    child: const Icon(Icons.person, size: 16, color: Colors.grey),
  );

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isSwitching =
    ref.watch(accountSwitcherProvider.select((s) => s.isSwitching));

    return Stack(
      children: [
        Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: _getPageForIndex(_selectedIndex),
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            elevation: 3.0,
            selectedItemColor: Colors.blue,
            unselectedItemColor: Colors.grey,
            iconSize: 20.0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            items: [
              const BottomNavigationBarItem(
                  icon: Icon(Icons.home), label: 'Home'),
              const BottomNavigationBarItem(
                  icon: Icon(Icons.play_circle_outline), label: 'Bytes'),
              const BottomNavigationBarItem(
                  icon: Icon(Icons.gamepad), label: 'Taiken'),
              const BottomNavigationBarItem(
                  icon: Icon(Icons.add), label: 'Create'),
              BottomNavigationBarItem(
                icon: _buildProfileNavIcon(_selectedIndex == 4),
                label: 'Profile',
              ),
            ],
          ),
        ),

        // Full-screen overlay while switching accounts
        if (isSwitching)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.65),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5),
                    SizedBox(height: 16),
                    Text(
                      'Switching account…',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          decoration: TextDecoration.none),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// AccountSwitcherSheet
//
// Shown while the user IS still logged in (no pre-signout).
// Exported so home_page.dart can use it from the drawer too.
// ════════════════════════════════════════════════════════════════════════════

class AccountSwitcherSheet extends ConsumerWidget {
  /// Called with the result map after a successful switch or add.
  final void Function(Map<String, dynamic> result)? onAfterSwitch;

  const AccountSwitcherSheet({super.key, this.onAfterSwitch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountSwitcherProvider);
    final currentEmail =
        Supabase.instance.client.auth.currentUser?.email ?? '';

    Future<void> handleResult(
        BuildContext ctx, Map<String, dynamic> result) async {
      if (!ctx.mounted) return;

      if (result['success'] == true) {
        onAfterSwitch?.call(result);
      } else if (result['cancelled'] != true) {
        // Show error only if it wasn't a user-cancel
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(result['error']?.toString() ?? 'Something went wrong'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    Future<void> onSwitch(SavedAccount account) async {
      Navigator.pop(context); // close sheet immediately (feels instant)
      final result =
      await ref.read(accountSwitcherProvider.notifier).switchToAccount(account);
      if (context.mounted) await handleResult(context, result);
    }

    Future<void> onAdd() async {
      Navigator.pop(context);
      final result =
      await ref.read(accountSwitcherProvider.notifier).addAccount();
      if (context.mounted) await handleResult(context, result);
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle pill
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Accounts',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // Account tiles
          ...state.accounts.map((account) {
            final isCurrent = account.email == currentEmail;
            return _AccountTile(
              account: account,
              isCurrent: isCurrent,
              onTap: isCurrent ? null : () => onSwitch(account),
              onRemove: isCurrent
                  ? null
                  : () => ref
                  .read(accountSwitcherProvider.notifier)
                  .removeAccount(account.email),
            );
          }),

          // Add account row
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey[700]!, width: 1.5),
              ),
              child: const Icon(Icons.add, color: Colors.blue, size: 22),
            ),
            title: const Text(
              'Add account',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: onAdd,
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}

// ── Single account row ────────────────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  final SavedAccount account;
  final bool isCurrent;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _AccountTile({
    required this.account,
    required this.isCurrent,
    this.onTap,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: isCurrent
                  ? Border.all(color: Colors.blue, width: 2)
                  : null,
            ),
            child: ClipOval(
              child: account.photoUrl != null && account.photoUrl!.isNotEmpty
                  ? CachedNetworkImage(
                imageUrl: account.photoUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _fallback(),
              )
                  : _fallback(),
            ),
          ),
          if (isCurrent)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: const Icon(Icons.check, size: 9, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Text(
        account.label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        account.email,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          fontSize: 12,
        ),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isCurrent
          ? const Text('Active',
          style: TextStyle(color: Colors.blue, fontSize: 12))
          : IconButton(
        icon: Icon(Icons.close,
            size: 18,
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withOpacity(0.4)),
        onPressed: onRemove,
      ),
    );
  }

  Widget _fallback() => Container(
    color: Colors.grey[850],
    child: const Icon(Icons.person, color: Colors.grey),
  );
}

// ════════════════════════════════════════════════════════════════════════════
// CreateModalSheet (unchanged)
// ════════════════════════════════════════════════════════════════════════════

class CreateModalSheet extends StatefulWidget {
  const CreateModalSheet({super.key});

  @override
  _CreateModalSheetState createState() => _CreateModalSheetState();
}

class _CreateModalSheetState extends State<CreateModalSheet> {
  int _selectedIndex = 0;
  final List<String> _options = ['Post', 'Byte', 'Taiken'];

  void _onOptionSelected(int index) {
    setState(() => _selectedIndex = index);
    _navigateToPage(index);
  }

  void _navigateToPage(int index) {
    Navigator.pop(context);
    switch (index) {
      case 0:
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => PostCreateScreen()));
        break;
      case 1:
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => ByteCreateScreen()));
        break;
      case 2:
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => TaikenCreatePage()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Container(
      height: screenHeight * 0.23,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text(
                        'Create',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isTablet ? 22 : 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: List.generate(
                      _options.length,
                          (index) => Expanded(
                        child: GestureDetector(
                          onTap: () => _onOptionSelected(index),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: isTablet ? 60 : 50,
                                height: isTablet ? 60 : 50,
                                decoration: BoxDecoration(
                                  color: _selectedIndex == index
                                      ? Colors.blue
                                      : Theme.of(context).dividerColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedIndex == index
                                        ? Colors.blue
                                        : Theme.of(context).dividerColor,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  _getOptionIcon(index),
                                  color: _selectedIndex == index
                                      ? Colors.white
                                      : Colors.grey[400],
                                  size: isTablet ? 28 : 24,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _options[index],
                                style: TextStyle(
                                  color: _selectedIndex == index
                                      ? Colors.blue
                                      : Colors.grey[400],
                                  fontSize: isTablet ? 16 : 14,
                                  fontWeight: _selectedIndex == index
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 16),
                  child: Row(
                    children: List.generate(
                      _options.length,
                          (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 3,
                          decoration: BoxDecoration(
                            color: _selectedIndex == index
                                ? Colors.blue
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getOptionIcon(int index) {
    switch (index) {
      case 0:
        return Icons.add_box_outlined;
      case 1:
        return Icons.play_circle_outline;
      case 2:
        return Icons.gamepad;
      default:
        return Icons.add;
    }
  }
}