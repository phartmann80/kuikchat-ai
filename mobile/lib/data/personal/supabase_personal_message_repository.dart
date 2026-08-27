import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/personal/entities/message.dart';
import '../../domain/personal/repositories/personal_messaging_repositories.dart';
import 'supabase_personal_client.dart';

class SupabasePersonalMessageRepository implements PersonalMessageRepository {
  SupabasePersonalMessageRepository(this._client);

  final SupabasePersonalClient _client;

  static const _messageColumns =
      'id, client_id, conversation_id, sender_id, body, created_at, deleted_at';

  @override
  Future<List<Message>> loadMessages(
    String conversationId, {
    DateTime? before,
    int limit = 50,
  }) async {
    try {
      var query = _client.raw
          .from('messages')
          .select(_messageColumns)
          .eq('conversation_id', conversationId);
      if (before != null) {
        query = query.lt('created_at', before.toUtc().toIso8601String());
      }
      final rows = await query.order('created_at', ascending: false).limit(limit);
      final messages = rows
          .map((row) => _fromRow(row))
          .toList(growable: false)
          .reversed
          .toList(growable: false);
      return messages;
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Future<Message> sendText({
    required String conversationId,
    required String body,
    required String clientId,
  }) async {
    try {
      // Idempotent insert: unique (conversation_id, sender_id, client_id).
      // A retry after a network timeout returns the existing row instead of
      // duplicating the message.
      final inserted = await _client.raw
          .from('messages')
          .upsert(
            {
              'conversation_id': conversationId,
              'sender_id': _client.raw.auth.currentUser!.id,
              'client_id': clientId,
              'body': body,
            },
            onConflict: 'conversation_id,sender_id,client_id',
            ignoreDuplicates: true,
          )
          .select(_messageColumns)
          .maybeSingle();
      if (inserted != null) return _fromRow(inserted);

      final existing = await _client.raw
          .from('messages')
          .select(_messageColumns)
          .eq('conversation_id', conversationId)
          .eq('client_id', clientId)
          .single();
      return _fromRow(existing);
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Stream<Message> watchMessages(String conversationId) {
    final controller = StreamController<Message>.broadcast();
    final channel = _client.raw
        .channel('personal:messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            controller.add(_fromRow(payload.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            controller.add(_fromRow(payload.newRecord));
          },
        )
        .subscribe();

    controller.onCancel = () async {
      await _client.raw.removeChannel(channel);
    };
    return controller.stream;
  }

  @override
  Future<void> markRead({
    required String conversationId,
    required String lastMessageId,
  }) async {
    try {
      await _client.raw.from('message_read_states').upsert(
        {
          'conversation_id': conversationId,
          'user_id': _client.raw.auth.currentUser!.id,
          'last_read_message_id': lastMessageId,
          'last_read_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'conversation_id,user_id',
      );
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Future<Map<String, String>> loadReadStates(String conversationId) async {
    try {
      final rows = await _client.raw
          .from('message_read_states')
          .select('user_id, last_read_message_id')
          .eq('conversation_id', conversationId);
      return {
        for (final row in rows)
          row['user_id'] as String: row['last_read_message_id'] as String,
      };
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  @override
  Stream<Map<String, String>> watchReadStates(String conversationId) {
    final controller = StreamController<Map<String, String>>.broadcast();
    final channel = _client.raw
        .channel('personal:read_states:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_read_states',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (_) async {
            try {
              controller.add(await loadReadStates(conversationId));
            } catch (_) {
              // Transient realtime refresh failure; the next event retries.
            }
          },
        )
        .subscribe();

    controller.onCancel = () async {
      await _client.raw.removeChannel(channel);
    };
    return controller.stream;
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    try {
      await _client.raw
          .from('messages')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', messageId)
          .eq('sender_id', _client.raw.auth.currentUser!.id);
    } catch (error) {
      throw SupabasePersonalClient.mapError(error);
    }
  }

  Message _fromRow(Map<String, dynamic> row) {
    return Message(
      id: row['id'] as String,
      clientId: row['client_id'] as String?,
      conversationId: row['conversation_id'] as String,
      senderId: row['sender_id'] as String,
      body: (row['body'] as String?) ?? '',
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      deliveryState: MessageDeliveryState.sent,
      deletedAt: row['deleted_at'] == null
          ? null
          : DateTime.parse(row['deleted_at'] as String).toLocal(),
    );
  }
}
