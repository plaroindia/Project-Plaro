import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/Post_card.dart';
import '../models/post.dart';
import 'dart:io';
import '../Viewmodels/post_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../Viewmodels/auth_provider.dart';
import '../Viewmodels/setProfileProvider.dart';
import '../constants/domain_constants.dart';
import '../service/moderation_service.dart';

class PostCreateScreen extends ConsumerStatefulWidget {
  const PostCreateScreen({super.key});

  @override
  ConsumerState<PostCreateScreen> createState() => _PostCreateScreenState();
}

class _PostCreateScreenState extends ConsumerState<PostCreateScreen> {
  final TextEditingController _titleController   = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _tagsController    = TextEditingController();
  final TextEditingController _budgetController  = TextEditingController();

  final FocusNode _titleFocusNode   = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  final FocusNode _captionFocusNode = FocusNode();
  final FocusNode _tagsFocusNode    = FocusNode();

  // ── Freelance local state ──────────────────────────────────────────────────
  bool   _isFreelance      = false;
  String _freelanceMinRank = 'beginner';
  bool   _requiresPro      = false;
  DateTime? _freelanceDeadline;

  final SupabaseClient _supabase = Supabase.instance.client;
  String? _selectedDomain;
  String? _selectedSubdomain;

  final bool _isExpanded = false;
  final List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(authStateProvider).value;
      if (session != null) {
        ref.read(setProfileProvider.notifier).getUserProfile(session.user.id);
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _captionController.dispose();
    _tagsController.dispose();
    _budgetController.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    _captionFocusNode.dispose();
    _tagsFocusNode.dispose();
    super.dispose();
  }

  void _addTag() {
    final tag = _tagsController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() => _tags.add(tag));
      ref.read(postCreateProvider.notifier).updateTags(_tags);
      _tagsController.clear();
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
    ref.read(postCreateProvider.notifier).updateTags(_tags);
  }

  Future<void> _handleCreatePost() async {
    final notifier = ref.read(postCreateProvider.notifier);
    notifier.updateTitle(_titleController.text);
    notifier.updateContent(_contentController.text);
    notifier.updateCaption(_captionController.text);

    final success = await notifier.createPost();
    if (success && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  bool _isVideoFile(String path) {
    const videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    return videoExtensions.any((ext) => path.toLowerCase().endsWith(ext));
  }

  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: const Text(
                  'Add Media',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Photo Library', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(postCreateProvider.notifier).pickMedia();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.green),
                title: const Text('Camera', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(postCreateProvider.notifier).pickMedia(fromCamera: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.red),
                title: const Text('Video Library', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(postCreateProvider.notifier).pickVideo();
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_call, color: Colors.orange),
                title: const Text('Record Video', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(postCreateProvider.notifier).pickVideo(fromCamera: true);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // ── Date picker helper ────────────────────────────────────────────────────

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF00BFA5),
            surface: Color(0xFF1E1E1E),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _freelanceDeadline = picked);
      ref.read(postCreateProvider.notifier).updateFreelanceDeadline(picked);
    }
  }

  // ── Freelance section ─────────────────────────────────────────────────────

  Widget _buildFreelanceSection() {
    const teal = Color(0xFF00BFA5);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isFreelance ? teal : Colors.grey[700]!,
          width: _isFreelance ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Toggle ──────────────────────────────────────────────────────
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
            title: Row(
              children: const [
                Text('💼 ', style: TextStyle(fontSize: 18)),
                Text(
                  'Post as Freelance Task',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Visible in Pearl Offers only — not the home feed',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),
            value: _isFreelance,
            activeColor: teal,
            onChanged: (v) {
              setState(() => _isFreelance = v);
              ref.read(postCreateProvider.notifier).toggleFreelance(v);
            },
          ),

          // ── Expanded fields (only when toggled on) ──────────────────────
          if (_isFreelance) ...[
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            const SizedBox(height: 12),

            // Budget
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _budgetController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Budget',
                  hintText: 'e.g. ₹2,000–₹5,000 or Negotiable',
                  hintStyle: TextStyle(color: Colors.grey[700], fontSize: 13),
                  labelStyle: TextStyle(color: Colors.grey[500]),
                  prefixIcon: const Icon(Icons.currency_rupee, color: Color(0xFF00BFA5), size: 18),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: teal),
                  ),
                ),
                onChanged: (v) =>
                    ref.read(postCreateProvider.notifier).updateFreelanceBudget(v),
              ),
            ),

            // Deadline
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GestureDetector(
                onTap: _pickDeadline,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, color: Color(0xFF00BFA5), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _freelanceDeadline == null
                              ? 'Deadline (optional)'
                              : 'Deadline: ${_freelanceDeadline!.day}/${_freelanceDeadline!.month}/${_freelanceDeadline!.year}',
                          style: TextStyle(
                            color: _freelanceDeadline == null
                                ? Colors.grey[500]
                                : Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_freelanceDeadline != null)
                        GestureDetector(
                          onTap: () {
                            setState(() => _freelanceDeadline = null);
                            ref
                                .read(postCreateProvider.notifier)
                                .updateFreelanceDeadline(null);
                          },
                          child: const Icon(Icons.close, color: Colors.grey, size: 18),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // Minimum rank
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Minimum rank required',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final rank in [
                        'beginner',
                        'intermediate',
                        'advanced',
                        'expert',
                        'master',
                      ])
                        ChoiceChip(
                          label: Text(
                            rank[0].toUpperCase() + rank.substring(1),
                            style: TextStyle(
                              color: _freelanceMinRank == rank
                                  ? Colors.black
                                  : Colors.grey[400],
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          selected: _freelanceMinRank == rank,
                          selectedColor: teal,
                          backgroundColor: Colors.grey[800],
                          side: BorderSide(
                            color: _freelanceMinRank == rank
                                ? teal
                                : Colors.grey[700]!,
                          ),
                          onSelected: (_) {
                            setState(() => _freelanceMinRank = rank);
                            ref
                                .read(postCreateProvider.notifier)
                                .updateFreelanceMinRank(rank);
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // Requires Pro
            SwitchListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
              title: Row(
                children: const [
                  Text('⭐ ', style: TextStyle(fontSize: 14)),
                  Text(
                    'Requires Pro subscription',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
              subtitle: Text(
                'Only Pro users will be eligible to apply',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              value: _requiresPro,
              activeColor: Colors.amber,
              onChanged: (v) {
                setState(() => _requiresPro = v);
                ref.read(postCreateProvider.notifier).toggleRequiresPro(v);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDomainDropdown() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedDomain == null
              ? Colors.red.withOpacity(0.5)
              : Colors.grey[700]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: const [
                Text('Domain',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(width: 4),
                Text('*', style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedDomain,
                hint: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Select content domain',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ),
                dropdownColor: Colors.grey[850],
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                items: DomainConstants.domains.map((domain) {
                  return DropdownMenuItem<String>(
                    value: domain['value'],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Text(domain['icon']!, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(domain['label']!,
                                style: const TextStyle(color: Colors.white, fontSize: 15)),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedDomain    = value;
                    _selectedSubdomain = null;
                  });
                  if (value != null) {
                    ref.read(postCreateProvider.notifier).updateDomain(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubdomainDropdown() {
    if (_selectedDomain == null) return const SizedBox();
    final subdomains = DomainConstants.subdomains[_selectedDomain] ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Subdomain',
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedSubdomain,
                hint: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Select subdomain (optional)',
                      style: TextStyle(color: Colors.grey[600])),
                ),
                dropdownColor: Colors.grey[850],
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                items: subdomains.map((sub) {
                  return DropdownMenuItem<String>(
                    value: sub['value'],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(sub['label']!, style: const TextStyle(color: Colors.white)),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedSubdomain = value);
                  if (value != null) {
                    ref.read(postCreateProvider.notifier).updateDomain(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final postCreateState = ref.watch(postCreateProvider);
    final screenHeight    = MediaQuery.of(context).size.height;
    final authState       = ref.watch(authStateProvider);
    final profileState    = ref.watch(setProfileProvider);

    final bool isBusy = postCreateState.isLoading || postCreateState.isModerating;

    // ── FIX: use ref.listen instead of addPostFrameCallback ──────────────────
    // addPostFrameCallback fires on EVERY rebuild, causing duplicate/stacked
    // snackbars when state changes rapidly (isLoading → isModerating → error).
    // ref.listen only fires when the specific value actually changes.
    ref.listen<String?>(
      postCreateProvider.select((s) => s.error),
          (previous, next) {
        if (next != null && next != previous && mounted) {
          // Clear any existing snackbars first so they don't stack
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Dismiss',
                textColor: Colors.white,
                onPressed: () {
                  ref.read(postCreateProvider.notifier).clearError();
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                },
              ),
            ),
          );
        }
      },
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Create Post',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: isBusy ? null : _handleCreatePost,
              child: isBusy
                  ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      color: Colors.blue, strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    postCreateState.isModerating
                        ? (postCreateState.moderationStatus ?? 'Checking…')
                        : 'Posting…',
                    style: TextStyle(color: Colors.blue.withOpacity(0.7), fontSize: 14),
                  ),
                ],
              )
                  : const Text(
                'Post',
                style: TextStyle(
                  color: Colors.blue, fontSize: 16, fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // Selected media preview
            if (postCreateState.selectedMedia.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: postCreateState.selectedMedia.length,
                        itemBuilder: (context, index) {
                          final media = postCreateState.selectedMedia[index];
                          return Container(
                            width: 120, height: 120,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: Colors.grey[800],
                            ),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _isVideoFile(media.path)
                                      ? Stack(children: [
                                    Container(
                                      width: 120, height: 120,
                                      color: Colors.grey[850],
                                      child: const Center(
                                        child: Icon(Icons.videocam, size: 40, color: Colors.white70),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: 4, left: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.play_arrow, size: 12, color: Colors.white),
                                            SizedBox(width: 2),
                                            Text('VIDEO',
                                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ])
                                      : Image.file(
                                    File(media.path),
                                    width: 120, height: 120,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 120, height: 120,
                                        color: Colors.grey[850],
                                        child: const Center(
                                          child: Icon(Icons.broken_image, size: 40, color: Colors.white54),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                Positioned(
                                  top: 4, right: 4,
                                  child: GestureDetector(
                                    onTap: () => ref.read(postCreateProvider.notifier).removeMedia(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            // Add Media Button
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: _showMediaPicker,
                icon: const Icon(Icons.add_photo_alternate, color: Colors.blue),
                label: const Text('Add Media', style: TextStyle(color: Colors.blue)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[700]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            _buildDomainDropdown(),
            _buildSubdomainDropdown(),

            // Title Input
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _titleFocusNode.hasFocus ? Colors.blue : Colors.grey[700]!,
                ),
              ),
              child: TextField(
                controller: _titleController,
                focusNode: _titleFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Add a title...',
                  hintStyle: TextStyle(color: Colors.grey[600], fontSize: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
                maxLines: 2,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _contentFocusNode.requestFocus(),
              ),
            ),

            // Content Input
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _contentFocusNode.hasFocus ? Colors.blue : Colors.grey[700]!,
                ),
              ),
              child: TextField(
                controller: _contentController,
                focusNode: _contentFocusNode,
                style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.5),
                decoration: InputDecoration(
                  hintText: "What's on your mind?",
                  hintStyle: TextStyle(color: Colors.grey[600], fontSize: 16),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
                maxLines: null,
                minLines: 5,
                textInputAction: TextInputAction.newline,
              ),
            ),

            // Tags Input
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _tags.isEmpty ? Colors.red.withOpacity(0.5) : Colors.grey[700]!,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: const [
                        Text('Tags',
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        SizedBox(width: 4),
                        Text('*', style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Text(
                      'Use tags appropriate to your content to help others discover it',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12, fontStyle: FontStyle.italic),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagsController,
                          focusNode: _tagsFocusNode,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Add a tag (e.g., tutorial, beginner, tips)',
                            hintStyle: TextStyle(color: Colors.grey[600], fontSize: 16),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                          onSubmitted: (_) => _addTag(),
                        ),
                      ),
                      IconButton(
                        onPressed: _addTag,
                        icon: const Icon(Icons.add, color: Colors.blue),
                      ),
                    ],
                  ),
                  if (_tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Wrap(
                        spacing: 8, runSpacing: 8,
                        children: _tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.blue.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('#$tag', style: const TextStyle(color: Colors.blue, fontSize: 14)),
                                const SizedBox(width: 4),
                                GestureDetector(
                                  onTap: () => _removeTag(tag),
                                  child: const Icon(Icons.close, color: Colors.blue, size: 16),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10.0),
            _buildFreelanceSection(),

            const SizedBox(height: 10.0),
            const Text('Preview', style: TextStyle(color: Colors.blue, fontSize: 14)),
            const Divider(thickness: 0.1),

            Padding(
              padding: const EdgeInsets.all(8.0),
              child: (_titleController.text.isEmpty &&
                  _contentController.text.isEmpty &&
                  _tags.isEmpty &&
                  postCreateState.selectedMedia.isEmpty)
                  ? const Center(
                  child: Text('Start typing to see a preview',
                      style: TextStyle(color: Colors.grey)))
                  : authState.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) =>
                    Center(child: Text('Error loading user data: $error')),
                data: (session) {
                  return profileState.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) =>
                        Center(child: Text('Error loading profile: $error')),
                    data: (profile) {
                      final userId     = session?.user.id ?? 'preview_user';
                      final username   = profile?.username ?? 'You';
                      final profilePic = profile?.profilePic;

                      return PostCard(
                        post: Post_feed(
                          post_id:         'preview_${DateTime.now().millisecondsSinceEpoch}',
                          user_id:         userId,
                          title:           _titleController.text,
                          content:         _contentController.text,
                          caption:         _captionController.text,
                          tags:            _tags,
                          localMediaFiles: postCreateState.selectedMedia,
                          username:        username,
                          profile_pic:     profilePic,
                          created_at:      DateTime.now(),
                          like_count:      0,
                          comment_count:   0,
                          share_count:     0,
                          isliked:         false,
                          commentsList:    [],
                        ),
                        isPreview: true,
                      );
                    },
                  );
                },
              ),
            ),

            SizedBox(height: screenHeight * 0.1),
          ],
        ),
      ),
    );
  }
}