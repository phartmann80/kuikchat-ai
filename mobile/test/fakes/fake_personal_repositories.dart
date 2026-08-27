import 'dart:async';

import 'package:kuikchat_mobile/core/result.dart';
import 'package:kuikchat_mobile/domain/personal/entities/conversation.dart';
import 'package:kuikchat_mobile/domain/personal/entities/message.dart';
import 'package:kuikchat_mobile/domain/personal/entities/user_profile.dart';
import 'package:kuikchat_mobile/domain/personal/repositories/personal_auth_repository.dart';
import 'package:kuikchat_mobile/domain/personal/repositories/personal_messaging_repositories.dart';

/// Controlled fakes used by unit and widget tests. They implement the same
/// repository interfaces as the Supabase-backed Personal services, proving
/// the provider boundary is swappable.
class FakePersonalAuthRepository implements PersonalAuthRepository {
  FakePersonalAuthRepository({this.userId = 'user-self'});

  final String userId;
  bool signedIn = true;
  final _controller = StreamController<bool>.broadcast();

  @override
  Stream<bool> watchSignedIn() => _controller.stream;

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get currentUserId => signedIn ? userId : null;

  @override
  Future<void> signInWithPassword({required String email, required String password}) async {
    signedIn = true;
    _controller.add(true);
  }

  @override
  Future<void> signUpWithPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    signedIn = true;
    _controller.add(true);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    _controller.add(false);
  }
}

class FakePersonalProfileRepository implements PersonalProfileRepository {
  final Map<String, UserProfile> profilesByEmail = {};

  @override
  Future<UserProfile> loadOwnProfile() async =>
      const UserProfile(userId: 'user-self', displayName: 'Test User');

  @override
  Future<UserProfile?> findByEmail(String email) async =>
      profilesByEmail[email.trim().toLowerCase()];
}

class FakePersonalConversationRepository implements PersonalConversationRepository {
  final List<Conversation> conversations = [];
  AppFailure? failure;

  @override
  Future<List<Conversation>> loadConversations() async {
    final pending = failure;
    if (pending != null) throw pending;
    return List.of(conversations);
  }

  @override
  Future<Conversation> openDirectConversation(String otherUserId) async {
    final pending = failure;
    if (pending != null) throw pending;
    final existing = conversations.where((c) => c.memberIds.contains(otherUserId));
    if (existing.isNotEmpty) return existing.first;
    final created = Conversation(
      id: 'conv-$otherUserId',
      title: otherUserId,
      isDirect: true,
      memberIds: ['user-self', otherUserId],
    );
    conversations.add(created);
    return created;
  }
}

class FakePersonalMessageRepository implements PersonalMessageRepository {
  final List<Message> store = [];
  final StreamController<Message> realtime = StreamController<Message>.broadcast();
  final StreamController<Map<String, String>> readStates =
      StreamController<Map<String, String>>.broadcast();

  /// When set, the next [sendText] throws this failure once.
  AppFailure? nextSendFailure;

  /// When set, [loadMessages] always throws.
  AppFailure? loadFailure;

  int sendCalls = 0;
  final List<String> markedRead = [];

  @override
  Future<List<Message>> loadMessages(String conversationId,
      {DateTime? before, int limit = 50}) async {
    final pending = loadFailure;
    if (pending != null) throw pending;
    return store.where((m) => m.conversationId == conversationId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<Message> sendText({
    required String conversationId,
    required String body,
    required String clientId,
  }) async {
    sendCalls += 1;
    final pending = nextSendFailure;
    if (pending != null) {
      nextSendFailure = null;
      throw pending;
    }
    // Idempotency: same clientId returns the existing row.
    final existing = store.where((m) => m.clientId == clientId);
    if (existing.isNotEmpty) return existing.first;
    final message = Message(
      id: 'server-$clientId',
      clientId: clientId,
      conversationId: conversationId,
      senderId: 'user-self',
      body: body,
      createdAt: DateTime.now(),
      deliveryState: MessageDeliveryState.sent,
    );
    store.add(message);
    return message;
  }

  @override
  Stream<Message> watchMessages(String conversationId) => realtime.stream;

  @override
  Future<void> markRead({required String conversationId, required String lastMessageId}) async {
    markedRead.add(lastMessageId);
  }

  @override
  Future<Map<String, String>> loadReadStates(String conversationId) async => {};

  @override
  Stream<Map<String, String>> watchReadStates(String conversationId) => readStates.stream;

  @override
  Future<void> deleteMessage(String messageId) async {
    final index = store.indexWhere((m) => m.id == messageId);
    if (index >= 0) {
      store[index] = store[index].copyWith(deletedAt: DateTime.now());
    }
  }
}
