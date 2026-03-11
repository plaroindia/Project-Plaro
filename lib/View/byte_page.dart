import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../ViewModel/byte_provider.dart';
import '../ViewModel/auth_provider.dart';
import '../ViewModel/setProfileProvider.dart';
import '../constants/domain_constants.dart';


class ByteCreateScreen extends ConsumerStatefulWidget {
  const ByteCreateScreen({super.key});

  @override
  ConsumerState<ByteCreateScreen> createState() => _ByteCreateScreenState();
}

class _ByteCreateScreenState extends ConsumerState<ByteCreateScreen> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _tagsController = TextEditingController();
  final FocusNode _tagsFocusNode = FocusNode();
  final FocusNode _captionFocusNode = FocusNode();
  VideoPlayerController? _videoController;

  String? _selectedDomain;
  String? _selectedSubdomain;
  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    _captionController.addListener(() {
      ref.read(byteCreateProvider.notifier).updateCaption(_captionController.text);
    });

    _tagsController.addListener(() {
      // Optional: you can add auto-suggestions here
    });

    // Load user profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = ref.read(authStateProvider).value;
      if (session != null) {
        ref.read(setProfileProvider.notifier).getUserProfile(session.user!.id);
      }
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _captionFocusNode.dispose();
    _tagsController.dispose();
    _tagsFocusNode.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _initializeVideoPlayer(String videoPath) {
    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(videoPath))
      ..initialize().then((_) {
        setState(() {});
        _videoController!.setLooping(true);
        _videoController!.play();
      });
  }

  void _addTag() {
    final tag = _tagsController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
      });
      ref.read(byteCreateProvider.notifier).updateTags(_tags);
      _tagsController.clear();
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
    ref.read(byteCreateProvider.notifier).updateTags(_tags);
  }

  void _showVideoPicker() {
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
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[600],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Select Video',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.red),
                title: const Text('Record Video', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Max 1 minute', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(byteCreateProvider.notifier).pickVideo(fromCamera: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library, color: Colors.blue),
                title: const Text('Video Library', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Max 1 minute', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(byteCreateProvider.notifier).pickVideo();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleCreateByte() async {
    final success = await ref.read(byteCreateProvider.notifier).createByte();
    if (success && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Byte created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Domain Dropdown Widget
  Widget _buildDomainDropdown() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selectedDomain == null ? Colors.red.withOpacity(0.5) : Colors.grey[700]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Text(
                  'Domain',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '*',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
                  child: Text(
                    'Select content domain',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
                  ),
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
                          Text(
                            domain['icon']!,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              domain['label']!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? value) {
                  setState(() {
                    _selectedDomain = value;
                    _selectedSubdomain = null;
                  });
                  if (value != null) {
                    ref.read(byteCreateProvider.notifier).updateDomain(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

// Subdomain Dropdown Widget
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: const Text(
              'Subdomain',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedSubdomain,
                hint: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Select subdomain (optional)',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                dropdownColor: Colors.grey[850],
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                items: subdomains.map((sub) {
                  return DropdownMenuItem<String>(
                    value: sub['value'],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        sub['label']!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSubdomain = value;
                  });
                  if (value != null) {
                    ref.read(byteCreateProvider.notifier).updateDomain(value);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

// Tags Input Widget
  Widget _buildTagsInput() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _tags.isEmpty ? Colors.red.withOpacity(0.5) : Colors.grey[700]!,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with mandatory indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Text(
                  'Tags',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  '*',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Helper text
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Use tags appropriate to your content to help others discover it',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),

          // Tag Input Row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _tagsController,
                  focusNode: _tagsFocusNode,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Add a tag (e.g., tutorial, tips, howto)',
                    hintStyle: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 16,
                    ),
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

          // Tags Display
          if (_tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
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
                        Text(
                          '#$tag',
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () => _removeTag(tag),
                          child: const Icon(
                            Icons.close,
                            color: Colors.blue,
                            size: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final byteCreateState = ref.watch(byteCreateProvider);
    final authState = ref.watch(authStateProvider);
    final profileState = ref.watch(setProfileProvider);

    // Initialize video player when video is selected
    if (byteCreateState.selectedVideo != null && _videoController == null) {
      _initializeVideoPlayer(byteCreateState.selectedVideo!.path);
    }

    // Show error messages
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (byteCreateState.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(byteCreateState.error!),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () => ref.read(byteCreateProvider.notifier).clearError(),
            ),
          ),
        );
      }
    });

    final canPost = byteCreateState.selectedVideo != null && !byteCreateState.isLoading;

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
          'Create Byte',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: canPost ? _handleCreateByte : null,
            child: byteCreateState.isLoading
                ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.blue,
                strokeWidth: 2,
              ),
            )
                : Text(
              'Post',
              style: TextStyle(
                color: canPost ? Colors.blue : Colors.grey,
                fontSize: 16,
                fontWeight: FontWeight.w600,
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
            // Video Selection/Preview
            Container(
              width: double.infinity,
              height: 400,
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: byteCreateState.selectedVideo == null
                  ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_library,
                    size: 64,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select a video to get started',
                    style: TextStyle(
                      color: Colors.grey[400],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showVideoPicker,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Video'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              )
                  : Stack(
                alignment: Alignment.center,
                children: [
                  if (_videoController != null && _videoController!.value.isInitialized)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      ),
                    )
                  else
                    const CircularProgressIndicator(color: Colors.blue),

                  // Video controls overlay
                  if (_videoController != null && _videoController!.value.isInitialized)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (_videoController!.value.isPlaying) {
                                  _videoController!.pause();
                                } else {
                                  _videoController!.play();
                                }
                              });
                            },
                            icon: Icon(
                              _videoController!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: VideoProgressIndicator(
                              _videoController!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.blue,
                                bufferedColor: Colors.grey,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              ref.read(byteCreateProvider.notifier).clearVideo();
                              _videoController?.dispose();
                              _videoController = null;
                              setState(() {});
                            },
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Change video button
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      onPressed: _showVideoPicker,
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.white,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        shape: const CircleBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Upload Progress
            if (byteCreateState.isUploading)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Uploading video...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: byteCreateState.uploadProgress,
                      backgroundColor: Colors.grey[700],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${(byteCreateState.uploadProgress * 100).toInt()}%',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

            _buildDomainDropdown(),
            _buildSubdomainDropdown(),

            // Caption Input
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _captionFocusNode.hasFocus ? Colors.blue : Colors.grey[700]!,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _captionController,
                focusNode: _captionFocusNode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
                maxLines: 3,
                maxLength: 280, // Twitter-like limit
                textInputAction: TextInputAction.done,
              ),
            ),

            const SizedBox(height: 16),
            _buildTagsInput(),
            const SizedBox(height: 24),

            // Tips section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tips_and_updates, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tips for great bytes',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTip('Keep it short and engaging (max 1 minute)'),
                  _buildTip('Use good lighting and clear audio'),
                  _buildTip('Start with a hook to grab attention'),
                  _buildTip('Add captions for better accessibility'),
                ],
              ),
            ),

            const SizedBox(height: 80), // Bottom spacing
          ],
        ),
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 8, right: 8),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}