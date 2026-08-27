import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuikchat_mobile/core/result.dart';
import 'package:kuikchat_mobile/domain/personal/entities/user_profile.dart';
import 'package:kuikchat_mobile/state/conversations_controller.dart';
import 'package:kuikchat_mobile/state/providers.dart';

import 'fakes/fake_personal_repositories.dart';

void main() {
  late FakePersonalAuthRepository auth;
  late FakePersonalProfileRepository profiles;
  late FakePersonalConversationRepository conversations;
  late ProviderContainer container;

  setUp(() {
    auth = FakePersonalAuthRepository();
    profiles = FakePersonalProfileRepository();
    conversations = FakePersonalConversationRepository();
    container = ProviderContainer(overrides: [
      personalAuthRepositoryProvider.overrideWithValue(auth),
      personalProfileRepositoryProvider.overrideWithValue(profiles),
      personalConversationRepositoryProvider.overrideWithValue(conversations),
    ]);
    addTearDown(container.dispose);
  });

  test('empty backend yields an empty list, never placeholder data', () async {
    final list = await container.read(conversationsControllerProvider.future);
    expect(list, isEmpty);
  });

  test('load failure surfaces as AsyncError with typed failure', () async {
    conversations.failure = const AppFailure(AppFailureKind.network);
    await expectLater(
      container.read(conversationsControllerProvider.future),
      throwsA(isA<AppFailure>()),
    );
  });

  test('openDirectByEmail returns notFound for unknown users', () async {
    await container.read(conversationsControllerProvider.future);
    final result = await container
        .read(conversationsControllerProvider.notifier)
        .openDirectByEmail('nobody@example.com');
    result.fold(
      (_) => fail('expected failure'),
      (failure) => expect(failure.kind, AppFailureKind.notFound),
    );
  });

  test('openDirectByEmail rejects starting a chat with yourself', () async {
    profiles.profilesByEmail['me@example.com'] =
        const UserProfile(userId: 'user-self', displayName: 'Me');
    await container.read(conversationsControllerProvider.future);
    final result = await container
        .read(conversationsControllerProvider.notifier)
        .openDirectByEmail('me@example.com');
    expect(result.isSuccess, isFalse);
  });

  test('openDirectByEmail creates and returns the conversation', () async {
    profiles.profilesByEmail['ana@example.com'] =
        const UserProfile(userId: 'user-ana', displayName: 'Ana');
    await container.read(conversationsControllerProvider.future);
    final result = await container
        .read(conversationsControllerProvider.notifier)
        .openDirectByEmail('ana@example.com');
    result.fold(
      (conversation) => expect(conversation.memberIds, contains('user-ana')),
      (failure) => fail('expected success, got $failure'),
    );
  });
}
