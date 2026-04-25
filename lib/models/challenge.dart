class Challenge {
  final String challengeId;
  final String eventId;
  final String title;
  final String type; // e.g., 'quiz', 'coding', 'file_upload'
  final String instructions;
  final DateTime startTime;
  final DateTime endTime;
  final int maxScore;
  final bool autoEvaluate;

  Challenge({
    required this.challengeId,
    required this.eventId,
    required this.title,
    required this.type,
    required this.instructions,
    required this.startTime,
    required this.endTime,
    this.maxScore = 100,
    this.autoEvaluate = false,
  });

  factory Challenge.fromMap(Map<String, dynamic> map) {
    return Challenge(
      challengeId: map['challenge_id'],
      eventId: map['event_id'],
      title: map['title'] ?? '',
      type: map['type'] ?? 'quiz',
      instructions: map['instructions'] ?? '',
      startTime: DateTime.parse(map['start_time']),
      endTime: DateTime.parse(map['end_time']),
      maxScore: map['max_score'] ?? 100,
      autoEvaluate: map['auto_evaluate'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'challenge_id': challengeId,
      'event_id': eventId,
      'title': title,
      'type': type,
      'instructions': instructions,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'max_score': maxScore,
      'auto_evaluate': autoEvaluate,
    };
  }

  String get readableWindow {
    return "${startTime.hour}:${startTime.minute} - ${endTime.hour}:${endTime.minute}";
  }
}