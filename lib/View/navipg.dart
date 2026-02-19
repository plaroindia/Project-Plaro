import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plaro_3/View/post_page.dart';
import 'package:plaro_3/View/taiken_create_page.dart';
import 'home_page.dart';
import 'profile.dart';
import '../ViewModel/setProfileProvider.dart';
import '../ViewModel/user_feed_provider.dart';
import '../ViewModel/follow_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'byte_page.dart';
import 'byte_viewer.dart';
import 'taiken_list_page.dart';


void main() => runApp(MaterialApp(home: navCard()));

class navCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<navCard> createState() => _navCardState();
}

class _navCardState extends ConsumerState<navCard> {
  int _selectedIndex = 0;
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get current user from Supabase
  User? get currentUser => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    // Don't load profile here - let OtherProfileScreen handle it
  }

  // Get the appropriate widget for each tab
  Widget _getPageForIndex(int index) {
    switch (index) {
      case 0:
        return HomeScreen();
      case 1:
        return ByteViewerPage();
      case 2:
        return TaikensListPage();
      case 3:
        return Container();
      case 4:
        return _buildProfileScreen();
      default:
        return HomeScreen();
    }
  }

  // Build profile screen with proper error handling and loading states
  Widget _buildProfileScreen() {
    final user = currentUser;

    if (user == null) {
      return _buildAuthRequiredScreen();
    }

    // Pass null as userId to indicate this is the current user's profile
    // Don't pass initialUserData to force fresh loading
    return OtherProfileScreen(
      userId: null, // This indicates it's the current user's profile
      key: ValueKey(
        'own_profile_${user.id}',
      ), // Force rebuild when user changes
    );
  }

  // Build screen when user is not authenticated
  Widget _buildAuthRequiredScreen() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off, color: Colors.grey[400], size: 64),
            const SizedBox(height: 16),
            Text(
              'Please log in to view profile',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Navigate to login screen
                // You can implement this based on your app structure
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: Text('Log In'),
            ),
          ],
        ),
      ),
    );
  }

  void _onItemTapped(int index) {
    if (index == 3) {
      // Show create modal instead of navigating
      _showCreateModal();
    } else {
      // Clear profile-related state when navigating to profile tab
      if (index == 4) {
        _clearProfileState();
      }

      setState(() {
        _selectedIndex = index;
      });
    }
  }

  // Clear profile state to ensure fresh data when switching to profile tab
  void _clearProfileState() {
    // Clear profile provider
    ref.read(setProfileProvider.notifier).clearProfile();
    // Clear feed provider
    ref.read(profileFeedProvider.notifier).clearFeed();
    // Clear follow provider
    ref.read(followProvider.notifier).clear();
  }

  void _showCreateModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.7), // Blur effect
      isScrollControlled: true,
      builder: (context) => CreateModalSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, toolbarHeight: 0.0),
      body: _getPageForIndex(_selectedIndex),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        elevation: 3.0,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        iconSize: 20.0,
        backgroundColor: Colors.black,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.play_circle_outline), label: 'Bytes'),
          BottomNavigationBarItem(icon: Icon(Icons.gamepad), label: 'Taiken'),
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'Create'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

// Create Modal Sheet Widget
class CreateModalSheet extends StatefulWidget {
  @override
  _CreateModalSheetState createState() => _CreateModalSheetState();
}

class _CreateModalSheetState extends State<CreateModalSheet> {
  int _selectedIndex = 0;
  final List<String> _options = ['Post', 'Byte','Taiken'];

  void _onOptionSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _navigateToPage(index);
  }

  void _navigateToPage(int index) {
    Navigator.pop(context);
    switch (index) {
      case 0: // Post
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => PostCreateScreen()),
        );
        break;
      case 1: // Byte
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ByteCreateScreen()),
        );
        break;
      case 2: // Taiken
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => TaikenCreatePage()),
        );
        break;
    }
  }


  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    return Container(
      height: screenHeight * 0.23, // Takes up 23% of screen height
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Bottom Section with Options
          Container(
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Header
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

                // Options Row
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
                                      : Colors.grey[800],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedIndex == index
                                        ? Colors.blue
                                        : Colors.grey[700]!,
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


                // Selected Option Indicator
                Container(
                  margin: EdgeInsets.only(top: 16),
                  child: Row(
                    children: List.generate(
                      _options.length,
                          (index) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 3,
                          decoration: BoxDecoration(
                            color:
                            _selectedIndex == index
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
      case 0: // Post
        return Icons.add_box_outlined;
      case 1: // Byte
        return Icons.play_circle_outline;
      case 2: // Taiken
        return Icons.gamepad;
      default:
        return Icons.add;
    }
  }
}