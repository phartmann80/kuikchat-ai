import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/result.dart';
import '../domain/personal/entities/conversation.dart';
import 'providers.dart';

/// State for the conversation list: loading / data (possibly empty) / error.
class ConversationsController extends AsyncNotifier<List<Conversation>> {
  @override
  Future<List<Conversation>> build() async {
    final repo = ref.watch(personalConversationRepositoryProvider);
    return repo.loadConversations();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(personalConversationRepositoryProvider);
      return repo.loadConversations();
    });
  }

  /// Opens (or creates) a direct conversation with the user matching [email].
  /// Returns the conversation or a typed failure for the UI to render.
  Future<Result<Conversation>> openDirectByEmail(String email) async {
    try {
      final profiles = ref.read(personalProfileRepositoryProvider);
      final conversations = ref.read(personalConversationRepositoryProvider);
      final target = await profiles.findByEmail(email);
      if (target == null) {
        return const Failure(AppFailure(AppFailureKind.notFound, 'No KuikChat user with that email.'));
      }
      final auth = ref.read(personalAuthRepositoryProvider);
      if (target.userId == auth.currentUserId) {
        return const Failure(AppFailure(AppFailureKind.conflict, 'You cannot start a conversation with yourself.'));
      }
      final conversation = await conversations.openDirectConversation(target.userId);
      await refresh();
      return Success(conversation);
    } on AppFailure catch (failure) {
      return Failure(failure);
    } catch (error) {
      return Failure(AppFailure(AppFailureKind.unknown, error.toString()));
    }
  }
}

final conversationsControllerProvider =
    AsyncNotifierProvider<ConversationsController, List<Conversation>>(ConversationsController.new);
