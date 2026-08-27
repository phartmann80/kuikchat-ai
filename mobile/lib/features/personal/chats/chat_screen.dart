import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/result.dart';
import '../../../domain/personal/entities/conversation.dart';
import '../../../domain/personal/entities/message.dart';
import '../../../state/chat_controller.dart';
import '../../../state/providers.dart';

/// One open conversation.
/// Handled states: loading, load error + retry, empty, sending, sent,
/// failed + per-message retry, deleted, read receipts, offline banner.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});

  final Conversation conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    ref.read(chatControllerProvider(widget.conversation.id).notifier).sendText(text);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider(widget.conversation.id));
    final selfId = ref.watch(personalAuthRepositoryProvider).currentUserId;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.conversation.title),
        leading: IconButton(
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: chat.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _LoadError(
            failure: error is AppFailure ? error : AppFailure(AppFailureKind.unknown, '$error'),
            onRetry: () =>
                ref.read(chatControllerProvider(widget.conversation.id).notifier).reload(),
          ),
          data: (state) {
            if (state.phase == ChatPhase.error) {
              return _LoadError(
                failure: state.failure ?? const AppFailure(AppFailureKind.unknown),
                onRetry: () =>
                    ref.read(chatControllerProvider(widget.conversation.id).notifier).reload(),
              );
            }
            return Column(
              children: [
                if (state.failure != null && state.failure!.kind == AppFailureKind.network)
                  const _OfflineBanner(),
                Expanded(
                  child: state.messages.isEmpty
                      ? const _EmptyConversation()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: state.messages.length,
                          itemBuilder: (context, index) {
                            final message = state.messages[index];
                            return _MessageBubble(
                              message: message,
                              isOwn: message.senderId == selfId,
                              isReadByOthers: _isReadByOthers(state, message, selfId),
                              onRetry: message.deliveryState == MessageDeliveryState.failed
                                  ? () => ref
                                      .read(chatControllerProvider(widget.conversation.id).notifier)
                                      .retry(message.clientId!)
                                  : null,
                              onDelete: message.senderId == selfId && !message.isDeleted
                                  ? () => ref
                                      .read(chatControllerProvider(widget.conversation.id).notifier)
                                      .deleteMessage(message.id)
                                  : null,
                            );
                          },
                        ),
                ),
                _Composer(controller: _composer, onSend: _send),
              ],
            );
          },
        ),
      ),
    );
  }

  bool _isReadByOthers(ChatState state, Message message, String? selfId) {
    if (message.senderId != selfId) return false;
    // A message counts as read when any other member's last-read message is
    // this message or a later one.
    final index = state.messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return false;
    for (final entry in state.readStates.entries) {
      if (entry.key == selfId) continue;
      final readIndex = state.messages.indexWhere((m) => m.id == entry.value);
      if (readIndex >= index) return true;
    }
    return false;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isOwn,
    required this.isReadByOthers,
    this.onRetry,
    this.onDelete,
  });

  final Message message;
  final bool isOwn;
  final bool isReadByOthers;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = message.deliveryState == MessageDeliveryState.failed;

    final bubbleColor = message.isDeleted
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
        : isOwn
            ? (failed ? scheme.error.withValues(alpha: 0.25) : scheme.primary)
            : scheme.surfaceContainerHighest;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(isOwn ? 16 : 4),
          bottomRight: Radius.circular(isOwn ? 4 : 16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isDeleted)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.ban, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('Message deleted',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant)),
              ],
            )
          else
            Text(
              message.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isOwn && !failed ? Colors.white : scheme.onSurface,
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _time(message.createdAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isOwn && !failed
                      ? Colors.white.withValues(alpha: 0.7)
                      : scheme.onSurfaceVariant,
                ),
              ),
              if (isOwn && !message.isDeleted) ...[
                const SizedBox(width: 4),
                _StatusIcon(state: message.deliveryState, isRead: isReadByOthers),
              ],
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: isOwn ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: onDelete == null ? null : () => _confirmDelete(context),
            child: Align(
              alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
              child: bubble,
            ),
          ),
          if (failed && onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: TextButton.icon(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.error,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('Not sent. Tap to retry'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('The message will be removed for everyone in this chat.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) onDelete?.call();
  }

  String _time(DateTime time) {
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.state, required this.isRead});
  final MessageDeliveryState state;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (state) {
      MessageDeliveryState.sending ||
      MessageDeliveryState.retrying =>
        Icon(LucideIcons.clock, size: 12, color: Colors.white.withValues(alpha: 0.7)),
      MessageDeliveryState.failed => Icon(LucideIcons.alertCircle, size: 12, color: scheme.error),
      MessageDeliveryState.sent => Icon(
          isRead ? LucideIcons.checkCheck : LucideIcons.check,
          size: 14,
          color: isRead ? const Color(0xFF86EFAC) : Colors.white.withValues(alpha: 0.7),
        ),
    };
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Message'),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSend,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(14),
            ),
            child: const Icon(LucideIcons.send, size: 18),
          ),
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.messageSquare, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No messages yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('Say hello to start the conversation.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.failure, required this.onRetry});
  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOffline = failure.kind == AppFailureKind.network;
    final isUnauthorized = failure.kind == AppFailureKind.unauthorized;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOffline
                  ? LucideIcons.wifiOff
                  : isUnauthorized
                      ? LucideIcons.shieldAlert
                      : LucideIcons.alertTriangle,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              isOffline
                  ? 'You are offline'
                  : isUnauthorized
                      ? 'You do not have access to this conversation'
                      : 'Could not load messages',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.error.withValues(alpha: 0.15),
      child: Row(
        children: [
          Icon(LucideIcons.wifiOff, size: 14, color: scheme.error),
          const SizedBox(width: 8),
          Text('Connection problem — messages will show as failed until retried.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error)),
        ],
      ),
    );
  }
}
