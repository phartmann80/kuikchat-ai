import '../../../core/result.dart';
import '../entities/message.dart';
import '../repositories/personal_messaging_repositories.dart';

/// Use case: load message history for a conversation.
class LoadMessageHistory {
  const LoadMessageHistory(this._messages);

  final PersonalMessageRepository _messages;

  Future<Result<List<Message>>> call(String conversationId, {DateTime? before}) async {
    try {
      final history = await _messages.loadMessages(conversationId, before: before, limit: 50);
      return Success(history);
    } on AppFailure catch (failure) {
      return Failure(failure);
    } catch (error) {
      return Failure(AppFailure(AppFailureKind.unknown, error.toString()));
    }
  }
}
