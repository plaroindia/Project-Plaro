// widgets/video_player_page.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../Viewmodels/course_provider.dart';

class VideoPlayerPage extends ConsumerStatefulWidget {
  final CourseVideo video;
  final Course course;
  final List<CourseVideo>? playlist;

  const VideoPlayerPage({
    super.key,
    required this.video,
    required this.course,
    this.playlist,
  });

  @override
  ConsumerState<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends ConsumerState<VideoPlayerPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _isLoading = true;
  String? _error;
  int _currentVideoIndex = 0;
  List<CourseVideo> _playlist = [];

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist ?? [widget.video];
    _currentVideoIndex = _playlist.indexWhere((v) => v.videoId == widget.video.videoId);
    if (_currentVideoIndex == -1) _currentVideoIndex = 0;
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final currentVideo = _playlist[_currentVideoIndex];

      // Dispose previous controllers
      await _disposeControllers();

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(currentVideo.videoUrl),
      );

      await _videoPlayerController!.initialize();

      // Set up video position from saved progress
      if (currentVideo.progress != null && currentVideo.progress!.progressSeconds > 0) {
        await _videoPlayerController!.seekTo(
          Duration(seconds: currentVideo.progress!.progressSeconds),
        );
      }

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Theme.of(context).primaryColor,
          handleColor: Theme.of(context).primaryColor,
          backgroundColor: Colors.grey[300]!,
          bufferedColor: Colors.grey[400]!,
        ),
        placeholder: Container(
          color: Colors.black,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Container(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 48,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Error playing video',
                    style: TextStyle(color: Colors.white),
                  ),
                  SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Listen for video completion
      _videoPlayerController!.addListener(_videoListener);

      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _videoListener() {
    final controller = _videoPlayerController;
    if (controller == null) return;

    final position = controller.value.position;
    final duration = controller.value.duration;

    // Save progress every 5 seconds
    if (position.inSeconds % 5 == 0 && position.inSeconds > 0) {
      _saveProgress(position.inSeconds);
    }

    // Mark as completed when 90% watched
    if (duration.inSeconds > 0 && position.inSeconds / duration.inSeconds >= 0.9) {
      _markVideoCompleted();
    }
  }

  Future<void> _saveProgress(int progressSeconds) async {
    final notifier = ref.read(courseFeedProvider.notifier);
    await notifier.updateVideoProgress(
      videoId: _playlist[_currentVideoIndex].videoId,
      progressSeconds: progressSeconds,
    );
  }

  Future<void> _markVideoCompleted() async {
    final notifier = ref.read(courseFeedProvider.notifier);
    await notifier.markVideoCompleted(_playlist[_currentVideoIndex].videoId);
  }

  Future<void> _disposeControllers() async {
    _chewieController?.dispose();
    await _videoPlayerController?.dispose();
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _playPreviousVideo() {
    if (_currentVideoIndex > 0) {
      setState(() {
        _currentVideoIndex--;
      });
      _initializePlayer();
    }
  }

  void _playNextVideo() {
    if (_currentVideoIndex < _playlist.length - 1) {
      setState(() {
        _currentVideoIndex++;
      });
      _initializePlayer();
    }
  }

  void _showPlaylistModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Course Videos',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      '${_currentVideoIndex + 1} of ${_playlist.length}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _playlist.length,
                  itemBuilder: (context, index) {
                    final video = _playlist[index];
                    final isCurrentVideo = index == _currentVideoIndex;
                    final isCompleted = video.progress?.completed == true;

                    return ListTile(
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCurrentVideo
                              ? Theme.of(context).primaryColor
                              : isCompleted
                              ? Colors.green[600]
                              : Colors.grey[300],
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: isCurrentVideo
                              ? Icon(Icons.play_arrow, color: Colors.white, size: 16)
                              : isCompleted
                              ? Icon(Icons.check, color: Colors.white, size: 16)
                              : Text(
                            '${video.position}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ),
                      title: Text(
                        video.title,
                        style: TextStyle(
                          fontWeight: isCurrentVideo ? FontWeight.w600 : FontWeight.normal,
                          color: isCurrentVideo ? Theme.of(context).primaryColor : null,
                        ),
                      ),
                      subtitle: video.duration != null
                          ? Text(_formatDuration(video.duration!))
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        if (index != _currentVideoIndex) {
                          setState(() {
                            _currentVideoIndex = index;
                          });
                          _initializePlayer();
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentVideo = _playlist[_currentVideoIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          currentVideo.title,
          style: TextStyle(fontSize: 16),
        ),
        actions: [
          IconButton(
            onPressed: _showPlaylistModal,
            icon: Icon(Icons.playlist_play),
          ),
        ],
      ),
      body: Column(
        children: [
          // Video Player
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _buildVideoPlayer(),
            ),
          ),

          // Video Info and Controls
          Expanded(
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  // Video Title and Description
                  Container(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentVideo.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Course: ${widget.course.title}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (currentVideo.description != null) ...[
                          SizedBox(height: 12),
                          Text(
                            currentVideo.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Navigation Controls
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey[200]!),
                        bottom: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: Row(
                      children: [
                        // Previous Video Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _currentVideoIndex > 0 ? _playPreviousVideo : null,
                            icon: Icon(Icons.skip_previous),
                            label: Text('Previous'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[100],
                              foregroundColor: Colors.black87,
                              elevation: 0,
                            ),
                          ),
                        ),
                        SizedBox(width: 12),

                        // Next Video Button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _currentVideoIndex < _playlist.length - 1 ? _playNextVideo : null,
                            icon: Icon(Icons.skip_next),
                            label: Text('Next'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).primaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Playlist
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.all(16),
                      itemCount: _playlist.length,
                      itemBuilder: (context, index) {
                        final video = _playlist[index];
                        final isCurrentVideo = index == _currentVideoIndex;
                        final isCompleted = video.progress?.completed == true;

                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isCurrentVideo ? Theme.of(context).primaryColor.withOpacity(0.1) : null,
                            borderRadius: BorderRadius.circular(8),
                            border: isCurrentVideo
                                ? Border.all(color: Theme.of(context).primaryColor, width: 1)
                                : null,
                          ),
                          child: ListTile(
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isCurrentVideo
                                    ? Theme.of(context).primaryColor
                                    : isCompleted
                                    ? Colors.green[600]
                                    : Colors.grey[300],
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: isCurrentVideo
                                    ? Icon(Icons.play_arrow, color: Colors.white, size: 16)
                                    : isCompleted
                                    ? Icon(Icons.check, color: Colors.white, size: 16)
                                    : Text(
                                  '${video.position}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              video.title,
                              style: TextStyle(
                                fontWeight: isCurrentVideo ? FontWeight.w600 : FontWeight.normal,
                                color: isCurrentVideo ? Theme.of(context).primaryColor : null,
                              ),
                            ),
                            subtitle: video.duration != null
                                ? Text(_formatDuration(video.duration!))
                                : null,
                            onTap: () {
                              if (index != _currentVideoIndex) {
                                setState(() {
                                  _currentVideoIndex = index;
                                });
                                _initializePlayer();
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 48,
            ),
            SizedBox(height: 16),
            Text(
              'Error loading video',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[400], fontSize: 12),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _initializePlayer,
              child: Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized || _chewieController == null) {
      return Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Chewie(controller: _chewieController!);
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }
}

// Updated Course Detail Page with video playing functionality
class CourseDetailPage extends ConsumerStatefulWidget {
  final Course course;

  const CourseDetailPage({super.key, required this.course});

  @override
  ConsumerState<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends ConsumerState<CourseDetailPage> {
  int? expandedModuleIndex;
  Course? detailedCourse;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCourseDetails();
  }

  Future<void> _loadCourseDetails() async {
    final notifier = ref.read(courseFeedProvider.notifier);
    final courseWithVideos = await notifier.getCourseDetails(widget.course.courseId);

    setState(() {
      detailedCourse = courseWithVideos;
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final course = detailedCourse ?? widget.course;
    final videos = course.videos ?? [];
    final modules = _groupVideosByModule(videos);

    if (isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.course.title),
        ),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Course Header
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    course.thumbnailUrl ?? 'https://via.placeholder.com/400x250',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.grey[300],
                        child: Icon(
                          Icons.school,
                          size: 64,
                          color: Colors.grey,
                        ),
                      );
                    },
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        if (course.category != null)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              course.category!,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Course Stats
          SliverToBoxAdapter(
            child: Container(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(
                    icon: Icons.play_circle_outline,
                    label: 'Videos',
                    value: '${videos.length}',
                  ),
                  _StatItem(
                    icon: Icons.access_time,
                    label: 'Duration',
                    value: _getTotalDuration(videos),
                  ),
                  _StatItem(
                    icon: Icons.trending_up,
                    label: 'Progress',
                    value: '${course.completionPercentage?.toInt() ?? 0}%',
                  ),
                  _StatItem(
                    icon: Icons.date_range,
                    label: 'Created',
                    value: _formatDate(course.createdAt),
                  ),
                ],
              ),
            ),
          ),

          // Course Description
          if (course.description != null && course.description!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About this course',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      course.description!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 24),
                  ],
                ),
              ),
            ),

          // Course Content Header
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Course Content',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${videos.length} videos',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // Videos List (if no modules, show all videos)
          if (modules.isEmpty && videos.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final video = videos[index];
                  return _VideoListItem(
                    video: video,
                    onTap: () => _playVideo(video, videos),
                  );
                },
                childCount: videos.length,
              ),
            )
          else if (modules.isNotEmpty)
          // Video Modules List
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final module = modules[index];
                  final isExpanded = expandedModuleIndex == index;

                  return _ModuleSection(
                    module: module,
                    isExpanded: isExpanded,
                    onToggle: () {
                      setState(() {
                        expandedModuleIndex = isExpanded ? null : index;
                      });
                    },
                    onVideoTap: (video) => _playVideo(video, videos),
                  );
                },
                childCount: modules.length,
              ),
            )
          else
          // Empty state
            SliverToBoxAdapter(
              child: Container(
                margin: EdgeInsets.all(16),
                padding: EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.video_library_outlined,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No videos available',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: videos.isNotEmpty ? () => _startCourse(videos) : null,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  course.completionPercentage != null && course.completionPercentage! > 0
                      ? 'Continue Learning'
                      : 'Start Course',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            IconButton(
              onPressed: () => _toggleFavorite(),
              icon: Icon(Icons.favorite_border),
              iconSize: 24,
              color: Colors.grey[600],
            ),
            IconButton(
              onPressed: () => _showCourseOptions(),
              icon: Icon(Icons.more_vert),
              iconSize: 24,
              color: Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _groupVideosByModule(List<CourseVideo> videos) {
    if (videos.length <= 5) {
      return [];
    }

    final Map<String, List<CourseVideo>> moduleGroups = {};

    for (final video in videos) {
      String moduleName;
      if (video.position <= 3) {
        moduleName = 'Getting Started';
      } else if (video.position <= 6) {
        moduleName = 'Core Concepts';
      } else if (video.position <= 9) {
        moduleName = 'Advanced Topics';
      } else {
        moduleName = 'Bonus Content';
      }

      if (!moduleGroups.containsKey(moduleName)) {
        moduleGroups[moduleName] = [];
      }
      moduleGroups[moduleName]!.add(video);
    }

    return moduleGroups.entries.map((entry) => {
      'name': entry.key,
      'videos': entry.value,
    }).toList();
  }

  String _getTotalDuration(List<CourseVideo> videos) {
    var totalSeconds = 0;
    for (final video in videos) {
      if (video.duration != null) {
        totalSeconds += video.duration!.inSeconds;
      }
    }

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 1) {
      return 'Today';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  void _playVideo(CourseVideo video, List<CourseVideo> playlist) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VideoPlayerPage(
          video: video,
          course: detailedCourse ?? widget.course,
          playlist: playlist,
        ),
      ),
    );
  }

  void _startCourse(List<CourseVideo> videos) {
    if (videos.isNotEmpty) {
      _playVideo(videos.first, videos);
    }
  }

  void _toggleFavorite() {
    // Implement favorite functionality
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Favorite functionality not implemented yet'),
      ),
    );
  }

  void _showCourseOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                margin: EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(Icons.share),
                title: Text('Share Course'),
                onTap: () {
                  Navigator.pop(context);
                  // Implement share functionality
                },
              ),
              ListTile(
                leading: Icon(Icons.download),
                title: Text('Download for Offline'),
                onTap: () {
                  Navigator.pop(context);
                  // Implement download functionality
                },
              ),
              ListTile(
                leading: Icon(Icons.report),
                title: Text('Report Course'),
                onTap: () {
                  Navigator.pop(context);
                  // Implement report functionality
                },
              ),
              SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 24, color: Theme.of(context).primaryColor),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}

class _ModuleSection extends StatelessWidget {
  final Map<String, dynamic> module;
  final bool isExpanded;
  final VoidCallback onToggle;
  final Function(CourseVideo) onVideoTap;

  const _ModuleSection({
    required this.module,
    required this.isExpanded,
    required this.onToggle,
    required this.onVideoTap,
  });

  @override
  Widget build(BuildContext context) {
    final videos = module['videos'] as List<CourseVideo>;
    final completedVideos = videos.where((v) => v.progress?.completed == true).length;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Module Header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module['name'],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              '${videos.length} videos',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (completedVideos > 0) ...[
                              Text(
                                ' • $completedVideos completed',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (completedVideos == videos.length && videos.isNotEmpty)
                    Icon(
                      Icons.check_circle,
                      color: Colors.green[600],
                      size: 20,
                    ),
                  SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),

          // Video List
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 300),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: videos.map<Widget>((video) => _VideoListItem(
                video: video,
                onTap: () => onVideoTap(video),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoListItem extends StatelessWidget {
  final CourseVideo video;
  final VoidCallback onTap;

  const _VideoListItem({
    required this.video,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = video.progress?.completed == true;
    final progressSeconds = video.progress?.progressSeconds ?? 0;
    final totalSeconds = video.duration?.inSeconds ?? 0;
    final progressPercentage = totalSeconds > 0 ? (progressSeconds / totalSeconds) : 0.0;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            // Video Position Number
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isCompleted ? Colors.green[600] : Colors.grey[300],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: isCompleted
                    ? Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 16,
                )
                    : Text(
                  '${video.position}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),

            // Video Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      if (video.duration != null)
                        Text(
                          _formatDuration(video.duration!),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      if (progressPercentage > 0 && !isCompleted) ...[
                        SizedBox(width: 8),
                        Text(
                          '${(progressPercentage * 100).toInt()}% watched',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (progressPercentage > 0 && !isCompleted)
                    Container(
                      margin: EdgeInsets.only(top: 4),
                      height: 2,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progressPercentage,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue[600],
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Play/Download Icon
            IconButton(
              onPressed: onTap,
              icon: Icon(
                Icons.play_circle_outline,
                color: Theme.of(context).primaryColor,
              ),
              iconSize: 24,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }
}