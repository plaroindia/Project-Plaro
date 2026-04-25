import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/user_profile.dart';
import '../../Viewmodels/chat_list_provider.dart';
import 'chat_page.dart';

class ChatList extends ConsumerStatefulWidget {
  final String userId;
  final Function(UserProfile)? onUserTap;
  final bool showAppBar;
  final bool isBottomSheet;

  const ChatList({
    super.key,
    required this.userId,
    this.onUserTap,
    this.showAppBar = true,
    this.isBottomSheet = false,
  });

  @override
  ConsumerState<ChatList> createState() => _ChatListState();
}

class _ChatListState extends ConsumerState<ChatList>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _selectedChats = {};
  bool _isSelectionMode = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<ChatUserProfile> _filteredUsers = [];
  final Set<String> _selectedUsersForGroup = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchInitialData();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _fetchInitialData() {
    final notifier = ref.read(enhancedChatListProvider(widget.userId).notifier);
    notifier.fetchChatUsersWithMessages(refresh: true);
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 200) {
        ref.read(enhancedChatListProvider(widget.userId).notifier)
            .fetchChatUsersWithMessages();
      }
    }
  }

  void _onSearchChanged() {
    final chatState = ref.read(enhancedChatListProvider(widget.userId));
    final query = _searchController.text.toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _filteredUsers = chatState.users;
      });
    } else {
      setState(() {
        _filteredUsers = chatState.users.where((user) {
          return user.username.toLowerCase().contains(query) ||
              (user.lastMessage?.toLowerCase().contains(query) ?? false) ||
              (user.bio?.toLowerCase().contains(query) ?? false);
        }).toList();
      });
    }
  }

  void _toggleSelection(String userId) {
    setState(() {
      if (_selectedChats.contains(userId)) {
        _selectedChats.remove(userId);
      } else {
        _selectedChats.add(userId);
      }

      if (_selectedChats.isEmpty) {
        _isSelectionMode = false;
      } else {
        _isSelectionMode = true;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedChats.clear();
      _isSelectionMode = false;
    });
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        _filteredUsers = [];
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _searchFocusNode.requestFocus();
        });
      }
    });
  }

  void _pinChat(String userId) {
    print('Pinning chat: $userId');
    _clearSelection();
  }

  void _muteChat(String userId) {
    print('Muting chat: $userId');
    _clearSelection();
  }

  void _deleteChat(String userId) {
    print('Deleting chat: $userId');
    _clearSelection();
  }

  // void _toggleUserForGroup(String userId) {
  //   setState(() {
  //     if (_selectedUsersForGroup.contains(userId)) {
  //       _selectedUsersForGroup.remove(userId);
  //     } else {
  //       _selectedUsersForGroup.add(userId);
  //     }
  //   });
  // }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final chatState = ref.watch(enhancedChatListProvider(widget.userId));
    final users = _isSearching ? _filteredUsers : chatState.users;

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          if (_isSelectionMode) _buildSelectionAppBar(),
          if (widget.showAppBar && !_isSelectionMode)
            _isSearching ? _buildSearchAppBar() : _buildAppBar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await ref
                    .read(enhancedChatListProvider(widget.userId).notifier)
                    .refresh();
              },
              backgroundColor: Colors.grey[900],
              color: Colors.blue,
              child: Container(
                color: Colors.black,
                child: _buildList(
                  users: users,
                  isLoading: chatState.isLoading,
                  error: chatState.error,
                  hasMore: chatState.hasMore,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      toolbarHeight: 56,
      leading: IconButton(
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.arrow_back, color: Colors.white),
      ),
      title: Text(
        "Chats",
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      actions: [
        IconButton(
          onPressed: _toggleSearch,
          icon: Icon(Icons.search, color: Colors.white, size: 24),
        ),
        // IconButton(
        //   onPressed: () {
        //     _selectedUsersForGroup.clear();
        //     _showCreateGroupDialog(context);
        //   },
        //   icon: Icon(Icons.group_add, color: Colors.white, size: 24),
        // ),
      ],
    );
  }

  Widget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      toolbarHeight: 56,
      leading: IconButton(
        onPressed: () {
          setState(() {
            _isSearching = false;
            _searchController.clear();
            _filteredUsers = [];
          });
        },
        icon: Icon(Icons.arrow_back, color: Colors.white),
      ),
      title: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        style: TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: 'Search chats...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 16),
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: (value) {
          _onSearchChanged();
        },
      ),
      actions: [
        if (_searchController.text.isNotEmpty)
          IconButton(
            onPressed: () {
              _searchController.clear();
            },
            icon: Icon(Icons.clear, color: Colors.white, size: 22),
          ),
      ],
    );
  }

  Widget _buildSelectionAppBar() {
    return AppBar(
      backgroundColor: Colors.grey[900],
      elevation: 0,
      toolbarHeight: 56,
      leading: IconButton(
        onPressed: _clearSelection,
        icon: Icon(Icons.close, color: Colors.white),
      ),
      title: Text(
        '${_selectedChats.length}',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 18,
        ),
      ),
      actions: [
        if (_selectedChats.length == 1)
          IconButton(
            onPressed: () => _muteChat(_selectedChats.first),
            icon: Icon(
                Icons.notifications_off, color: Colors.white, size: 22),
          ),
        if (_selectedChats.length == 1)
          IconButton(
            onPressed: () => _pinChat(_selectedChats.first),
            icon: Icon(Icons.push_pin, color: Colors.white, size: 22),
          ),
        IconButton(
          onPressed: () {
            for (String id in _selectedChats) {
              _deleteChat(id);
            }
          },
          icon: Icon(Icons.delete, color: Colors.white, size: 22),
        ),
      ],
    );
  }

  Widget _buildList({
    required List<ChatUserProfile> users,
    required bool isLoading,
    required String? error,
    required bool hasMore,
  }) {
    if (error != null && users.isEmpty) {
      return _buildErrorWidget(error);
    }

    if (users.isEmpty && !isLoading) {
      return _buildEmptyWidget();
    }

    if (users.isEmpty && isLoading) {
      return _buildInitialLoadingWidget();
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: users.length + (hasMore && isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= users.length) {
          return _buildLoadingItem();
        }

        final user = users[index];
        return Column(
          children: [
            _buildChatListItem(user),
            Container(
              height: 0.5,
              margin: EdgeInsets.only(left: 88, right: 16),
              color: Colors.grey[800]!.withOpacity(0.3),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChatListItem(ChatUserProfile user) {
    final isSelected = _selectedChats.contains(user.user_id);

    return Material(
      color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(user.user_id);
          } else {
            // Mark messages as read when opening chat
            if (user.unreadCount > 0) {
              ref.read(enhancedChatListProvider(widget.userId).notifier)
                  .markMessagesAsRead(user.user_id);
            }

            if (widget.onUserTap != null) {
              widget.onUserTap!(user);
            } else {
              _navigateToChat(context, user);
            }
          }
        },
        onLongPress: () {
          _toggleSelection(user.user_id);
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Stack(
                children: [
                  _buildProfileImage(user),
                  if (_isSelectionMode)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue : Colors.grey[700],
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: isSelected
                            ? Icon(
                            Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                  // Online status indicator (green dot)
                  if (user.unreadCount > 0 && !_isSelectionMode)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.username,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: user.unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!_isSelectionMode && user.lastMessageTime != null)
                          Text(
                            _formatMessageTime(user.lastMessageTime!),
                            style: TextStyle(
                              color: user.unreadCount > 0
                                  ? Colors.green
                                  : Colors.grey[500],
                              fontSize: 12,
                              fontWeight: user.unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        // Message status indicator for sent messages
                        if (user.isLastMessageFromMe && user.lastMessage != null) ...[
                          Icon(
                            Icons.done,
                            size: 16,
                            color: Colors.grey[500],
                          ),
                          SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            user.lastMessage ?? (user.bio?.isNotEmpty == true
                                ? user.bio!
                                : 'No messages yet'),
                            style: TextStyle(
                              color: user.lastMessage != null
                                  ? (user.unreadCount > 0
                                  ? Colors.white
                                  : Colors.grey[400])
                                  : Colors.grey[500],
                              fontSize: 14,
                              fontWeight: user.unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // Unread count badge
                        if (user.unreadCount > 0 && !_isSelectionMode)
                          Container(
                            margin: EdgeInsets.only(left: 8),
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.all(Radius.circular(12)),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            child: Text(
                              user.unreadCount > 99 ? '99+' : '${user.unreadCount}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMessageTime(DateTime messageTime) {
    final now = DateTime.now();
    final difference = now.difference(messageTime);

    if (difference.inDays > 0) {
      if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d';
      } else {
        return '${messageTime.day}/${messageTime.month}/${messageTime.year}';
      }
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  void _navigateToChat(BuildContext context, ChatUserProfile user) {
    try {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => IndividualChatPage(
            receiver: user,
            receiverId: user.user_id,
            receiverName: user.username,
            receiverProfilePic: user.profilePic,
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening chat: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProfileImage(ChatUserProfile user) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[700],
      ),
      child: user.profilePic?.isNotEmpty == true
          ? ClipOval(
        child: Image.network(
          user.profilePic!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.person,
              color: Colors.grey[400],
              size: 28,
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                  strokeWidth: 2,
                ),
              ),
            );
          },
        ),
      )
          : Icon(
        Icons.person,
        color: Colors.grey[400],
        size: 28,
      ),
    );
  }

  Widget _buildInitialLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          SizedBox(height: 16),
          Text(
            'Loading chats...',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingItem() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          strokeWidth: 2,
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.message_outlined,
              size: 40,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 24),
          Text(
            'No chats yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start following people to see them here\nand begin conversations',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.red[900]?.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.error_outline,
              size: 40,
              color: Colors.red[400],
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Something went wrong',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _fetchInitialData,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
            ),
            child: Text('Try again'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialog(BuildContext context) {
    final chatState = ref.read(enhancedChatListProvider(widget.userId));
    final TextEditingController groupSearchController = TextEditingController();
    final TextEditingController groupNameController = TextEditingController();
    List<ChatUserProfile> filteredGroupUsers = chatState.users;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void filterGroupUsers(String query) {
              if (query.isEmpty) {
                setState(() {
                  filteredGroupUsers = chatState.users;
                });
              } else {
                setState(() {
                  filteredGroupUsers = chatState.users.where((user) {
                    return user.username.toLowerCase().contains(
                        query.toLowerCase());
                  }).toList();
                });
              }
            }

            bool canCreateGroup() {
              return _selectedUsersForGroup.isNotEmpty &&
                  groupNameController.text.trim().isNotEmpty;
            }

            return Dialog(
              backgroundColor: Colors.grey[900],
              insetPadding: EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Create New Group',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Divider(color: Colors.grey[800], height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: groupNameController,
                                style: TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Group name',
                                  hintStyle: TextStyle(color: Colors.grey[500]),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[800],
                                  contentPadding: EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                ),
                                onChanged: (value) {
                                  setState(() {});
                                },
                              ),
                              SizedBox(height: 16),
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[800],
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  children: [
                                    Icon(Icons.search, color: Colors.grey[500], size: 20),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        controller: groupSearchController,
                                        style: TextStyle(color: Colors.white, fontSize: 14),
                                        decoration: InputDecoration(
                                          hintText: 'Search participants...',
                                          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                                        ),
                                        onChanged: filterGroupUsers,
                                      ),
                                    ),
                                    if (groupSearchController.text.isNotEmpty)
                                      IconButton(
                                        icon: Icon(Icons.clear, color: Colors.grey[500], size: 18),
                                        onPressed: () {
                                          groupSearchController.clear();
                                          filterGroupUsers('');
                                        },
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Select participants:',
                                style: TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              SizedBox(height: 8),
                              if (filteredGroupUsers.isNotEmpty)
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: MediaQuery.of(context).size.height * 0.3,
                                  ),
                                  child: ListView.builder(
                                    shrinkWrap: true,
                                    itemCount: filteredGroupUsers.length,
                                    itemBuilder: (context, index) {
                                      final user = filteredGroupUsers[index];
                                      final isSelected = _selectedUsersForGroup.contains(user.user_id);

                                      return ListTile(
                                        leading: _buildProfileImage(user),
                                        title: Text(
                                          user.username,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        trailing: isSelected
                                            ? Icon(Icons.check_circle, color: Colors.blue)
                                            : Icon(Icons.radio_button_unchecked, color: Colors.grey),
                                        // onTap: () {
                                        //   setState(() {
                                        //     _toggleUserForGroup(user.user_id);
                                        //   });
                                        // },
                                      );
                                    },
                                  ),
                                )
                              else
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Text(
                                    'No contacts found',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              SizedBox(height: 8),
                              if (_selectedUsersForGroup.isNotEmpty)
                                Text(
                                  'Selected: ${_selectedUsersForGroup.length} users',
                                  style: TextStyle(color: Colors.blue),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Divider(color: Colors.grey[800], height: 1),
                    Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              _selectedUsersForGroup.clear();
                            },
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: canCreateGroup()
                                ? () {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Group "${groupNameController.text}" created successfully'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _selectedUsersForGroup.clear();
                            }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: canCreateGroup() ? Colors.blue : Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            child: Text('Create Group'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}