/// Client-side delivery state machine for an outgoing message.
///
///   sending -> sent
///   sending -> failed -> retrying -> sent | failed
///
/// Incoming messages are always [MessageDeliveryState.sent].
enum MessageDeliveryState { sending, sent, failed, retrying }

class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.deliveryState,
    this.clientId,
    this.deletedAt,
    this.readBy = const <String>{},
  });

  /// Server id (uuid). For not-yet-acknowledged messages this equals
  /// [clientId] until the server row is confirmed.
  final String id;

  /// Client-generated idempotency key so retries never duplicate rows.
  final String? clientId;

  final String conversationId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final MessageDeliveryState deliveryState;
  final DateTime? deletedAt;

  /// User ids that have read this message (excluding the sender).
  final Set<String> readBy;

  bool get isDeleted => deletedAt != null;

  Message copyWith({
    String? id,
    MessageDeliveryState? deliveryState,
    DateTime? deletedAt,
    Set<String>? readBy,
  }) {
    return Message(
      id: id ?? this.id,
      clientId: clientId,
      conversationId: conversationId,
      senderId: senderId,
      body: body,
      createdAt: createdAt,
      deliveryState: deliveryState ?? this.deliveryState,
      deletedAt: deletedAt ?? this.deletedAt,
      readBy: readBy ?? this.readBy,
    );
  }
}
