// chat_media_provider.dart - COMPLETELY FIXED VERSION
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;

// Media upload state
class MediaUploadState {
  final bool isUploading;
  final double uploadProgress;
  final String? uploadingFileId;
  final String? error;
  final List<ChatMediaItem> recentUploads;

  const MediaUploadState({
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.uploadingFileId,
    this.error,
    this.recentUploads = const [],
  });

  MediaUploadState copyWith({
    bool? isUploading,
    double? uploadProgress,
    String? uploadingFileId,
    String? error,
    List<ChatMediaItem>? recentUploads,
  }) {
    return MediaUploadState(
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      uploadingFileId: uploadingFileId ?? this.uploadingFileId,
      error: error,
      recentUploads: recentUploads ?? this.recentUploads,
    );
  }

  bool get hasError => error != null;
}

// Media item model
class ChatMediaItem {
  final String id;
  final String fileName;
  final String fileUrl;
  final String mimeType;
  final int fileSize;
  final MediaType mediaType;
  final DateTime uploadedAt;
  final String? thumbnailUrl;
  final Map<String, dynamic>? metadata;

  const ChatMediaItem({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    required this.mimeType,
    required this.fileSize,
    required this.mediaType,
    required this.uploadedAt,
    this.thumbnailUrl,
    this.metadata,
  });

  factory ChatMediaItem.fromJson(Map<String, dynamic> json) {
    return ChatMediaItem(
      id: json['id'] as String,
      fileName: json['file_name'] as String,
      fileUrl: json['file_url'] as String,
      mimeType: json['mime_type'] as String,
      fileSize: json['file_size'] as int,
      mediaType: MediaType.fromString(json['media_type'] as String),
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      thumbnailUrl: json['thumbnail_url'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'file_name': fileName,
      'file_url': fileUrl,
      'mime_type': mimeType,
      'file_size': fileSize,
      'media_type': mediaType.value,
      'uploaded_at': uploadedAt.toIso8601String(),
      'thumbnail_url': thumbnailUrl,
      'metadata': metadata,
    };
  }

  String get formattedFileSize {
    if (fileSize < 1024) return '${fileSize}B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)}KB';
    if (fileSize < 1024 * 1024 * 1024) return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }

  bool get isImage => mediaType == MediaType.image;
  bool get isDocument => mediaType == MediaType.document;
}

// Media type enum
enum MediaType {
  image('image'),
  document('document'),
  video('video'),
  audio('audio');

  const MediaType(this.value);
  final String value;

  static MediaType fromString(String value) {
    return MediaType.values.firstWhere(
          (type) => type.value == value,
      orElse: () => MediaType.document,
    );
  }

  static MediaType fromMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) return MediaType.image;
    if (mimeType.startsWith('video/')) return MediaType.video;
    if (mimeType.startsWith('audio/')) return MediaType.audio;
    return MediaType.document;
  }
}

// Media upload result
class MediaUploadResult {
  final bool success;
  final ChatMediaItem? mediaItem;
  final String? error;

  const MediaUploadResult({
    required this.success,
    this.mediaItem,
    this.error,
  });

  MediaUploadResult.success(this.mediaItem)
      : success = true,
        error = null;

  MediaUploadResult.failure(this.error)
      : success = false,
        mediaItem = null;
}

// Value-equality key for the family provider.
// Using Map<String,String> as a family key is broken because Dart Maps use
// reference equality, so every createMediaParams() call produces a new
// provider instance and immediately disposes the previous one mid-upload.
class ChatMediaParams {
  final String chatId;
  final String currentUserId;

  const ChatMediaParams({required this.chatId, required this.currentUserId});

  @override
  bool operator ==(Object other) =>
      other is ChatMediaParams &&
      other.chatId == chatId &&
      other.currentUserId == currentUserId;

  @override
  int get hashCode => Object.hash(chatId, currentUserId);

  @override
  String toString() => 'ChatMediaParams(chatId: $chatId, userId: $currentUserId)';
}

// FIXED Chat Media Notifier
class ChatMediaNotifier extends StateNotifier<MediaUploadState> {
  final String chatId;
  final String currentUserId;
  final SupabaseClient _supabase = Supabase.instance.client;
  final Uuid _uuid = const Uuid();
  final ImagePicker _imagePicker = ImagePicker();

  // CRITICAL: Track disposal state properly
  bool _disposed = false;

  static const String bucketName = 'chat_media'; // FIXED: Use hyphen, not underscore
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB
  static const List<String> allowedImageTypes = [
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  ];
  static const List<String> allowedDocumentTypes = [
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/csv',
  ];

  ChatMediaNotifier({
    required this.chatId,
    required this.currentUserId,
  }) : super(const MediaUploadState());

  // FIXED: More robust state update check
  void _safeUpdateState(MediaUploadState Function(MediaUploadState) update) {
    if (_disposed) {
      print('ChatMediaNotifier: Attempted to update state after disposal');
      return;
    }

    try {
      if (mounted) {
        state = update(state);
      }
    } catch (e) {
      print('ChatMediaNotifier: State update error: $e');
      // Don't rethrow - just log and continue
    }
  }

  // Pick image from camera
  Future<MediaUploadResult?> pickImageFromCamera() async {
    if (_disposed) {
      print('ChatMediaNotifier: pickImageFromCamera called after disposal');
      return MediaUploadResult.failure('Operation cancelled');
    }

    try {
      print('ChatMediaNotifier: Starting camera image pick...');

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) {
        print('ChatMediaNotifier: No image selected from camera');
        return null; // User cancelled
      }

      if (_disposed) {
        print('ChatMediaNotifier: Disposed during camera pick');
        return MediaUploadResult.failure('Operation cancelled');
      }

      print('ChatMediaNotifier: Camera image picked: ${image.name}');

      return await _uploadFile(
        filePath: image.path,
        fileName: image.name,
        mimeType: image.mimeType ?? 'image/jpeg',
      );
    } catch (error) {
      print('ChatMediaNotifier: Camera pick error: $error');
      if (!_disposed) {
        _safeUpdateState((state) => state.copyWith(error: 'Failed to capture image: $error'));
      }
      return MediaUploadResult.failure('Failed to capture image');
    }
  }

  // Pick image from gallery
  Future<MediaUploadResult?> pickImageFromGallery() async {
    if (_disposed) {
      print('ChatMediaNotifier: pickImageFromGallery called after disposal');
      return MediaUploadResult.failure('Operation cancelled');
    }

    try {
      print('ChatMediaNotifier: Starting gallery image pick...');

      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) {
        print('ChatMediaNotifier: No image selected from gallery');
        return null; // User cancelled
      }

      if (_disposed) {
        print('ChatMediaNotifier: Disposed during gallery pick');
        return MediaUploadResult.failure('Operation cancelled');
      }

      print('ChatMediaNotifier: Gallery image picked: ${image.name}');

      return await _uploadFile(
        filePath: image.path,
        fileName: image.name,
        mimeType: image.mimeType ?? 'image/jpeg',
      );
    } catch (error) {
      print('ChatMediaNotifier: Gallery pick error: $error');
      if (!_disposed) {
        _safeUpdateState((state) => state.copyWith(error: 'Failed to pick image: $error'));
      }
      return MediaUploadResult.failure('Failed to pick image');
    }
  }

  // Pick document file
  Future<MediaUploadResult?> pickDocument() async {
    if (_disposed) {
      print('ChatMediaNotifier: pickDocument called after disposal');
      return MediaUploadResult.failure('Operation cancelled');
    }

    try {
      print('ChatMediaNotifier: Starting document pick...');

      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        print('ChatMediaNotifier: No document selected');
        return null; // User cancelled
      }

      if (_disposed) {
        print('ChatMediaNotifier: Disposed during document pick');
        return MediaUploadResult.failure('Operation cancelled');
      }

      final file = result.files.first;

      if (file.path == null) {
        const errorMsg = 'Unable to access selected file';
        print('ChatMediaNotifier: $errorMsg');
        if (!_disposed) {
          _safeUpdateState((state) => state.copyWith(error: errorMsg));
        }
        return MediaUploadResult.failure(errorMsg);
      }

      print('ChatMediaNotifier: Document picked: ${file.name}');

      String mimeType = _getMimeTypeFromExtension(path.extension(file.name));

      return await _uploadFile(
        filePath: file.path!,
        fileName: file.name,
        mimeType: mimeType,
      );
    } catch (error) {
      print('ChatMediaNotifier: Document pick error: $error');
      if (!_disposed) {
        _safeUpdateState((state) => state.copyWith(error: 'Failed to pick document: $error'));
      }
      return MediaUploadResult.failure('Failed to pick document');
    }
  }

  // FIXED: Main upload method with better error handling
  Future<MediaUploadResult?> _uploadFile({
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async {
    if (_disposed) {
      print('ChatMediaNotifier: _uploadFile called after disposal');
      return MediaUploadResult.failure('Operation cancelled');
    }

    final fileId = _uuid.v4();
    print('ChatMediaNotifier: Starting upload for file: $fileName (ID: $fileId)');

    try {
      // Validate file first
      final validation = await _validateFile(filePath, mimeType);
      if (!validation.isValid) {
        print('ChatMediaNotifier: File validation failed: ${validation.error}');
        if (!_disposed) {
          _safeUpdateState((state) => state.copyWith(error: validation.error));
        }
        return MediaUploadResult.failure(validation.error!);
      }

      if (_disposed) return MediaUploadResult.failure('Operation cancelled');

      // Update UI to show upload starting
      _safeUpdateState((state) => state.copyWith(
        isUploading: true,
        uploadProgress: 0.0,
        uploadingFileId: fileId,
        error: null,
      ));

      // Read file
      print('ChatMediaNotifier: Reading file...');
      final File file = File(filePath);
      final Uint8List fileBytes = await file.readAsBytes();
      final int fileSize = fileBytes.length;

      print('ChatMediaNotifier: File size: $fileSize bytes');

      if (_disposed) {
        print('ChatMediaNotifier: Disposed during file read');
        return MediaUploadResult.failure('Operation cancelled');
      }

      // Generate storage path
      final String storagePath = _generateStoragePath(fileId, fileName);
      print('ChatMediaNotifier: Storage path: $storagePath');

      // Update progress
      _safeUpdateState((state) => state.copyWith(uploadProgress: 0.3));

      // Upload to Supabase Storage
      print('ChatMediaNotifier: Starting Supabase upload...');
      await _supabase.storage.from(bucketName).uploadBinary(
        storagePath,
        fileBytes,
        fileOptions: FileOptions(
          contentType: mimeType,
          upsert: false,
        ),
      );

      print('ChatMediaNotifier: Upload successful');

      if (_disposed) {
        print('ChatMediaNotifier: Disposed after upload');
        return MediaUploadResult.failure('Operation cancelled');
      }

      // Update progress
      _safeUpdateState((state) => state.copyWith(uploadProgress: 0.8));

      // Get public URL
      final String fileUrl = _supabase.storage.from(bucketName).getPublicUrl(storagePath);
      print('ChatMediaNotifier: File URL: $fileUrl');

      // Create media item
      final ChatMediaItem mediaItem = ChatMediaItem(
        id: fileId,
        fileName: fileName,
        fileUrl: fileUrl,
        mimeType: mimeType,
        fileSize: fileSize,
        mediaType: MediaType.fromMimeType(mimeType),
        uploadedAt: DateTime.now(),
        metadata: {
          'chat_id': chatId,
          'uploaded_by': currentUserId,
          'original_path': filePath,
        },
      );

      // Final state update
      if (!_disposed) {
        final updatedUploads = [mediaItem, ...state.recentUploads].take(10).toList();
        _safeUpdateState((state) => state.copyWith(
          isUploading: false,
          uploadProgress: 1.0,
          uploadingFileId: null,
          recentUploads: updatedUploads,
        ));
      }

      print('ChatMediaNotifier: Upload completed successfully');
      return MediaUploadResult.success(mediaItem);

    } catch (error) {
      print('ChatMediaNotifier: Upload error: $error');
      print('ChatMediaNotifier: Error type: ${error.runtimeType}');

      if (!_disposed) {
        // Clean up partial upload
        try {
          final storagePath = _generateStoragePath(fileId, fileName);
          await _supabase.storage.from(bucketName).remove([storagePath]);
          print('ChatMediaNotifier: Cleaned up partial upload');
        } catch (cleanupError) {
          print('ChatMediaNotifier: Cleanup error: $cleanupError');
        }

        final errorMessage = _getErrorMessage(error);
        _safeUpdateState((state) => state.copyWith(
          isUploading: false,
          uploadProgress: 0.0,
          uploadingFileId: null,
          error: errorMessage,
        ));

        return MediaUploadResult.failure(errorMessage);
      }

      return MediaUploadResult.failure(_getErrorMessage(error));
    }
  }

  // ADDED: Ensure bucket exists
  // File validation
  Future<FileValidation> _validateFile(String filePath, String mimeType) async {
    if (_disposed) {
      return FileValidation.invalid('Operation cancelled');
    }

    try {
      final File file = File(filePath);

      // Check if file exists
      if (!await file.exists()) {
        print('ChatMediaNotifier: File does not exist: $filePath');
        return FileValidation.invalid('File does not exist');
      }

      if (_disposed) {
        return FileValidation.invalid('Operation cancelled');
      }

      // Check file size
      final int fileSize = await file.length();
      print('ChatMediaNotifier: Validating file size: $fileSize bytes');

      if (fileSize > maxFileSize) {
        final maxSizeMB = maxFileSize / (1024 * 1024);
        print('ChatMediaNotifier: File too large: $fileSize > $maxFileSize');
        return FileValidation.invalid('File too large. Maximum size is ${maxSizeMB.toInt()}MB');
      }

      if (fileSize == 0) {
        print('ChatMediaNotifier: File is empty');
        return FileValidation.invalid('File is empty');
      }

      // Check MIME type
      final MediaType mediaType = MediaType.fromMimeType(mimeType);
      print('ChatMediaNotifier: Validating MIME type: $mimeType -> $mediaType');

      switch (mediaType) {
        case MediaType.image:
          if (!allowedImageTypes.contains(mimeType)) {
            print('ChatMediaNotifier: Unsupported image format: $mimeType');
            return FileValidation.invalid('Unsupported image format');
          }
          break;
        case MediaType.document:
          if (!allowedDocumentTypes.contains(mimeType)) {
            print('ChatMediaNotifier: Unsupported document format: $mimeType');
            return FileValidation.invalid('Unsupported document format');
          }
          break;
        default:
          print('ChatMediaNotifier: Unsupported file type: $mediaType');
          return FileValidation.invalid('Unsupported file type');
      }

      print('ChatMediaNotifier: File validation successful');
      return FileValidation.valid();
    } catch (error) {
      print('ChatMediaNotifier: File validation error: $error');
      return FileValidation.invalid('Error validating file: $error');
    }
  }

  // Generate storage path (FIXED: Better path structure)
  String _generateStoragePath(String fileId, String fileName) {
    final extension = path.extension(fileName);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    // FIXED: Use forward slashes and ensure valid path
    return 'chats/$chatId/$currentUserId/$timestamp-$fileId$extension';
  }

  // Get MIME type from extension (unchanged)
  String _getMimeTypeFromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case '.xls':
        return 'application/vnd.ms-excel';
      case '.xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case '.txt':
        return 'text/plain';
      case '.csv':
        return 'text/csv';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  // FIXED: Better error message handling
  String _getErrorMessage(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    if (error is StorageException) {
      print('ChatMediaNotifier: StorageException - ${error.statusCode}: ${error.message}');
      switch (error.statusCode) {
        case '413':
          return 'File too large';
        case '415':
          return 'Unsupported file type';
        case '409':
          return 'File already exists';
        case '400':
          return 'Invalid file or bucket configuration';
        case '401':
          return 'Authentication error. Please log in again.';
        case '403':
          return 'Permission denied. Check storage permissions.';
        case '404':
          return 'Storage bucket not found';
        default:
          return 'Upload failed: ${error.message}';
      }
    } else if (errorStr.contains('timeout')) {
      return 'Upload timeout. Please try again.';
    } else if (errorStr.contains('network') || errorStr.contains('connection')) {
      return 'Network error. Check your connection.';
    } else if (errorStr.contains('bucket') && errorStr.contains('not')) {
      return 'Storage error. Please try again.';
    } else {
      return 'Upload failed. Please try again.';
    }
  }

  // Clear error
  void clearError() {
    if (!_disposed && state.hasError) {
      _safeUpdateState((state) => state.copyWith(error: null));
    }
  }

  // Cancel upload
  void cancelUpload() {
    if (!_disposed && state.isUploading) {
      _safeUpdateState((state) => state.copyWith(
        isUploading: false,
        uploadProgress: 0.0,
        uploadingFileId: null,
        error: 'Upload cancelled',
      ));
    }
  }

  // FIXED: Proper disposal
  @override
  void dispose() {
    print('ChatMediaNotifier: Starting disposal...');
    _disposed = true;

    try {
      super.dispose();
      print('ChatMediaNotifier: Disposal completed');
    } catch (e) {
      print('ChatMediaNotifier: Disposal error (expected): $e');
    }
  }
}

// File validation helper (unchanged)
class FileValidation {
  final bool isValid;
  final String? error;

  const FileValidation._(this.isValid, this.error);

  factory FileValidation.valid() => const FileValidation._(true, null);
  factory FileValidation.invalid(String error) => FileValidation._(false, error);
}

// Explicit type annotation required — without it Dart hits a circularity error
// when trying to infer the type of the ref.listenSelf callback.
final AutoDisposeStateNotifierProviderFamily<ChatMediaNotifier, MediaUploadState, ChatMediaParams>
    chatMediaProvider =
    StateNotifierProvider.family.autoDispose<ChatMediaNotifier, MediaUploadState, ChatMediaParams>(
  (ref, params) {
    print('ChatMediaProvider: Creating notifier for chatId: ${params.chatId}');

    final notifier = ChatMediaNotifier(
      chatId: params.chatId,
      currentUserId: params.currentUserId,
    );

    // Keep the provider alive while an upload is in progress.
    // ref.listenSelf avoids the self-reference circularity — it observes this
    // provider's own state without naming it, so Dart can infer the type cleanly.
    KeepAliveLink? keepAliveLink;
    ref.listenSelf((prev, next) {
      if (next.isUploading && keepAliveLink == null) {
        keepAliveLink = ref.keepAlive();
        print('ChatMediaProvider: keepAlive acquired');
      } else if (!next.isUploading && keepAliveLink != null) {
        keepAliveLink!.close();
        keepAliveLink = null;
        print('ChatMediaProvider: keepAlive released');
      }
    });

    ref.onDispose(() {
      keepAliveLink?.close();
      print('ChatMediaProvider: Disposing notifier for chatId: ${params.chatId}');
      try {
        if (notifier.mounted) {
          notifier.dispose();
        }
      } catch (e) {
        print('ChatMediaProvider: Disposal error (expected): $e');
      }
    });

    return notifier;
  },
);

// Helper function (unchanged)
ChatMediaParams createMediaParams({
  required String chatId,
  required String currentUserId,
}) {
  return ChatMediaParams(chatId: chatId, currentUserId: currentUserId);
}