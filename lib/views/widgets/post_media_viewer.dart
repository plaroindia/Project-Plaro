import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'Post_card.dart';

class PostMediaViewer extends ConsumerStatefulWidget {
  final List<String> mediaUrls;
  final int initialIndex;

  const PostMediaViewer({super.key, required this.mediaUrls, this.initialIndex = 0});

  @override
  ConsumerState<PostMediaViewer> createState() => _PostMediaViewerState();
}

class _PostMediaViewerState extends ConsumerState<PostMediaViewer> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isVideoUrl(String url) {
    final videoExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
    return videoExtensions.any((ext) => url.toLowerCase().contains(ext));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.mediaUrls.length,
              itemBuilder: (context, index) {
                final mediaUrl = widget.mediaUrls[index];
                return Center(
                  child: _isVideoUrl(mediaUrl)
                      ? VideoPlayerWidget(videoUrl: mediaUrl)
                      : InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Image.network(
                            mediaUrl,
                            fit: BoxFit.contain,
                            width: double.infinity,
                            height: double.infinity,
                          ),
                        ),
                );
              },
            ),
            Positioned(
              top: 40,
              right: 16,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


