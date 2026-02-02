import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ViewModel/setprofileprovider.dart';
import 'package:image_picker/image_picker.dart';

class SetProfile extends ConsumerStatefulWidget {
  final bool isOnboarding;
  const SetProfile({super.key, this.isOnboarding = false});

  @override
  ConsumerState<SetProfile> createState() => _SetProfileState();
}

class _SetProfileState extends ConsumerState<SetProfile> {
  final _formKey = GlobalKey<FormState>();
  bool _isInitialized = false;
  bool _isUploading = false; // Track upload state

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _schoolController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();

  File? _profileImage; // New selected image
  String? _profileImageUrl; // Current profile image URL from database


  final List<String> _roleOptions = [
    'Student',
    'Professional',
    'Learner',
  ];

  String? _selectedRole;



  @override
  void initState() {
    super.initState();
  }

  // Load user profile - following the same pattern as profile.dart
  Future<void> _loadUserProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await ref.read(setProfileProvider.notifier).getUserProfile(user.id);

        // Populate fields after data is loaded
        final profileState = ref.read(setProfileProvider);
        profileState.whenData((profile) {
          if (profile != null) {
            _usernameController.text = profile.username;
            _userIdController.text = profile.user_id;
            _schoolController.text = profile.study ?? '';
            _bioController.text = profile.bio ?? '';
            _locationController.text = profile.location ?? '';
            _roleController.text = profile.role ?? '';
            setState(() {
              _profileImageUrl = profile.profilePic;
            });
          }
        });

        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      print('Error loading profile: $e');
      setState(() {
        _isInitialized = true;
      });
    }
  }

  // Refresh profile data - following the same pattern as profile.dart
  Future<void> _refreshProfile() async {
    setState(() {
      _isInitialized = false;
      _profileImage = null; // Reset selected image on refresh
    });
    await _loadUserProfile();
  }

  // Pick image from gallery
  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedImage = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );

      if (pickedImage != null) {
        setState(() {
          _profileImage = File(pickedImage.path);
        });
        print("Image selected: ${_profileImage?.path}");
      }
    } catch (e) {
      print('Error picking image: $e');
      _showSnackBar('Error selecting image: $e', isError: true);
    }
  }

  // Show image selection options
  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSheetOption(
              icon: Icons.delete,
              label: 'Remove Photo',
              onTap: () {
                setState(() => _profileImage = null);
                Navigator.pop(context);
              },
              iconColor: Colors.redAccent,
              textColor: Colors.redAccent,
            ),
            _buildSheetOption(
              icon: Icons.camera_alt,
              label: 'Take Photo',
              onTap: () => _pickImage(ImageSource.camera),
            ),
            _buildSheetOption(
              icon: Icons.photo_library,
              label: 'Choose from Gallery',
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            _buildSheetOption(
              icon: Icons.close,
              label: 'Cancel',
              onTap: () => Navigator.pop(context),
              textColor: Colors.grey,
              iconColor: Colors.grey,
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildSheetOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color textColor = Colors.white,
    Color iconColor = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      splashColor: Colors.grey[800],
      highlightColor: Colors.grey[700],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 16),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Upload profile image to Supabase Storage
  Future<String?> _uploadProfileImage() async {
    if (_profileImage == null) return null;

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      setState(() {
        _isUploading = true;
      });

      // Create unique filename
      final fileExtension = _profileImage!.path.split('.').last.toLowerCase();
      final fileName = 'profile_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = '${user.id}/$fileName';

      // Delete old profile image if exists
      if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
        try {
          final oldFileName = _profileImageUrl!.split('/').last;
          final oldFilePath = '${user.id}/$oldFileName';
          await Supabase.instance.client.storage
              .from('avatars')
              .remove([oldFilePath]);
        } catch (e) {
          print('Warning: Could not delete old profile image: $e');
        }
      }

      // Upload new image
      final response = await Supabase.instance.client.storage
          .from('avatars')
          .upload(filePath, _profileImage!);

      if (response.isEmpty) {
        throw Exception('Upload failed - no response');
      }

      // Get public URL
      final imageUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(filePath);

      print('Image uploaded successfully: $imageUrl');
      return imageUrl;

    } catch (e) {
      print('Error uploading image: $e');
      _showSnackBar('Failed to upload image: $e', isError: true);
      return null;
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  // Save profile function
  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated', isError: true);
        return;
      }

      String? finalImageUrl = _profileImageUrl; // Keep existing URL by default

      // Upload new image if selected
      if (_profileImage != null) {
        final uploadedUrl = await _uploadProfileImage();
        if (uploadedUrl != null) {
          finalImageUrl = uploadedUrl;
        } else {
          _showSnackBar('Failed to upload image, but profile will be saved without image update', isError: true);
        }
      }

      // Save profile
      await ref.read(setProfileProvider.notifier).saveProfile(
        user_id: user.id,
        username: _usernameController.text.trim(),
        email: user.email,
        role: _roleController.text.trim().isNotEmpty ? _roleController.text.trim() : null,
        profilePic: finalImageUrl,
        bio: _bioController.text.trim().isNotEmpty ? _bioController.text.trim() : null,
        study: _schoolController.text.trim().isNotEmpty ? _schoolController.text.trim() : null,
        location: _locationController.text.trim().isNotEmpty ? _locationController.text.trim() : null,
        isVerified: false,
      );

      // Update local state
      setState(() {
        _profileImageUrl = finalImageUrl;
        _profileImage = null; // Clear selected image after successful save
      });

      _showSnackBar('Profile saved successfully!', isError: false);

      // Optionally navigate back
      if (mounted) {
        if (widget.isOnboarding) {
          // If coming from onboarding, navigate to main app
          Navigator.pushReplacementNamed(context, '/navipg');
        } else {
          // If editing existing profile, just go back
          Navigator.pop(context);
        }
      }
    } catch (error) {
      String errorMessage = 'Failed to save profile';

      if (error is PostgrestException) {
        errorMessage = 'Database error: ${error.message}';
      } else if (error is AuthException) {
        errorMessage = 'Authentication error: ${error.message}';
      } else if (error is StorageException) {
        errorMessage = 'Storage error: ${error.message}';
      } else if (error is Exception) {
        errorMessage = error.toString();
      }

      _showSnackBar(errorMessage, isError: true);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(isError ? Icons.error : Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text(message),
            ],
          ),
          backgroundColor: isError ? Colors.red : Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.all(10),
        ),
      );
    }
  }

  // Helper method to get the display image
  ImageProvider? _getDisplayImage() {
    if (_profileImage != null) {
      return FileImage(_profileImage!);
    } else if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      return NetworkImage(_profileImageUrl!);
    }
    return null;
  }

  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      enabled: enabled,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white70,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.3), width: 1),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.blue.withOpacity(0.6), width: 1.3),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }

  String? _validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your $fieldName';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final profileState = ref.watch(setProfileProvider);

    // Initialize profile loading if not done yet - same pattern as profile.dart
    if (!_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadUserProfile();
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text('Edit Profile', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Add refresh button like in profile.dart
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshProfile,
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: RefreshIndicator(
            onRefresh: _refreshProfile,
            color: Colors.blue,
            backgroundColor: Colors.black,
            displacement: 40.0,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Show loading indicator if not initialized - same pattern as profile.dart
                    if (!_isInitialized && profileState.isLoading)
                      const Padding(
                        padding: EdgeInsets.all(20.0),
                        child: Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                          ),
                        ),
                      ),

                    // Profile image section with upload indicator
                    GestureDetector(
                      onTap: _isUploading ? null : _showImageOptions,
                      child: Stack(
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.blueAccent, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.4),
                                  blurRadius: 4,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: _getDisplayImage() != null
                                  ? Image(image: _getDisplayImage()!, fit: BoxFit.cover)
                                  : const Icon(Icons.person, size: 55, color: Colors.grey),
                            ),
                          ),
                          // Upload indicator overlay
                          if (_isUploading)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withOpacity(0.7),
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                  ),
                                ),
                              ),
                            ),
                          // Camera icon overlay for better UX
                          if (!_isUploading)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt, size: 20, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Image status text
                    if (_profileImage != null)
                      const Text(
                        'New image selected',
                        style: TextStyle(color: Colors.blue, fontSize: 12),
                      )
                    else if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                      const Text(
                        'Current profile image',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    else
                      const Text(
                        'Tap to select profile image',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),

                    const SizedBox(height: 30),

                    // Username field
                    profileState.when(
                      data: (profile) => _buildLabeledField(
                        label: 'Username',
                        controller: _usernameController,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a username';
                          }
                          if (value.trim().length < 3) {
                            return 'Username must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                      loading: () => _buildLabeledField(
                        label: 'Loading...',
                        controller: _usernameController,
                        enabled: false,
                      ),
                      error: (error, stack) => _buildLabeledField(
                        label: 'Username (Error loading data)',
                        controller: _usernameController,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a username';
                          }
                          if (value.trim().length < 3) {
                            return 'Username must be at least 3 characters';
                          }
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Role field
                    profileState.when(
                      data: (profile) => DropdownButtonFormField<String>(
                        value: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: _roleOptions
                            .map(
                              (role) => DropdownMenuItem<String>(
                            value: role,
                            child: Text(role),
                          ),
                        )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRole = value;
                          });
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Role is required';
                          }
                          return null;
                        },
                      ),

                      loading: () => DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                        ),
                        items: const [],
                        onChanged: null,
                        disabledHint: const Text('Loading...'),
                      ),

                      error: (error, stack) => DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Role',
                          border: OutlineInputBorder(),
                          errorText: 'Failed to load role data',
                        ),
                        items: _roleOptions
                            .map(
                              (role) => DropdownMenuItem<String>(
                            value: role,
                            child: Text(role),
                          ),
                        )
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRole = value;
                          });
                        },
                      ),
                    ),


                    const SizedBox(height: 20),

                    // School field
                    profileState.when(
                      data: (profile) => _buildLabeledField(
                        label: 'School/College',
                        controller: _schoolController,
                        validator: (value) => _validateRequired(value, 'school/college'),
                      ),
                      loading: () => _buildLabeledField(
                        label: 'Loading...',
                        controller: _schoolController,
                        enabled: false,
                      ),
                      error: (error, stack) => _buildLabeledField(
                        label: 'School/College - Error loading data',
                        controller: _schoolController,
                        validator: (value) => _validateRequired(value, 'school/college'),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Location field
                    profileState.when(
                      data: (profile) => _buildLabeledField(
                        label: 'Location (Optional)',
                        controller: _locationController,
                      ),
                      loading: () => _buildLabeledField(
                        label: 'Loading...',
                        controller: _locationController,
                        enabled: false,
                      ),
                      error: (error, stack) => _buildLabeledField(
                        label: 'Location (Optional) - Error loading data',
                        controller: _locationController,
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Bio field
                    profileState.when(
                      data: (profile) => _buildLabeledField(
                        label: 'Bio',
                        controller: _bioController,
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a short bio';
                          }
                          if (value.trim().length > 200) {
                            return 'Bio must be less than 200 characters';
                          }
                          return null;
                        },
                      ),
                      loading: () => _buildLabeledField(
                        label: 'Loading...',
                        controller: _bioController,
                        maxLines: 3,
                        enabled: false,
                      ),
                      error: (error, stack) => _buildLabeledField(
                        label: 'Bio - Error loading data',
                        controller: _bioController,
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a short bio';
                          }
                          if (value.trim().length > 200) {
                            return 'Bio must be less than 200 characters';
                          }
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Save button
                    profileState.when(
                      data: (profile) => Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 160,
                          child: ElevatedButton(
                            onPressed: _isUploading ? null : _saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isUploading
                                ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                strokeWidth: 2,
                              ),
                            )
                                : const Text(
                              'Save Profile',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                        ),
                      ),
                      error: (error, stack) => Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.error, color: Colors.red),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Error loading profile data',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 15),
                          Align(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: 160,
                              child: ElevatedButton(
                                onPressed: _isUploading ? null : _saveProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: _isUploading
                                    ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    strokeWidth: 2,
                                  ),
                                )
                                    : const Text(
                                  'Save Profile',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _userIdController.dispose();
    _schoolController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _roleController.dispose();
    super.dispose();
  }
}