import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────

enum ModerationVerdict { allow, warning, block }

class ImageModerationResult {
  final double drawings;
  final double hentai;
  final double neutral;
  final double porn;
  final double sexy;
  final double nsfwScore;
  final ModerationVerdict verdict;
  final String? reason;

  const ImageModerationResult({
    required this.drawings,
    required this.hentai,
    required this.neutral,
    required this.porn,
    required this.sexy,
    required this.nsfwScore,
    required this.verdict,
    this.reason,
  });

  bool get isBlocked => verdict == ModerationVerdict.block;
}

class TextModerationResult {
  final double nsfwScore;
  final ModerationVerdict verdict;
  final String? reason;
  final bool fromWordlist;

  const TextModerationResult({
    required this.nsfwScore,
    required this.verdict,
    this.reason,
    this.fromWordlist = false,
  });

  bool get isBlocked => verdict == ModerationVerdict.block;
}

// ─────────────────────────────────────────────────────────────────────────────
// ModerationService
// ─────────────────────────────────────────────────────────────────────────────

class ModerationService {
  static const _imageModelPath = 'assets/models/nsfw/nsfw_model_optimized.tflite';
  static const _textModelPath  = 'assets/models/text/text_nsfw.tflite';
  static const _tokenizerPath  = 'assets/models/text/tokenizer.json';
  static const _wordlistPath   = 'assets/models/text/nsfw_wordlist.json';

  // ── Image thresholds ──────────────────────────────────────────────────────
  // Lowered from 0.70 → 0.50 so WARNING-range images are also blocked.
  // combined score = porn + hentai + (sexy * 0.5)
  static const double _imageBlockThreshold = 0.50;
  static const double _imageWarnThreshold  = 0.30;

  // ── Text thresholds ───────────────────────────────────────────────────────
  static const double _textBlockThreshold  = 0.60;
  static const double _textWarnThreshold   = 0.35;

  static const int _imageSize     = 224;
  static const int _maxTextLen    = 100;
  static const int _oovIndex      = 1;
  // FIX for "gather index out of bounds":
  // The TFLite Embedding layer was trained with num_words=10000 → rows 0..9999.
  // The tokenizer JSON has 72,200 entries. Any index ≥ 10000 crashes GATHER.
  // Clamp every token index to 9999 before passing to the model.
  static const int _maxTokenIndex = 9999;

  Interpreter? _imageInterpreter;
  Interpreter? _textInterpreter;
  Map<String, int>? _wordIndex;
  Set<String>?      _nsfwWordlist;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await Future.wait([
      _loadImageModel(),
      _loadTextModel(),
      _loadTokenizer(),
      _loadWordlist(),
    ]);
  }

  Future<void> _loadImageModel() async {
    _imageInterpreter = await Interpreter.fromAsset(_imageModelPath);
  }

  Future<void> _loadTextModel() async {
    _textInterpreter = await Interpreter.fromAsset(_textModelPath);
  }

  Future<void> _loadTokenizer() async {
    final raw    = await rootBundle.loadString(_tokenizerPath);
    final outer  = jsonDecode(raw) as Map<String, dynamic>;
    final config = outer['config'] as Map<String, dynamic>;
    final wiJson = config['word_index'] as String;
    final rawMap = jsonDecode(wiJson) as Map<String, dynamic>;
    _wordIndex   = rawMap.map((k, v) => MapEntry(k, v as int));
  }

  Future<void> _loadWordlist() async {
    final raw  = await rootBundle.loadString(_wordlistPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final list = (json['words'] as List).cast<String>();
    _nsfwWordlist = list.toSet();
  }

  void dispose() {
    _imageInterpreter?.close();
    _textInterpreter?.close();
  }

  // ── Image moderation ──────────────────────────────────────────────────────

  Future<ImageModerationResult> moderateImage(String imagePath) async {
    if (_imageInterpreter == null) await _loadImageModel();

    final bytes   = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return _imageAllow();

    final resized = img.copyResize(decoded, width: _imageSize, height: _imageSize);

    final input = List.generate(
      1,
          (_) => List.generate(
        _imageSize,
            (y) => List.generate(
          _imageSize,
              (x) {
            final pixel = resized.getPixel(x, y);
            return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
          },
        ),
      ),
    );

    final output = List.generate(1, (_) => List.filled(5, 0.0));
    _imageInterpreter!.run(input, output);

    final scores   = output[0];
    final drawings = scores[0];
    final hentai   = scores[1];
    final neutral  = scores[2];
    final porn     = scores[3];
    final sexy     = scores[4];

    final nsfwScore = porn + hentai + (sexy * 0.5);

    final verdict = nsfwScore >= _imageBlockThreshold
        ? ModerationVerdict.block
        : nsfwScore >= _imageWarnThreshold
        ? ModerationVerdict.warning
        : ModerationVerdict.allow;

    String? reason;
    if (verdict == ModerationVerdict.block) {
      if (porn > 0.4)        reason = 'Image contains explicit content';
      else if (hentai > 0.4) reason = 'Image contains explicit illustrated content';
      else                   reason = 'Image contains inappropriate content';
    }

    return ImageModerationResult(
      drawings: drawings, hentai: hentai, neutral: neutral,
      porn: porn, sexy: sexy,
      nsfwScore: nsfwScore, verdict: verdict, reason: reason,
    );
  }

  // ── Text moderation — public API ──────────────────────────────────────────
  //
  // Checks title + content (caption) + tags.
  // Layer 1: instant wordlist check
  // Layer 2: ML model on combined title+content

  Future<TextModerationResult> moderatePost({
    required String title,
    required String content,
    required List<String> tags,
  }) async {
    if (_nsfwWordlist == null) await _loadWordlist();

    // Layer 1: wordlist on each field
    for (final text in [title, content, ...tags]) {
      if (text.isEmpty) continue;
      final r = _checkWordlist(text);
      if (r != null) return r;
    }

    // Layer 2: ML model on title + content combined
    final combined = '$title $content'.trim();
    if (combined.isEmpty) {
      return const TextModerationResult(nsfwScore: 0, verdict: ModerationVerdict.allow);
    }
    return _runTextModel(combined);
  }

  // ── Wordlist check ────────────────────────────────────────────────────────

  TextModerationResult? _checkWordlist(String text) {
    final lower = text.toLowerCase();

    // Multi-word phrases first
    for (final phrase in _nsfwWordlist!) {
      if (phrase.contains(' ') && lower.contains(phrase)) {
        return const TextModerationResult(
          nsfwScore: 1.0,
          verdict:   ModerationVerdict.block,
          reason:    'Post contains inappropriate language',
          fromWordlist: true,
        );
      }
    }

    // Individual words — word boundary safe split
    final words = lower
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toSet();

    for (final word in words) {
      if (_nsfwWordlist!.contains(word)) {
        return const TextModerationResult(
          nsfwScore: 1.0,
          verdict:   ModerationVerdict.block,
          reason:    'Post contains inappropriate language',
          fromWordlist: true,
        );
      }
    }

    return null;
  }

  // ── ML text model ─────────────────────────────────────────────────────────

  Future<TextModerationResult> _runTextModel(String text) async {
    if (_textInterpreter == null) await _loadTextModel();
    if (_wordIndex == null)       await _loadTokenizer();

    final cleaned = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

    // Tokenise + CLAMP indices to prevent GATHER crash
    final tokens = cleaned
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => (_wordIndex![w] ?? _oovIndex).clamp(0, _maxTokenIndex))
        .toList();

    // Pre-pad to maxlen=100
    final padded  = List<double>.filled(_maxTextLen, 0.0);
    final tooLong = tokens.length > _maxTextLen;
    final start   = tooLong ? 0 : _maxTextLen - tokens.length;
    final tStart  = tooLong ? tokens.length - _maxTextLen : 0;
    for (int i = 0; i < tokens.length && i < _maxTextLen; i++) {
      padded[start + i] = tokens[tStart + i].toDouble();
    }

    final input  = [padded];
    final output = [[0.0]];
    _textInterpreter!.run(input, output);

    final nsfwScore = (output[0][0] as num).toDouble();

    final verdict = nsfwScore >= _textBlockThreshold
        ? ModerationVerdict.block
        : nsfwScore >= _textWarnThreshold
        ? ModerationVerdict.warning
        : ModerationVerdict.allow;

    return TextModerationResult(
      nsfwScore: nsfwScore,
      verdict:   verdict,
      reason:    verdict == ModerationVerdict.block
          ? 'Post contains inappropriate content'
          : null,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  ImageModerationResult _imageAllow() => const ImageModerationResult(
    drawings: 0, hentai: 0, neutral: 1, porn: 0, sexy: 0,
    nsfwScore: 0, verdict: ModerationVerdict.allow,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final moderationServiceProvider = Provider<ModerationService>((ref) {
  final service = ModerationService();
  ref.onDispose(service.dispose);
  return service;
});