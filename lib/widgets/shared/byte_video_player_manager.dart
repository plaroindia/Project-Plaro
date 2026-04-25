import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Manages video player controllers for byte videos
/// Handles initialization, disposal, and lifecycle management
class ByteVideoPlayerManager {
  final Map<int, VideoPlayerController> _controllers = {};
  int _currentIndex = 0;
  final ValueNotifier<int> currentIndexNotifier = ValueNotifier<int>(0);

  int get currentIndex => _currentIndex;
  int get controllerCount => _controllers.length;

  /// Get or create a video controller for the given index
  VideoPlayerController? getController(int index, String videoUrl) {
    if (!_controllers.containsKey(index)) {
      if (kDebugMode) {
        debugPrint('🎥 Creating video controller for index $index');
      }

      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _controllers[index] = controller;

      controller.initialize().then((_) {
        if (kDebugMode) {
          debugPrint('✅ Video initialized for index $index');
        }
      }).catchError((error) {
        if (kDebugMode) {
          debugPrint('❌ Error initializing video at index $index: $error');
        }
      });
    }
    return _controllers[index];
  }

  /// Update current index and manage video playback
  void onPageChanged(int newIndex) {
    if (kDebugMode) {
      debugPrint('🔄 Page changed from $_currentIndex to $newIndex');
    }

    // Pause and reset previous video
    final prevController = _controllers[_currentIndex];
    if (prevController != null && prevController.value.isInitialized) {
      prevController.pause();
      prevController.seekTo(Duration.zero);
    }

    _currentIndex = newIndex;
    currentIndexNotifier.value = newIndex;

    // Play new video if initialized
    final newController = _controllers[newIndex];
    if (newController != null && newController.value.isInitialized) {
      newController.seekTo(Duration.zero);
      newController.play();
      newController.setLooping(true);
    }
  }

  /// Toggle play/pause for a specific video
  void togglePlayPause(int index) {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    }
  }

  /// Dispose all controllers
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    currentIndexNotifier.dispose();
  }

  /// Dispose a specific controller
  void disposeController(int index) {
    final controller = _controllers.remove(index);
    controller?.dispose();
  }

  /// Check if a controller is initialized
  bool isInitialized(int index) {
    return _controllers[index]?.value.isInitialized ?? false;
  }

  /// Check if a video is playing
  bool isPlaying(int index) {
    return _controllers[index]?.value.isPlaying ?? false;
  }
}

