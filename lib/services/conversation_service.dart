import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/message.dart';

/// Persists conversations locally using SharedPreferences (JSON)
/// For MVP this is simpler than SQLite; can migrate later if needed
class ConversationService {
  static const String _storageKey = 'conversations';
  List<Conversation> _conversations = [];

  List<Conversation> get conversations => List.unmodifiable(_conversations);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _conversations = list
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .toList();
        // Sort by updatedAt descending
        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      } catch (_) {
        _conversations = [];
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode(_conversations.map((c) => c.toJson()).toList());
    await prefs.setString(_storageKey, json);
  }

  /// Get or create a conversation for a scenario
  Conversation getOrCreate({
    required String scenarioId,
    required String scenarioTitle,
  }) {
    // Find the most recent conversation for this scenario
    final existing = _conversations.where((c) => c.scenarioId == scenarioId);
    if (existing.isNotEmpty) {
      return existing.first;
    }

    // Create new
    final conv = Conversation(
      scenarioId: scenarioId,
      scenarioTitle: scenarioTitle,
    );
    _conversations.insert(0, conv);
    return conv;
  }

  /// Start a fresh conversation for a scenario (keep old ones in history)
  Conversation startNew({
    required String scenarioId,
    required String scenarioTitle,
  }) {
    final conv = Conversation(
      scenarioId: scenarioId,
      scenarioTitle: scenarioTitle,
    );
    _conversations.insert(0, conv);
    _save();
    return conv;
  }

  /// Add a message to a conversation and persist
  Future<void> addMessage(String conversationId, Message message) async {
    final conv = _conversations.where((c) => c.id == conversationId).firstOrNull;
    if (conv != null) {
      conv.messages.add(message);
      conv.updatedAt = DateTime.now();
      await _save();
    }
  }

  /// Update the last message text (for streaming updates)
  Future<void> updateLastMessage(String conversationId, String text) async {
    final conv = _conversations.where((c) => c.id == conversationId).firstOrNull;
    if (conv != null && conv.messages.isNotEmpty) {
      conv.messages.last.text = text;
      conv.updatedAt = DateTime.now();
      await _save();
    }
  }

  /// Get conversation by ID
  Conversation? getById(String id) =>
      _conversations.where((c) => c.id == id).firstOrNull;

  /// Delete a conversation
  Future<void> delete(String id) async {
    _conversations.removeWhere((c) => c.id == id);
    await _save();
  }

  /// Get all conversations for a scenario
  List<Conversation> getByScenario(String scenarioId) =>
      _conversations.where((c) => c.scenarioId == scenarioId).toList();
}
