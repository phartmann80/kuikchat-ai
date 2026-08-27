import '../entities/conversation.dart';
import '../entities/message.dart';

abstract interface class PersonalConversationRepository {
  /// Loads all conversations the current user is a member of, newest first.
  Future<List<Conversation>> loadConversations();

  /// Returns the existing direct conversation with [otherUserId] or creates
  /// one. Authorization (membership) is enforced server-side; this call must
  /// fail with unauthorized if the server rejects it.
  Future<Conversation> openDirectConversation(String otherUserId);
}

abstract interface class PersonalMessageRepository {
  /// Loads message history, oldest first. [before] enables pagination.
  Future<List<Message>> loadMessages(String conversationId, {DateTime? before, int limit});

  /// Sends a text message. [clientId] is the idempotency key; sending the
  /// same clientId twice must not create two rows.
  Future<Message> sendText({
    required String conversationId,
    required String body,
    required String clientId,
  });

  /// Realtime stream of newly inserted/updated messages in a conversation.
  Stream<Message> watchMessages(String conversationId);

  /// Marks everything up to [lastMessageId] as read by the current user.
  Future<void> markRead({required String conversationId, required String lastMessageId});

  /// userId -> id of the last message that user has read in the conversation.
  Future<Map<String, String>> loadReadStates(String conversationId);

  /// Realtime stream of read-state changes (same shape as [loadReadStates]).
  Stream<Map<String, String>> watchReadStates(String conversationId);

  /// Soft-deletes an own message.
  Future<void> deleteMessage(String messageId);
}
