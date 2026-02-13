import 'package:uuid/uuid.dart';
import 'message.dart';

class Conversation {
  final String id;
  final String scenarioId;
  final String scenarioTitle;
  final DateTime createdAt;
  DateTime updatedAt;
  List<Message> messages;

  Conversation({
    String? id,
    required this.scenarioId,
    required this.scenarioTitle,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Message>? messages,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        messages = messages ?? [];

  /// Build a context summary of recent messages for injecting into system prompt
  /// This lets Gemini "remember" what was discussed before reconnecting
  String buildContextSummary({int maxMessages = 10}) {
    if (messages.isEmpty) return '';

    final recent = messages.length > maxMessages
        ? messages.sublist(messages.length - maxMessages)
        : messages;

    final buffer = StringBuffer();
    buffer.writeln('PREVIOUS CONVERSATION CONTEXT (help the user feel continuity):');
    for (final msg in recent) {
      final role = msg.role == MessageRole.user ? 'User' : 'SpeakMate';
      buffer.writeln('$role: ${msg.text}');
    }
    buffer.writeln('\nContinue the conversation naturally from where you left off.');
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'scenarioId': scenarioId,
        'scenarioTitle': scenarioTitle,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        scenarioId: json['scenarioId'] as String,
        scenarioTitle: json['scenarioTitle'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        messages: (json['messages'] as List)
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}
