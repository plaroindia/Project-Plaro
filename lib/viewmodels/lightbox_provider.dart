import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/post.dart';
import '../models/byte.dart';

enum LightboxType { post, byte }

class LightboxItem {
  final LightboxType type;
  final Object data;

  const LightboxItem({required this.type, required this.data});
}

class LightboxState {
  final List<LightboxItem> items;
  final int initialIndex;
  final bool isOpen;

  const LightboxState({
    this.items = const [],
    this.initialIndex = 0,
    this.isOpen = false,
  });

  LightboxState copyWith({
    List<LightboxItem>? items,
    int? initialIndex,
    bool? isOpen,
  }) => LightboxState(
    items: items ?? this.items,
    initialIndex: initialIndex ?? this.initialIndex,
    isOpen: isOpen ?? this.isOpen,
  );
}

class LightboxNotifier extends StateNotifier<LightboxState> {
  LightboxNotifier() : super(const LightboxState());

  void openPosts(List<Post_feed> posts, int index) {
    state = LightboxState(
      items: posts.map((p) => LightboxItem(type: LightboxType.post, data: p)).toList(),
      initialIndex: index,
      isOpen: true,
    );
  }


  void openBytes(List<Byte> bytes, int index) {
    state = LightboxState(
      items: bytes.map((b) => LightboxItem(type: LightboxType.byte, data: b)).toList(),
      initialIndex: index,
      isOpen: true,
    );
  }

  void close() {
    state = const LightboxState();
  }
}

final lightboxProvider = StateNotifierProvider<LightboxNotifier, LightboxState>((ref) {
  return LightboxNotifier();
});


