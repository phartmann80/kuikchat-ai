import '../../../core/result.dart';
import '../entities/message.dart';
import '../repositories/personal_messaging_repositories.dart';

/// Use case: send a text message with an idempotent client id.
/// Returns the acknowledged server message, or a typed failure the UI maps
/// to the failed/retry state.
class SendTextMessage {
  const SendTextMessage(this._messages);

  final PersonalMessageRepository _messages;

  Future<Result<Message>> call({
    required String conversationId,
    required String body,
    required String clientId,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const Failure(AppFailure(AppFailureKind.conflict, 'Empty message'));
    }
    if (trimmed.length > 4000) {
      return const Failure(AppFailure(AppFailureKind.conflict, 'Message too long (max 4000 characters)'));
    }
    try {
      final message = await _messages.sendText(
        conversationId: conversationId,
        body: trimmed,
        clientId: clientId,
      );
      return Success(message);
    } on AppFailure catch (failure) {
      return Failure(failure);
    } catch (error) {
      return Failure(AppFailure(AppFailureKind.unknown, error.toString()));
    }
  }
}
