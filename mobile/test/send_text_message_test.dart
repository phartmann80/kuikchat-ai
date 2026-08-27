import 'package:flutter_test/flutter_test.dart';
import 'package:kuikchat_mobile/core/result.dart';
import 'package:kuikchat_mobile/domain/personal/usecases/send_text_message.dart';

import 'fakes/fake_personal_repositories.dart';

void main() {
  late FakePersonalMessageRepository messages;
  late SendTextMessage sendText;

  setUp(() {
    messages = FakePersonalMessageRepository();
    sendText = SendTextMessage(messages);
  });

  test('rejects empty and whitespace-only messages without calling the backend', () async {
    final result = await sendText(conversationId: 'c1', body: '   ', clientId: 'id-1');
    expect(result.isSuccess, isFalse);
    expect(messages.sendCalls, 0);
  });

  test('rejects messages above the 4000 character input limit', () async {
    final result = await sendText(
      conversationId: 'c1',
      body: 'x' * 4001,
      clientId: 'id-1',
    );
    expect(result.isSuccess, isFalse);
    expect(messages.sendCalls, 0);
  });

  test('trims message body before sending', () async {
    final result = await sendText(conversationId: 'c1', body: '  hi  ', clientId: 'id-1');
    result.fold(
      (message) => expect(message.body, 'hi'),
      (failure) => fail('expected success, got $failure'),
    );
  });

  test('maps repository failures to typed Result failures', () async {
    messages.nextSendFailure = const AppFailure(AppFailureKind.unauthorized);
    final result = await sendText(conversationId: 'c1', body: 'hello', clientId: 'id-1');
    result.fold(
      (_) => fail('expected failure'),
      (failure) => expect(failure.kind, AppFailureKind.unauthorized),
    );
  });

  test('sending the same clientId twice returns the same server row', () async {
    final first = await sendText(conversationId: 'c1', body: 'hello', clientId: 'same-id');
    final second = await sendText(conversationId: 'c1', body: 'hello', clientId: 'same-id');
    final firstId = first.fold((m) => m.id, (_) => 'a');
    final secondId = second.fold((m) => m.id, (_) => 'b');
    expect(firstId, secondId);
    expect(messages.store, hasLength(1));
  });
}
