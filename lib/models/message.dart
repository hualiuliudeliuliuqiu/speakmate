import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant }

class Message {
  final String id;
  final MessageRole role;
  String text;
  final DateTime timestamp;
  bool isStreaming;
  bool isVoice;

  Message({
    String? id,
    required this.role,
    required this.text,
    DateTime? timestamp,
    this.isStreaming = false,
    this.isVoice = false,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  Message copyWith({
    String? text,
    bool? isStreaming,
  }) {
    return Message(
      id: id,
      role: role,
      text: text ?? this.text,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role == MessageRole.user ? 'user' : 'assistant',
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        if (isVoice) 'isVoice': true,
      };

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
        text: json['text'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        isVoice: json['isVoice'] as bool? ?? false,
      );
}
