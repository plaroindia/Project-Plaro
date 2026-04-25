// ViewModel/course_provider.dart
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

// Course Model Classes
class Course {
  final int courseId;
  final String userId;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? category;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CourseVideo>? videos;
  final int? totalVideos;
  final double? completionPercentage;

  Course({
    required this.courseId,
    required this.userId,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.category,
    required this.createdAt,
    required this.updatedAt,
    this.videos,
    this.totalVideos,
    this.completionPercentage,
  });

  factory Course.fromJson(Map<String, dynamic> json) {
    return Course(
      courseId: json['course_id'],
      userId: json['user_id'],
      title: json['title'],
      description: json['description'],
      thumbnailUrl: json['thumbnail_url'],
      category: json['category'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      totalVideos: json['total_videos'],
      completionPercentage: json['completion_percentage']?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course_id': courseId,
      'user_id': userId,
      'title': title,
      'description': description,
      'thumbnail_url': thumbnailUrl,
      'category': category,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class CourseVideo {
  final int videoId;
  final int courseId;
  final String title;
  final String? description;
  final String videoUrl;
  final Duration? duration;
  final int position;
  final DateTime createdAt;
  final VideoProgress? progress;

  CourseVideo({
    required this.videoId,
    required this.courseId,
    required this.title,
    this.description,
    required this.videoUrl,
    this.duration,
    required this.position,
    required this.createdAt,
    this.progress,
  });

  factory CourseVideo.fromJson(Map<String, dynamic> json) {
    return CourseVideo(
      videoId: json['video_id'],
      courseId: json['course_id'],
      title: json['title'],
      description: json['description'],
      videoUrl: json['video_url'],
      duration: json['duration'] != null ? _parseDuration(json['duration']) : null,
      position: json['position'],
      createdAt: DateTime.parse(json['created_at']),
      progress: json['progress'] != null ? VideoProgress.fromJson(json['progress']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'video_id': videoId,
      'course_id': courseId,
      'title': title,
      'description': description,
      'video_url': videoUrl,
      'duration': duration?.toString(),
      'position': position,
      'created_at': createdAt.toIso8601String(),
    };
  }

  static Duration _parseDuration(String duration) {
    // Parse PostgreSQL interval format
    final parts = duration.split(':');
    if (parts.length >= 3) {
      return Duration(
        hours: int.parse(parts[0]),
        minutes: int.parse(parts[1]),
        seconds: int.parse(parts[2].split('.')[0]),
      );
    }
    return Duration.zero;
  }
}

class VideoProgress {
  final int progressId;
  final int videoId;
  final String userId;
  final DateTime? lastWatchedAt;
  final int progressSeconds;
  final bool completed;

  VideoProgress({
    required this.progressId,
    required this.videoId,
    required this.userId,
    this.lastWatchedAt,
    required this.progressSeconds,
    required this.completed,
  });

  factory VideoProgress.fromJson(Map<String, dynamic> json) {
    return VideoProgress(
      progressId: json['progress_id'],
      videoId: json['video_id'],
      userId: json['user_id'],
      lastWatchedAt: json['last_watched_at'] != null ? DateTime.parse(json['last_watched_at']) : null,
      progressSeconds: json['progress_seconds'],
      completed: json['completed'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'progress_id': progressId,
      'video_id': videoId,
      'user_id': userId,
      'last_watched_at': lastWatchedAt?.toIso8601String(),
      'progress_seconds': progressSeconds,
      'completed': completed,
    };
  }
}

// Course State Class
class CourseState {
  final List<Course> allCourses;
  final List<Course> popularCourses;
  final List<Course> programmingCourses;
  final List<Course> designCourses;
  final List<Course> businessCourses;
  final List<Course> dataScienceCourses;
  final List<Course> myCourses;
  final String searchQuery;
  final dynamic filterOptions;
  final bool isLoading;
  final String? error;

  const CourseState({
    this.allCourses = const [],
    this.popularCourses = const [],
    this.programmingCourses = const [],
    this.designCourses = const [],
    this.businessCourses = const [],
    this.dataScienceCourses = const [],
    this.myCourses = const [],
    this.searchQuery = '',
    this.filterOptions,
    this.isLoading = false,
    this.error,
  });

  CourseState copyWith({
    List<Course>? allCourses,
    List<Course>? popularCourses,
    List<Course>? programmingCourses,
    List<Course>? designCourses,
    List<Course>? businessCourses,
    List<Course>? dataScienceCourses,
    List<Course>? myCourses,
    String? searchQuery,
    dynamic filterOptions,
    bool? isLoading,
    String? error,
  }) {
    return CourseState(
      allCourses: allCourses ?? this.allCourses,
      popularCourses: popularCourses ?? this.popularCourses,
      programmingCourses: programmingCourses ?? this.programmingCourses,
      designCourses: designCourses ?? this.designCourses,
      businessCourses: businessCourses ?? this.businessCourses,
      dataScienceCourses: dataScienceCourses ?? this.dataScienceCourses,
      myCourses: myCourses ?? this.myCourses,
      searchQuery: searchQuery ?? this.searchQuery,
      filterOptions: filterOptions ?? this.filterOptions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

// Course Notifier Class
class CourseFeedNotifier extends StateNotifier<CourseState> {
  CourseFeedNotifier() : super(const CourseState()) {
    loadCourses();
  }

  final _supabase = Supabase.instance.client;

  // Filtered course lists based on search and filters
  List<Course> get filteredPopularCourses => _filterCourses(state.popularCourses);
  List<Course> get filteredProgrammingCourses => _filterCourses(state.programmingCourses);
  List<Course> get filteredDesignCourses => _filterCourses(state.designCourses);
  List<Course> get filteredBusinessCourses => _filterCourses(state.businessCourses);
  List<Course> get filteredDataScienceCourses => _filterCourses(state.dataScienceCourses);

  List<Course> _filterCourses(List<Course> courses) {
    var filtered = courses;

    // Apply search filter
    if (state.searchQuery.isNotEmpty) {
      filtered = filtered.where((course) {
        final title = course.title.toLowerCase();
        final description = course.description?.toLowerCase() ?? '';
        final query = state.searchQuery.toLowerCase();
        return title.contains(query) || description.contains(query);
      }).toList();
    }

    // Apply other filters
    if (state.filterOptions != null) {
      if (state.filterOptions['category'] != null) {
        filtered = filtered.where((course) => course.category == state.filterOptions['category']).toList();
      }
    }

    return filtered;
  }

  // Load all courses
  Future<void> loadCourses() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _supabase
          .from('courses')
          .select('''
            *,
            course_videos!inner(count)
          ''')
          .order('created_at', ascending: false);

      final courses = (response as List).map((json) => Course.fromJson(json)).toList();

      // Group courses by category
      final popular = courses.take(6).toList();
      final programming = courses.where((c) => c.category == 'Programming').toList();
      final design = courses.where((c) => c.category == 'Design').toList();
      final business = courses.where((c) => c.category == 'Business').toList();
      final dataScience = courses.where((c) => c.category == 'Data Science').toList();

      state = state.copyWith(
        isLoading: false,
        allCourses: courses,
        popularCourses: popular,
        programmingCourses: programming,
        designCourses: design,
        businessCourses: business,
        dataScienceCourses: dataScience,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  // Load user's enrolled courses
  Future<void> loadMyCourses() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _supabase
          .from('courses')
          .select('''
            *,
            course_videos!inner(
              *,
              video_progress!left(*)
            )
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final myCourses = (response as List).map((json) => Course.fromJson(json)).toList();

      state = state.copyWith(myCourses: myCourses);
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // Create a new course
  Future<Course?> createCourse({
    required String title,
    String? description,
    String? thumbnailUrl,
    String? category,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from('courses')
          .insert({
        'user_id': userId,
        'title': title,
        'description': description,
        'thumbnail_url': thumbnailUrl,
        'category': category,
      })
          .select()
          .single();

      final newCourse = Course.fromJson(response);

      // Update state with new course
      state = state.copyWith(
        allCourses: [newCourse, ...state.allCourses],
        myCourses: [newCourse, ...state.myCourses],
      );

      return newCourse;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  // Add video to course
  Future<CourseVideo?> addVideoToCourse({
    required int courseId,
    required String title,
    String? description,
    required String videoUrl,
    Duration? duration,
    required int position,
  }) async {
    try {
      final response = await _supabase
          .from('course_videos')
          .insert({
        'course_id': courseId,
        'title': title,
        'description': description,
        'video_url': videoUrl,
        'duration': duration?.toString(),
        'position': position,
      })
          .select()
          .single();

      final newVideo = CourseVideo.fromJson(response);

      // Refresh courses to update video counts
      await loadCourses();

      return newVideo;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  // Get course with videos and progress
  Future<Course?> getCourseDetails(int courseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;

      final response = await _supabase
          .from('courses')
          .select('''
            *,
            course_videos!inner(
              *,
              video_progress!left(
                progress_id,
                last_watched_at,
                progress_seconds,
                completed
              )
            )
          ''')
          .eq('course_id', courseId)
          .single();

      // Process videos with progress
      final videosData = response['course_videos'] as List;
      final videos = videosData.map((videoJson) {
        VideoProgress? progress;
        if (videoJson['video_progress'] != null &&
            (videoJson['video_progress'] as List).isNotEmpty) {
          final progressData = (videoJson['video_progress'] as List)
              .firstWhere((p) => p['user_id'] == userId, orElse: () => null);
          if (progressData != null) {
            progress = VideoProgress.fromJson(progressData);
          }
        }

        return CourseVideo.fromJson({
          ...videoJson,
          'progress': progress?.toJson(),
        });
      }).toList();

      videos.sort((a, b) => a.position.compareTo(b.position));

      final course = Course.fromJson(response);
      return Course(
        courseId: course.courseId,
        userId: course.userId,
        title: course.title,
        description: course.description,
        thumbnailUrl: course.thumbnailUrl,
        category: course.category,
        createdAt: course.createdAt,
        updatedAt: course.updatedAt,
        videos: videos,
        totalVideos: videos.length,
        completionPercentage: _calculateCompletionPercentage(videos),
      );
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  // Update video progress
  Future<void> updateVideoProgress({
    required int videoId,
    required int progressSeconds,
    bool? completed,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await _supabase
          .from('video_progress')
          .upsert({
        'video_id': videoId,
        'user_id': userId,
        'last_watched_at': DateTime.now().toIso8601String(),
        'progress_seconds': progressSeconds,
        'completed': completed ?? false,
      });

      // Optionally refresh course data to update UI
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // Mark video as completed
  Future<void> markVideoCompleted(int videoId) async {
    await updateVideoProgress(
      videoId: videoId,
      progressSeconds: 0, // Will be updated with actual progress
      completed: true,
    );
  }

  // Get user's course progress
  Future<List<VideoProgress>> getUserProgress(int courseId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('video_progress')
          .select('''
            *,
            course_videos!inner(course_id)
          ''')
          .eq('user_id', userId)
          .eq('course_videos.course_id', courseId);

      return (response as List).map((json) => VideoProgress.fromJson(json)).toList();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  // Update course details
  Future<void> updateCourse({
    required int courseId,
    String? title,
    String? description,
    String? thumbnailUrl,
    String? category,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (title != null) updates['title'] = title;
      if (description != null) updates['description'] = description;
      if (thumbnailUrl != null) updates['thumbnail_url'] = thumbnailUrl;
      if (category != null) updates['category'] = category;
      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('courses')
          .update(updates)
          .eq('course_id', courseId);

      // Refresh courses
      await loadCourses();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // Delete course
  Future<void> deleteCourse(int courseId) async {
    try {
      await _supabase
          .from('courses')
          .delete()
          .eq('course_id', courseId);

      // Remove from state
      final updatedCourses = state.allCourses.where((c) => c.courseId != courseId).toList();
      state = state.copyWith(allCourses: updatedCourses);

      await loadCourses(); // Refresh all categories
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // Delete video from course
  Future<void> deleteVideo(int videoId) async {
    try {
      await _supabase
          .from('course_videos')
          .delete()
          .eq('video_id', videoId);

      // Refresh courses
      await loadCourses();
    } catch (e) {
      state = state.copyWith(error: e.toString());
    }
  }

  // Search and filter methods
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void applyFilters(dynamic filters) {
    state = state.copyWith(filterOptions: filters);
  }

  void clearFilters() {
    state = state.copyWith(
      filterOptions: null,
      searchQuery: '',
    );
  }

  // Helper method to calculate completion percentage
  double _calculateCompletionPercentage(List<CourseVideo> videos) {
    if (videos.isEmpty) return 0.0;

    final completedCount = videos.where((v) => v.progress?.completed == true).length;
    return (completedCount / videos.length) * 100;
  }

  // Get courses by category
  Future<List<Course>> getCoursesByCategory(String category) async {
    try {
      final response = await _supabase
          .from('courses')
          .select('*')
          .eq('category', category)
          .order('created_at', ascending: false);

      return (response as List).map((json) => Course.fromJson(json)).toList();
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return [];
    }
  }

  Future<String?> uploadThumbnail(Uint8List fileBytes, String fileName) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      // Include user ID in path for better organization and security
      final filePath = '$userId/$fileName';

      await _supabase.storage
          .from('course-thumbnails')
          .uploadBinary(filePath, fileBytes);

      final publicUrl = _supabase.storage
          .from('course-thumbnails')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }

  // Upload course video
  Future<String?> uploadVideo(Uint8List fileBytes, String fileName) async {
    try {
      await _supabase.storage
          .from('course-videos')
          .uploadBinary(fileName, fileBytes);

      final publicUrl = _supabase.storage
          .from('course-videos')
          .getPublicUrl(fileName);

      return publicUrl;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return null;
    }
  }
}

// Provider declaration
final courseFeedProvider = StateNotifierProvider<CourseFeedNotifier, CourseState>((ref) {
  return CourseFeedNotifier();
});

// Additional providers for specific functionality
final courseDetailProvider = FutureProvider.family<Course?, int>((ref, courseId) async {
  final notifier = ref.read(courseFeedProvider.notifier);
  return await notifier.getCourseDetails(courseId);
});

final userProgressProvider = FutureProvider.family<List<VideoProgress>, int>((ref, courseId) async {
  final notifier = ref.read(courseFeedProvider.notifier);
  return await notifier.getUserProgress(courseId);
});