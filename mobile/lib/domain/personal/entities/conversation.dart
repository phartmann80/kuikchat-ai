/// A Personal conversation (direct for this milestone; groups share the same
/// membership model server-side).
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.isDirect,
    required this.memberIds,
    this.lastMessagePreview,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  final String id;

  /// For direct conversations this is the other member's display name.
  final String title;
  final bool isDirect;
  final List<String> memberIds;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
}
