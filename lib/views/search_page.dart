import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/Profile_card.dart';
import '../Viewmodels/search_provider.dart';
import '../views/profile.dart';
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    setState(() {
      _isSearching = query.isNotEmpty;
    });

    if (query.isEmpty) {
      // Clear search results when query is empty
      ref.read(searchProfileProvider.notifier).clearSearch();
    } else {
      // Debounce search to avoid too many API calls
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_searchController.text.trim() == query) {
          ref.read(searchProfileProvider.notifier).searchUsers(query);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    final searchState = ref.watch(searchProfileProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Header Section
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Add status bar padding
                SizedBox(height: MediaQuery.of(context).padding.top),

                // Header with back button and title
                Row(
                  children: [
                    SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Padding(
                        padding: EdgeInsets.only(left: 8.0),
                        child: Icon(
                          Icons.arrow_back_ios,
                          color: Colors.grey[400],
                          size: 20,
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        'Search',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: isTablet ? 20 : 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

                // Search Bar
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 16),
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(
                      color: Colors.grey[800]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: Colors.grey[400],
                        size: 20,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search users by username',
                            hintStyle: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 16,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (_isSearching) ...[
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                          },
                          child: Icon(
                            Icons.clear,
                            color: Colors.grey[400],
                            size: 20,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                SizedBox(height: 16),
              ],
            ),
          ),

          // Search Results Section
          Expanded(
            child: searchState.when(
              data: (users) {
                if (!_isSearching) {
                  // Show initial state when not searching
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          color: Colors.grey[600],
                          size: 48,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Start typing to search for users',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                } else if (users.isEmpty) {
                  // Show no results found
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search_off,
                          color: Colors.grey[600],
                          size: 48,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No users found',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Try searching with different keywords',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  // Show search results
                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, index) {
                      final user = users[index];
                      return ProfileCard(
                        user: user,
                        onTap: () {

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => OtherProfileScreen(
                                userId: user.user_id, // Pass the user ID
                                initialUserData: user, // Pass initial data to avoid loading delay
                              ),
                            ),
                          );


                        },
                      );
                    },
                  );
                }
              },
              loading: () => Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              error: (error, stackTrace) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red[400],
                      size: 48,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Error searching users',
                      style: TextStyle(
                        color: Colors.red[400],
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please try again later',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        if (_searchController.text.isNotEmpty) {
                          ref.read(searchProfileProvider.notifier)
                              .searchUsers(_searchController.text);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        foregroundColor: Colors.white,
                      ),
                      child: Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}