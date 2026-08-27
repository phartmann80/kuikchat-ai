import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/result.dart';
import '../domain/personal/entities/message.dart';
import 'providers.dart';

/// Full view state for one open conversation.
class ChatState {
  const ChatState({
    this.phase = ChatPhase.loading,
    this.messages = const <Message>[],
    this.readStates = const <String, String>{},
    this.failure,
  });

  final ChatPhase phase;

  /// Ordered oldest -> newest. Includes optimistic (sending/failed) entries.
  final List<Message> messages;

  /// userId -> last read message id.
  final Map<String, String> readStates;
  final AppFailure? failure;

  bool get isEmpty => phase == ChatPhase.ready && messages.isEmpty;

  ChatState copyWith({
    ChatPhase? phase,
    List<Message>? messages,
    Map<String, String>? readStates,
    AppFailure? failure,
    bool clearFailure = false,
  }) {
    return ChatState(
      phase: phase ?? this.phase,
      messages: messages ?? this.messages,
      readStates: readStates ?? this.readStates,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

enum ChatPhase { loading, ready, error }

/// State machine for a single conversation:
/// history load, realtime inserts, optimistic send, failed-send retry,
/// read-state updates, message deletion.
class ChatController extends FamilyAsyncNotifier<ChatState, String> {
  StreamSubscription<Message>? _messageSub;
  StreamSubscription<Map<String, String>>? _readSub;
  final _random = Random();

  String get conversationId => arg;

  @override
  Future<ChatState> build(String arg) async {
    ref.onDispose(() {
      unawaited(_messageSub?.cancel());
      unawaited(_readSub?.cancel());
    });

    final loadHistory = ref.watch(loadMessageHistoryProvider);
    // Watching keeps the subscription wiring in sync with provider overrides.
    ref.watch(personalMessageRepositoryProvider);

    final result = await loadHistory(arg);
    return result.fold(
      (messages) {
        _subscribe();
        unawaited(_loadReadStates());
        unawaited(_markLatestRead(messages));
        return ChatState(phase: ChatPhase.ready, messages: messages);
      },
      (failure) => ChatState(phase: ChatPhase.error, failure: failure),
    );
  }

  void _subscribe() {
    unawaited(_messageSub?.cancel());
    unawaited(_readSub?.cancel());
    final messages = ref.read(personalMessageRepositoryProvider);
    _messageSub = messages.watchMessages(conversationId).listen(_onRealtimeMessage);
    _readSub = messages.watchReadStates(conversationId).listen((states) {
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncData(current.copyWith(readStates: states));
    });
  }

  Future<void> _loadReadStates() async {
    try {
      final repo = ref.read(personalMessageRepositoryProvider);
      final states = await repo.loadReadStates(conversationId);
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncData(current.copyWith(readStates: states));
    } on AppFailure {
      // Read receipts are non-critical; history remains usable without them.
    }
  }

  void _onRealtimeMessage(Message incoming) {
    final current = state.valueOrNull;
    if (current == null) return;

    final list = List<Message>.of(current.messages);
    // Reconcile: replaces the optimistic copy (matched by clientId) or an
    // older version of the same server row (matched by id).
    final existingIndex = list.indexWhere(
      (m) => m.id == incoming.id || (incoming.clientId != null && m.clientId == incoming.clientId),
    );
    if (existingIndex >= 0) {
      list[existingIndex] = incoming;
    } else {
      list.add(incoming);
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }
    state = AsyncData(current.copyWith(messages: list));
    unawaited(_markLatestRead(list));
  }

  /// Optimistic send. The message appears immediately as `sending`, then
  /// transitions to `sent` on server ack or `failed` on error.
  Future<void> sendText(String body) async {
    final current = state.valueOrNull;
    if (current == null || current.phase != ChatPhase.ready) return;
    final auth = ref.read(personalAuthRepositoryProvider);
    final selfId = auth.currentUserId;
    if (selfId == null) return;

    final clientId = _newClientId();
    final optimistic = Message(
      id: clientId,
      clientId: clientId,
      conversationId: conversationId,
      senderId: selfId,
      body: body.trim(),
      createdAt: DateTime.now(),
      deliveryState: MessageDeliveryState.sending,
    );
    state = AsyncData(current.copyWith(messages: [...current.messages, optimistic], clearFailure: true));

    await _dispatch(optimistic);
  }

  /// Retries a failed optimistic message with the SAME clientId so the server
  /// side stays idempotent.
  Future<void> retry(String clientId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final index = current.messages.indexWhere((m) => m.clientId == clientId);
    if (index < 0) return;
    final message = current.messages[index];
    if (message.deliveryState != MessageDeliveryState.failed) return;

    _updateMessage(clientId, (m) => m.copyWith(deliveryState: MessageDeliveryState.retrying));
    await _dispatch(message);
  }

  Future<void> _dispatch(Message optimistic) async {
    final send = ref.read(sendTextMessageProvider);
    final result = await send(
      conversationId: conversationId,
      body: optimistic.body,
      clientId: optimistic.clientId!,
    );
    result.fold(
      (acked) => _updateMessage(
        optimistic.clientId!,
        (_) => acked.copyWith(deliveryState: MessageDeliveryState.sent),
      ),
      (failure) {
        _updateMessage(
          optimistic.clientId!,
          (m) => m.copyWith(deliveryState: MessageDeliveryState.failed),
        );
        final current = state.valueOrNull;
        if (current != null) {
          state = AsyncData(current.copyWith(failure: failure));
        }
      },
    );
  }

  Future<void> deleteMessage(String messageId) async {
    try {
      final repo = ref.read(personalMessageRepositoryProvider);
      await repo.deleteMessage(messageId);
      _updateById(messageId, (m) => m.copyWith(deletedAt: DateTime.now()));
    } on AppFailure catch (failure) {
      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncData(current.copyWith(failure: failure));
      }
    }
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> _markLatestRead(List<Message> messages) async {
    final auth = ref.read(personalAuthRepositoryProvider);
    final selfId = auth.currentUserId;
    if (selfId == null) return;
    Message? latestIncoming;
    for (final m in messages.reversed) {
      if (m.senderId != selfId && m.deliveryState == MessageDeliveryState.sent) {
        latestIncoming = m;
        break;
      }
    }
    if (latestIncoming == null) return;
    try {
      final repo = ref.read(personalMessageRepositoryProvider);
      await repo.markRead(conversationId: conversationId, lastMessageId: latestIncoming.id);
    } on AppFailure {
      // Non-critical; will retry on the next incoming message.
    }
  }

  void _updateMessage(String clientId, Message Function(Message) transform) {
    final current = state.valueOrNull;
    if (current == null) return;
    final list = current.messages
        .map((m) => m.clientId == clientId ? transform(m) : m)
        .toList(growable: false);
    state = AsyncData(current.copyWith(messages: list));
  }

  void _updateById(String id, Message Function(Message) transform) {
    final current = state.valueOrNull;
    if (current == null) return;
    final list =
        current.messages.map((m) => m.id == id ? transform(m) : m).toList(growable: false);
    state = AsyncData(current.copyWith(messages: list));
  }

  String _newClientId() {
    // RFC4122-style v4 id without an extra dependency.
    String hex(int length) =>
        List.generate(length, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${(_random.nextInt(4) + 8).toRadixString(16)}${hex(3)}-${hex(12)}';
  }
}

final chatControllerProvider =
    AsyncNotifierProvider.family<ChatController, ChatState, String>(ChatController.new);
