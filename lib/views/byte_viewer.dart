import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/byte.dart';
import '../Viewmodels/byte_provider.dart';
import '../Viewmodels/auth_provider.dart';
import '../Viewmodels/follow_provider.dart';
import '../Viewmodels/content_event_tracker.dart';
import 'widgets/byte_comments.dart';
import 'widgets/double_tap_like.dart';
import 'byte_page.dart';
import 'widgets/follow_button.dart';
import 'byte_rating_dialogs.dart';
import 'profile.dart';

class ByteViewerPage extends ConsumerStatefulWidget {
  const ByteViewerPage({super.key});

  @override
  ConsumerState<ByteViewerPage> createState() => _ByteViewerPageState();
}

class _ByteViewerPageState extends ConsumerState<ByteViewerPage>
    with WidgetsBindingObserver {
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _controllers = {};

  // ── Dwell tracking ───────────────────────────────────────
  DateTime? _pageEnteredAt;

  // ── Preload timer: delays next-video init until current is playing ─────────
  // Prevents simultaneous HEVC decoder initialisation on MediaTek chips,
  // which exhausts ImageReader buffer slots ("Unable to acquire a buffer item").
  Timer? _preloadTimer;
  bool _isPageVisible = true;
  bool _isInitializing = false; // lock: only one decoder inits at a time

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ModalRoute.of detects whether this page is currently on top of the stack.
    final isVisible = ModalRoute.of(context)?.isCurrent ?? true;
    if (_isPageVisible && !isVisible) {
      // Navigated away — pause and flush dwell immediately
      _controllers[_currentIndex]?.pause();
      _flushDwell(_currentIndex); // safe: ref is still valid here
    } else if (!_isPageVisible && isVisible) {
      // Came back — resume
      final controller = _controllers[_currentIndex];
      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.isPlaying) {
        controller.play();
      }
    }
    _isPageVisible = isVisible;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = 0;
    _pageController = PageController(initialPage: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(bytesFeedProvider.notifier).loadBytes();
      _consumeFollowStatusCache();
      _recordPageEntry();
      // Initialize the first video immediately after load.
      // PageView's itemBuilder will have called _getController(0) by now.
      if (mounted) _initController(0);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preloadTimer?.cancel();
    _controllers[_currentIndex]?.pause();
    _pageController.dispose();
    _disposeAllControllers();
    // NOTE: Do NOT call _flushDwell here — ref is invalid during dispose()
    // in ConsumerStatefulWidget. Dwell is flushed on every page change and
    // on didChangeDependencies (route leave), so nothing is lost.
    super.dispose();
  }

  /// Pause when the user switches away from the app entirely,
  /// resume when they come back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _controllers[_currentIndex]?.pause();
    } else if (state == AppLifecycleState.resumed) {
      final controller = _controllers[_currentIndex];
      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.isPlaying) {
        controller.play();
      }
    }
  }

  void _disposeAllControllers() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
  }

  // ── Dwell helpers ────────────────────────────────────────

  void _recordPageEntry() {
    _pageEnteredAt = DateTime.now();
  }

  void _flushDwell(int index) {
    if (_pageEnteredAt == null) return;
    final dwellSeconds =
        DateTime.now().difference(_pageEnteredAt!).inSeconds;
    _pageEnteredAt = null; // clear so it's never double-flushed
    if (dwellSeconds < 1) return;

    final bytesState = ref.read(bytesFeedProvider);
    if (index >= bytesState.bytes.length) return;
    final byte = bytesState.bytes[index];
    final userId = ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId == null) return;

    ref.read(contentEventTrackerProvider).trackDwell(
      userId: userId,
      contentType: 'byte',
      contentIdInt: int.tryParse(byte.byteId),
      dwellTimeSeconds: dwellSeconds,
    );
  }

  // ── Video management ─────────────────────────────────────

  /// Returns (or creates) a controller for [index].
  /// IMPORTANT: Does NOT call .initialize() here.
  /// Initialization is driven by [_initController] which is called
  /// only when the page is actually current, or via [_schedulePreload]
  /// after the current video has started playing.
  VideoPlayerController _getController(int index, String videoUrl) {
    if (!_controllers.containsKey(index)) {
      debugPrint('🎥 Creating controller for index $index (not yet init)');
      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _controllers[index] = controller;
      // Do NOT initialize here — let _initController handle it sequentially.
    }
    return _controllers[index]!;
  }

  /// Actually initializes the controller for [index] and plays if current.
  /// All initialization goes through here so only one decoder spins up
  /// at a time on the MediaTek hardware.
  Future<void> _initController(int index) async {
    final controller = _controllers[index];
    if (controller == null) return;
    if (controller.value.isInitialized) {
      // Already ready — just play if it's the current page.
      if (index == _currentIndex && !controller.value.isPlaying) {
        controller.play();
        controller.setLooping(true);
      }
      return;
    }

    // Lock: bail if another decoder is already initializing.
    if (_isInitializing) {
      debugPrint('⏳ Already initializing, skipping index $index');
      return;
    }

    _isInitializing = true;
    debugPrint('🎥 Initializing controller for index $index');
    try {
      await controller.initialize();
      if (!mounted) return;
      setState(() {});
      if (index == _currentIndex) {
        controller.play();
        controller.setLooping(true);
        debugPrint('▶️ Playing video at index $index');
        // After current video has started, pre-init the next one
        // with a 500ms delay so the two decoders don't race.
        _schedulePreload(index + 1);
      }
    } catch (e) {
      debugPrint('❌ Error initializing video at $index: $e');
    } finally {
      _isInitializing = false;
    }
  }

  /// Schedules initialization of [nextIndex] after a short delay.
  /// The delay lets the current decoder finish its buffer setup before
  /// the next one starts competing for ImageReader slots.
  void _schedulePreload(int nextIndex) {
    _preloadTimer?.cancel();
    final bytes = ref.read(bytesFeedProvider).bytes;
    if (nextIndex >= bytes.length) return;
    if (_controllers[nextIndex]?.value.isInitialized == true) return;

    _preloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final bytes2 = ref.read(bytesFeedProvider).bytes;
      if (nextIndex < bytes2.length &&
          _controllers.containsKey(nextIndex) &&
          !(_controllers[nextIndex]?.value.isInitialized ?? false)) {
        debugPrint('⏩ Pre-loading controller for index $nextIndex');
        _initController(nextIndex);
      }
    });
  }

  /// Disposes controllers that are not the current or next index.
  /// On MediaTek chips, keeping even 3 decoders alive simultaneously
  /// exhausts ImageReader buffer slots — so we keep at most 2.
  void _pruneControllers(int currentIndex) {
    final toRemove = _controllers.keys
        .where((i) => i != currentIndex && i != currentIndex + 1)
        .toList();
    for (final i in toRemove) {
      debugPrint('🗑️ Disposing controller for index $i (pruned from $currentIndex)');
      _controllers[i]?.dispose();
      _controllers.remove(i);
    }
  }

  void _onPageChanged(int index) {
    debugPrint('🔄 Page changed from $_currentIndex to $index');

    // ── Flush dwell for the page we're leaving ────────────
    _flushDwell(_currentIndex);

    // Pause and reset previous video
    if (_controllers.containsKey(_currentIndex)) {
      final prevController = _controllers[_currentIndex]!;
      if (prevController.value.isInitialized) {
        prevController.pause();
        prevController.seekTo(Duration.zero);
        debugPrint('⏸️ Paused video at index $_currentIndex');
      }
    }

    setState(() {
      _currentIndex = index;
    });

    // ── Dispose controllers that are now too far away ─────
    _pruneControllers(index);

    // Reset init lock and cancel preload — current page must always be able to init
    _preloadTimer?.cancel();
    _isInitializing = false;

    // ── Track view for the new page ───────────────────────
    final bytesState = ref.read(bytesFeedProvider);
    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId != null && index < bytesState.bytes.length) {
      final byte = bytesState.bytes[index];
      ref.read(contentEventTrackerProvider).trackView(
        userId: userId,
        contentType: 'byte',
        contentIdInt: int.tryParse(byte.byteId),
        source: 'feed',
      );
    }

    // ── Start dwell timer for new page ───────────────────
    _recordPageEntry();

    // Initialize (or resume) the video for the new page sequentially.
    // _initController handles the "already initialized" fast-path and
    // schedules the next preload only after the current decoder is running.
    _initController(index);

    // Load more bytes when approaching the end
    if (index >= bytesState.bytes.length - 3 &&
        bytesState.hasMore &&
        !bytesState.isLoadingMore) {
      ref.read(bytesFeedProvider.notifier).loadMoreBytes().then((_) {
        if (mounted) _consumeFollowStatusCache();
      });
    }
  }

  /// Drains the follow-status cache populated by BytesFeedNotifier and pushes
  /// it into followProvider in one synchronous write. This ensures every
  /// FollowButton on the current page renders with the correct state on first
  /// paint, with no DB round-trip and no "Follow" flash.
  void _consumeFollowStatusCache() {
    if (!mounted) return;
    final cache = ref.read(bytesFeedProvider).followStatusCache;
    if (cache.isEmpty) return;
    ref.read(followProvider.notifier).seedFollowingStatus(cache);
    ref.read(bytesFeedProvider.notifier).clearFollowStatusCache();
  }

  void _togglePlayPause(int index) {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      setState(() {
        if (controller.value.isPlaying) {
          controller.pause();
          debugPrint('⏸️ Manually paused video at index $index');
        } else {
          controller.play();
          debugPrint('▶️ Manually playing video at index $index');
        }
      });
    }
  }

  // ── Like handler with event tracking ─────────────────────

  Future<void> _handleLike(Byte byte) async {
    await ref.read(bytesFeedProvider.notifier).toggleLike(byte.byteId);

    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId == null) return;

    // Only track the "like" signal (not unlike — the tracker doesn't
    // have an unlike event type; the engagement weight stays positive)
    final current = ref.read(bytesFeedProvider).bytes
        .firstWhere((b) => b.byteId == byte.byteId,
        orElse: () => byte);
    if (current.isliked == true) {
      ref.read(contentEventTrackerProvider).trackLike(
        userId: userId,
        contentType: 'byte',
        contentIdInt: int.tryParse(byte.byteId),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytesState = ref.watch(bytesFeedProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: bytesState.isLoading && bytesState.bytes.isEmpty
          ? Center(
        child: CircularProgressIndicator(color: Colors.white),
      )
          : bytesState.bytes.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library_outlined,
              color: Colors.grey[600],
              size: 80,
            ),
            SizedBox(height: 24),
            Text(
              'No bytes yet',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Be the first to create a byte!',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => ByteCreateScreen()),
                );
              },
              icon: Icon(Icons.add),
              label: Text('Create Byte'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (bytesState.error != null) ...[
              SizedBox(height: 24),
              Container(
                margin:
                EdgeInsets.symmetric(horizontal: 32),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        bytesState.error!,
                        style:
                        TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  ref
                      .read(bytesFeedProvider.notifier)
                      .refreshBytes();
                },
                icon: Icon(Icons.refresh),
                label: Text('Retry'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.blue,
                ),
              ),
            ],
          ],
        ),
      )
          : Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: bytesState.bytes.length,
            itemBuilder: (context, index) {
              final byte = bytesState.bytes[index];
              debugPrint(
                  '🗃️ Building page for index $index: ${byte.byteId}');

              return ByteVideoPlayer(
                byte: byte,
                controller:
                _getController(index, byte.videoUrl),
                isCurrentVideo: index == _currentIndex,
                onTogglePlayPause: () =>
                    _togglePlayPause(index),
                onLike: () => _handleLike(byte), // ✅ UPGRADED
                onSwipeLeft: () => _showCommentsModal(byte),
                onShare: () => _showShareModal(byte),
                showSwipeIndicator: true,
              );
            },
          ),
          // Loading more indicator
          if (bytesState.isLoadingMore)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Loading more...',
                        style: TextStyle(
                            color: Colors.white, fontSize: 12),
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

  void _showCommentsModal(Byte byte) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) =>
          ByteCommentsBottomSheet(byteId: byte.byteId),
    );
  }

  void _showShareModal(Byte byte) {
    final userId =
        ref.read(authStateProvider).valueOrNull?.user.id;
    if (userId != null) {
      ref.read(contentEventTrackerProvider).trackShare(
        userId: userId,
        contentType: 'byte',
        contentIdInt: int.tryParse(byte.byteId),
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ShareModal(byte: byte),
    );
  }
}

// ── ByteVideoPlayer (unchanged — all tracking is in the page widget) ─────────
// Keeping original implementation below; only the onLike callback now carries
// tracking logic from the caller.

class ByteVideoPlayer extends ConsumerStatefulWidget {
  final Byte byte;
  final VideoPlayerController controller;
  final bool isCurrentVideo;
  final VoidCallback onTogglePlayPause;
  final VoidCallback onLike;
  final VoidCallback onSwipeLeft;
  final VoidCallback onShare;
  final bool showSwipeIndicator;

  const ByteVideoPlayer({
    super.key,
    required this.byte,
    required this.controller,
    required this.isCurrentVideo,
    required this.onTogglePlayPause,
    required this.onLike,
    required this.onSwipeLeft,
    required this.onShare,
    this.showSwipeIndicator = true,
  });

  @override
  ConsumerState<ByteVideoPlayer> createState() =>
      _ByteVideoPlayerState();
}

class _ByteVideoPlayerState extends ConsumerState<ByteVideoPlayer> {
  @override
  void didUpdateWidget(ByteVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isCurrentVideo && oldWidget.isCurrentVideo) {
      if (widget.controller.value.isInitialized &&
          widget.controller.value.isPlaying) {
        widget.controller.pause();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final feedState = ref.watch(bytesFeedProvider);

    final currentByte = feedState.bytes.firstWhere(
          (b) => b.byteId == widget.byte.byteId,
      orElse: () => widget.byte,
    );

    debugPrint('🎬 Building ByteVideoPlayer for ${currentByte.byteId} - '
        'Initialized: ${widget.controller.value.isInitialized}, '
        'Playing: ${widget.controller.value.isPlaying}');

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! < -500) {
          widget.onSwipeLeft();
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video + double-tap like ────────────────────────────────────────
          ByteDoubleTapLike(
            byteId: currentByte.byteId,
            isliked: currentByte.isliked ?? false,
            onSingleTap: widget.onTogglePlayPause,
            onDoubleTapLike: widget.onLike,
            child: Container(
              color: Colors.black,
              child: widget.controller.value.isInitialized
                  ? Center(
                child: AspectRatio(
                  aspectRatio: widget.controller.value.aspectRatio,
                  child: VideoPlayer(widget.controller),
                ),
              )
                  : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text('Loading video…',
                        style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),

          // ── Play/pause overlay ─────────────────────────────────────────────
          if (widget.controller.value.isInitialized &&
              !widget.controller.value.isPlaying)
            IgnorePointer(
              child: Center(
                child: Container(
                  padding: EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
                  ),
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 44),
                ),
              ),
            ),

          // ── Bottom gradient ────────────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: IgnorePointer(
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Color(0x44000000),
                      Color(0xCC000000),
                      Colors.black,
                    ],
                    stops: [0.0, 0.35, 0.72, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // ── Right-side action column ───────────────────────────────────────
          Positioned(
            right: 12,
            bottom: 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: widget.onLike,
                  child: _SideActionItem(
                    icon: currentByte.isliked == true
                        ? Icons.favorite_rounded
                        : Icons.favorite_outline_rounded,
                    iconColor: currentByte.isliked == true
                        ? Colors.redAccent
                        : Colors.white,
                    label: _formatCount(currentByte.likeCount),
                  ),
                ),
                SizedBox(height: 20),
                ByteStarRatingIcon(byteId: currentByte.byteId),
                SizedBox(height: 20),
                ByteRankedByIcon(byteId: currentByte.byteId),
                SizedBox(height: 20),
                GestureDetector(
                  onTap: widget.onShare,
                  child: const _SideActionItem(
                    icon: Icons.reply_rounded,
                    iconColor: Colors.white70,
                    label: '',
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom info row ────────────────────────────────────────────────
          Positioned(
            bottom: 12,
            left: 12,
            right: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // Avatar + username: tappable to open profile
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          final currentUserId = ref.read(authStateProvider).valueOrNull?.user.id;
                          if (currentUserId != null && currentUserId != currentByte.userId) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OtherProfileScreen(
                                  userId: currentByte.userId,
                                ),
                              ),
                            );
                          }
                        },
                        child: Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [Color(0xFF0077FF), Color(0xFF00C6FF)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              padding: EdgeInsets.all(2),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Colors.grey.shade800,
                                backgroundImage: currentByte.profilePic != null
                                    ? CachedNetworkImageProvider(currentByte.profilePic!)
                                    : null,
                                child: currentByte.profilePic == null
                                    ? Text(
                                  (currentByte.username?.isNotEmpty ?? false)
                                      ? currentByte.username!.substring(0, 1).toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold),
                                )
                                    : null,
                              ),
                            ),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                '@${currentByte.username ?? "unknown"}',
                                style: TextStyle(
                                  color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700,
                                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 6),
                    if (authState.value?.user != null &&
                        authState.value!.user.id != currentByte.userId)
                    // ValueKey forces a fresh widget (and initState) when the
                    // userId changes (e.g. swiping to a byte from a new author).
                      FollowButton(
                        key: ValueKey('follow_${currentByte.userId}'),
                        targetUserId: currentByte.userId,
                        compact: true,
                      ),
                    SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _showMoreOptions(context, currentByte),
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                        ),
                        child: Icon(Icons.more_horiz, color: Colors.white, size: 30),
                      ),
                    ),
                  ],
                ),

                if (currentByte.caption != null && currentByte.caption!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      currentByte.caption!,
                      style: TextStyle(
                        color: Colors.white, fontSize: 13, height: 1.4,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                if (widget.controller.value.isInitialized)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: VideoProgressIndicator(
                        widget.controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.white,
                          bufferedColor: Colors.white30,
                          backgroundColor: Colors.white12,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Swipe-left comment hint ────────────────────────────────────────
          if (widget.showSwipeIndicator)
            Positioned(
              left: 12,
              bottom: MediaQuery.of(context).size.height * 0.42,
              child: Opacity(
                opacity: 0.75,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 18),
                    SizedBox(width: 2),
                    Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 16),
                    SizedBox(width: 4),
                    Text(
                      _formatCount(currentByte.commentCount),
                      style: TextStyle(
                          color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMoreOptions(BuildContext context, Byte byte) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => MoreOptionsModal(byte: byte),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }
}

// ── Reusable right-side action item ──────────────────────────────────────────
class _SideActionItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;

  const _SideActionItem({
    required this.icon,
    required this.iconColor,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        if (label.isNotEmpty) ...[
          SizedBox(height: 4),
          Text(label, style: TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          )),
        ],
      ],
    );
  }
}

class ShareModal extends StatelessWidget {
  final Byte byte;

  const ShareModal({super.key, required this.byte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'Share',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 24),
          ListTile(
            leading: Icon(Icons.link, color: Colors.white),
            title: Text('Copy Link', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Link copied to clipboard!'),
                  backgroundColor: Colors.blue,
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          ListTile(
            leading: Icon(Icons.message, color: Colors.white),
            title: Text('Share via Message', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.more_horiz, color: Colors.white),
            title: Text('More Options', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}

class MoreOptionsModal extends StatelessWidget {
  final Byte byte;

  const MoreOptionsModal({super.key, required this.byte});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'More Options',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 16),
          ListTile(
            leading: Icon(Icons.bookmark_outline, color: Colors.white),
            title: Text('Save', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.report_outlined, color: Colors.red),
            title: Text('Report', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: Icon(Icons.block, color: Colors.orange),
            title: Text('Block User', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(context),
          ),
          SizedBox(height: 16),
        ],
      ),
    );
  }
}