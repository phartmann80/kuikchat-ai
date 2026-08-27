import '../../domain/personal/entities/conversation.dart';
import '../../domain/personal/repositories/personal_messaging_repositories.dart';
import 'supabase_personal_client.dart';

class SupabasePersonalConversationRepository implements PersonalConversationRepository {
  SupabasePersonalConversationRepository(this._client);

  final SupabasePersonalClient _client;

  @override
  Future<List<Conversation>> loadConversations() async {
    try {
      // RPC returns only conversations the caller is a member of (enforced by
      // RLS + the function itself). See personal migration 0001.
      final rows = await _client.raw.rpc<List<dynamic>>('list_conversations');
      return rows
          .map((row) => _fromRow(row as Map<String, dynamic>))
          .toList(growable: false);
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Future<Conversation> openDirectConversation(String otherUserId) async {
    try {
      // Server-side function creates-or-returns the direct conversation and
      // enforces block lists and membership atomically.
      final row = await _client.raw.rpc<Map<String, dynamic>>(
        'open_direct_conversation',
        params: {'other_user': otherUserId},
      );
      return _fromRow(row);
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  Conversation _fromRow(Map<String, dynamic> row) {
    return Conversation(
      id: row['id'] as String,
      title: (row['title'] as String?) ?? 'Conversation',
      isDirect: (row['is_direct'] as bool?) ?? true,
      memberIds: ((row['member_ids'] as List<dynamic>?) ?? const [])
          .map((id) => id as String)
          .toList(growable: false),
      lastMessagePreview: row['last_message_preview'] as String?,
      lastMessageAt: row['last_message_at'] == null
          ? null
          : DateTime.parse(row['last_message_at'] as String).toLocal(),
      unreadCount: (row['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}
