import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Viewmodels/setprofileprovider.dart';
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
  // FIX: single master saving flag — covers both upload + DB write.
  // Previously _isUploading was reset inside _uploadProfileImage()'s finally
  // block BEFORE saveProfile finished, causing a setState-during-build crash
  // on the first save for new users.
  bool _isSaving = false;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _userIdController = TextEditingController();
  final TextEditingController _schoolController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();

  File? _profileImage;
  String? _profileImageUrl;

  final List<String> _roleOptions = ['Student', 'Professional', 'Learner'];
  String? _selectedRole;

  @override
  void initState() {
    super.initState();
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

  Future<void> _loadUserProfile() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        await ref.read(setProfileProvider.notifier).getUserProfile(user.id);
        final profileState = ref.read(setProfileProvider);
        profileState.whenData((profile) {
          if (profile != null && mounted) {
            _usernameController.text = profile.username;
            _userIdController.text = profile.user_id;
            _schoolController.text = profile.study ?? '';
            _bioController.text = profile.bio ?? '';
            _locationController.text = profile.location ?? '';
            _roleController.text = profile.role ?? '';
            setState(() {
              _profileImageUrl = profile.profilePic;
              if (profile.role != null &&
                  _roleOptions
                      .map((e) => e.toLowerCase())
                      .contains(profile.role!.toLowerCase())) {
                _selectedRole = _roleOptions.firstWhere(
                        (e) => e.toLowerCase() == profile.role!.toLowerCase());
              }
            });
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isInitialized = true);
    }
  }

  Future<void> _refreshProfile() async {
    setState(() {
      _isInitialized = false;
      _profileImage = null;
    });
    await _loadUserProfile();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      Navigator.pop(context); // close bottom sheet first
      final pickedImage = await ImagePicker().pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      if (pickedImage != null && mounted) {
        setState(() => _profileImage = File(pickedImage.path));
      }
    } catch (e) {
      _showSnackBar('Error selecting image: $e', isError: true);
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSheetOption(
            icon: Icons.delete,
            label: 'Remove Photo',
            onTap: () {
              setState(() {
                _profileImage = null;
                _profileImageUrl = null;
              });
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
      ),
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
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // FIX: upload now just uploads and returns the URL (no setState calls inside).
  // All state management is handled by _saveProfile.
  Future<String?> _uploadProfileImage(String userId) async {
    if (_profileImage == null) return null;

    try {
      final fileExtension = _profileImage!.path.split('.').last.toLowerCase();
      final fileName =
          'profile_${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExtension';
      final filePath = '$userId/$fileName';

      // Try to delete old image — non-fatal if it fails
      if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
        try {
          final uri = Uri.parse(_profileImageUrl!);
          final segments = uri.pathSegments;
          // path is: /storage/v1/object/public/avatars/{userId}/{filename}
          final avatarsIndex = segments.indexOf('avatars');
          if (avatarsIndex != -1 && avatarsIndex + 2 < segments.length) {
            final oldPath =
                '${segments[avatarsIndex + 1]}/${segments[avatarsIndex + 2]}';
            await Supabase.instance.client.storage
                .from('avatars')
                .remove([oldPath]);
          }
        } catch (_) {}
      }

      final response = await Supabase.instance.client.storage
          .from('avatars')
          .upload(filePath, _profileImage!);

      if (response.isEmpty) throw Exception('Upload returned empty path');

      final imageUrl = Supabase.instance.client.storage
          .from('avatars')
          .getPublicUrl(filePath);

      return imageUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      rethrow; // let _saveProfile handle it
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnackBar('User not authenticated', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? finalImageUrl = _profileImageUrl;

      // Upload image if a new one was selected
      if (_profileImage != null) {
        try {
          final uploadedUrl = await _uploadProfileImage(user.id);
          if (uploadedUrl != null) finalImageUrl = uploadedUrl;
        } catch (e) {
          // Image upload failed — show warning but continue saving profile
          // without the image. This way the user doesn't lose their text data.
          _showSnackBar(
              'Photo upload failed — profile saved without image update.',
              isError: true);
          // Don't return — keep going with existing image URL
        }
      }

      await ref.read(setProfileProvider.notifier).saveProfile(
        user_id: user.id,
        username: _usernameController.text.trim(),
        email: user.email,
        role: _selectedRole,
        profilePic: finalImageUrl,
        bio: _bioController.text.trim().isNotEmpty
            ? _bioController.text.trim()
            : null,
        study: _schoolController.text.trim().isNotEmpty
            ? _schoolController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        isVerified: false,
      );

      if (mounted) {
        setState(() {
          _profileImageUrl = finalImageUrl;
          _profileImage = null;
        });
        _showSnackBar('Profile saved!', isError: false);
        if (widget.isOnboarding) {
          Navigator.pushReplacementNamed(context, '/navipg');
        } else {
          Navigator.pop(context);
        }
      }
    } catch (error) {
      String msg = 'Failed to save profile';
      if (error is PostgrestException) msg = 'Database error: ${error.message}';
      else if (error is AuthException) msg = 'Auth error: ${error.message}';
      else if (error is StorageException) msg = 'Storage error: ${error.message}';
      else msg = error.toString();
      if (mounted) _showSnackBar(msg, isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error : Icons.check_circle, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: isError ? Colors.red : Colors.green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(10),
    ));
  }

  ImageProvider? _getDisplayImage() {
    if (_profileImage != null) return FileImage(_profileImage!);
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
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
            borderSide:
            BorderSide(color: Colors.grey.withOpacity(0.3), width: 1)),
        focusedBorder: UnderlineInputBorder(
            borderSide:
            BorderSide(color: Colors.blue.withOpacity(0.6), width: 1.3)),
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

    if (!_isInitialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUserProfile());
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title:
        const Text('Edit Profile', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isSaving ? null : _refreshProfile,
          ),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Profile picture ──────────────────────────────────────
                  Center(
                    child: Stack(
                      children: [
                        GestureDetector(
                          onTap: _isSaving ? null : _showImageOptions,
                          child: CircleAvatar(
                            radius: 60,
                            backgroundColor: Colors.grey[800],
                            backgroundImage: _getDisplayImage(),
                            child: _getDisplayImage() == null
                                ? const Icon(Icons.person,
                                size: 60, color: Colors.grey)
                                : null,
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: _isSaving ? null : _showImageOptions,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                  color: Colors.blue,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.edit,
                                  color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Username ─────────────────────────────────────────────
                  _buildLabeledField(
                    label: 'Username',
                    controller: _usernameController,
                    validator: (v) => _validateRequired(v, 'username'),
                  ),
                  const SizedBox(height: 20),

                  // ── Role ─────────────────────────────────────────────────
                  DropdownButtonFormField<String>(
                    value: _selectedRole,
                    dropdownColor: Colors.grey[900],
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Role',
                      labelStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Colors.grey.withOpacity(0.3), width: 1)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Colors.blue.withOpacity(0.6), width: 1.3)),
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                    ),
                    hint: const Text('Select Role',
                        style: TextStyle(color: Colors.grey)),
                    validator: (v) =>
                    v == null ? 'Please select a role' : null,
                    items: _roleOptions
                        .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r,
                            style:
                            const TextStyle(color: Colors.white))))
                        .toList(),
                    onChanged: _isSaving
                        ? null
                        : (v) => setState(() => _selectedRole = v),
                  ),
                  const SizedBox(height: 20),

                  // ── School ───────────────────────────────────────────────
                  _buildLabeledField(
                    label: 'School/College',
                    controller: _schoolController,
                    validator: (v) =>
                        _validateRequired(v, 'school/college'),
                  ),
                  const SizedBox(height: 20),

                  // ── Location ─────────────────────────────────────────────
                  _buildLabeledField(
                    label: 'Location (Optional)',
                    controller: _locationController,
                  ),
                  const SizedBox(height: 20),

                  // ── Bio ──────────────────────────────────────────────────
                  _buildLabeledField(
                    label: 'Bio',
                    controller: _bioController,
                    maxLines: 3,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Please enter a short bio';
                      }
                      if (v.trim().length > 200) {
                        return 'Bio must be less than 200 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),

                  // ── Save button ──────────────────────────────────────────
                  Align(
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 160,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                                strokeWidth: 2))
                            : const Text('Save Profile',
                            style: TextStyle(
                                fontSize: 15,
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}