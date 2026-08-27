import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuikchat_mobile/core/result.dart';
import 'package:kuikchat_mobile/domain/personal/entities/message.dart';
import 'package:kuikchat_mobile/state/chat_controller.dart';
import 'package:kuikchat_mobile/state/providers.dart';

import 'fakes/fake_personal_repositories.dart';

void main() {
  late FakePersonalAuthRepository auth;
  late FakePersonalMessageRepository messages;
  late ProviderContainer container;

  const conversationId = 'conv-1';

  setUp(() {
    auth = FakePersonalAuthRepository();
    messages = FakePersonalMessageRepository();
    container = ProviderContainer(overrides: [
      personalAuthRepositoryProvider.overrideWithValue(auth),
      personalMessageRepositoryProvider.overrideWithValue(messages),
    ]);
    addTearDown(container.dispose);
  });

  Future<ChatState> readState() async {
    // Let pending microtasks (state updates) settle.
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return container.read(chatControllerProvider(conversationId)).value!;
  }

  test('loads empty history into ready/empty state', () async {
    final state = await container.read(chatControllerProvider(conversationId).future);
    expect(state.phase, ChatPhase.ready);
    expect(state.messages, isEmpty);
    expect(state.isEmpty, isTrue);
  });

  test('history load failure produces error state with typed failure', () async {
    messages.loadFailure = const AppFailure(AppFailureKind.network);
    final state = await container.read(chatControllerProvider(conversationId).future);
    expect(state.phase, ChatPhase.error);
    expect(state.failure?.kind, AppFailureKind.network);
  });

  test('sendText goes sending -> sent and keeps idempotent clientId', () async {
    await container.read(chatControllerProvider(conversationId).future);
    final controller = container.read(chatControllerProvider(conversationId).notifier);

    await controller.sendText('hello world');
    final state = await readState();

    expect(state.messages, hasLength(1));
    final message = state.messages.single;
    expect(message.deliveryState, MessageDeliveryState.sent);
    expect(message.body, 'hello world');
    expect(message.clientId, isNotNull);
    expect(message.id, startsWith('server-'));
    expect(messages.sendCalls, 1);
  });

  test('failed send is marked failed and retry with same clientId succeeds', () async {
    await container.read(chatControllerProvider(conversationId).future);
    final controller = container.read(chatControllerProvider(conversationId).notifier);

    messages.nextSendFailure = const AppFailure(AppFailureKind.network);
    await controller.sendText('offline message');

    var state = await readState();
    expect(state.messages.single.deliveryState, MessageDeliveryState.failed);
    expect(state.failure?.kind, AppFailureKind.network);
    final clientId = state.messages.single.clientId!;

    await controller.retry(clientId);
    state = await readState();

    expect(state.messages.single.deliveryState, MessageDeliveryState.sent);
    expect(state.messages.single.clientId, clientId);
    expect(messages.sendCalls, 2);
  });

  test('retry ignores messages that are not in failed state', () async {
    await container.read(chatControllerProvider(conversationId).future);
    final controller = container.read(chatControllerProvider(conversationId).notifier);

    await controller.sendText('fine message');
    var state = await readState();
    final clientId = state.messages.single.clientId!;

    await controller.retry(clientId);
    state = await readState();
    expect(messages.sendCalls, 1, reason: 'sent message must not be re-sent');
  });

  test('realtime incoming message is appended and marked read', () async {
    await container.read(chatControllerProvider(conversationId).future);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    messages.realtime.add(Message(
      id: 'incoming-1',
      conversationId: conversationId,
      senderId: 'user-other',
      body: 'hi there',
      createdAt: DateTime.now(),
      deliveryState: MessageDeliveryState.sent,
    ));

    final state = await readState();
    expect(state.messages.map((m) => m.id), contains('incoming-1'));
    expect(messages.markedRead, contains('incoming-1'));
  });

  test('realtime echo of own optimistic message does not duplicate it', () async {
    await container.read(chatControllerProvider(conversationId).future);
    final controller = container.read(chatControllerProvider(conversationId).notifier);

    await controller.sendText('no duplicates');
    var state = await readState();
    final sent = state.messages.single;

    // Realtime INSERT arrives for the same server row.
    messages.realtime.add(sent.copyWith());
    state = await readState();

    expect(state.messages, hasLength(1));
  });
}
