import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/result.dart';
import '../../../domain/personal/entities/conversation.dart';
import '../../../state/conversations_controller.dart';
import 'chat_screen.dart';
import 'new_conversation_sheet.dart';

/// Personal conversation list. States: loading, empty, error+retry, data.
/// No placeholder conversations are ever rendered.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _startConversation(context, ref),
        tooltip: 'New chat',
        child: const Icon(LucideIcons.edit),
      ),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          failure: error is AppFailure ? error : AppFailure(AppFailureKind.unknown, '$error'),
          onRetry: () => ref.read(conversationsControllerProvider.notifier).refresh(),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyState()
            : RefreshIndicator(
                onRefresh: () => ref.read(conversationsControllerProvider.notifier).refresh(),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (context, index) => _ConversationTile(conversation: items[index]),
                ),
              ),
      ),
    );
  }

  Future<void> _startConversation(BuildContext context, WidgetRef ref) async {
    final conversation = await showModalBottomSheet<Conversation>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const NewConversationSheet(),
    );
    if (conversation != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(conversation: conversation)),
      );
    }
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation});
  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
        child: Text(
          conversation.title.isEmpty ? '?' : conversation.title[0].toUpperCase(),
          style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
        ),
      ),
      title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: conversation.lastMessagePreview == null
          ? null
          : Text(
              conversation.lastMessagePreview!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (conversation.lastMessageAt != null)
            Text(_formatTime(conversation.lastMessageAt!),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (conversation.unreadCount > 0) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${conversation.unreadCount}',
                style: theme.textTheme.labelSmall?.copyWith(color: Colors.white),
              ),
            ),
          ],
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ChatScreen(conversation: conversation)),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final local = time.toLocal();
    if (now.difference(local).inDays == 0 && now.day == local.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.messagesSquare, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No conversations yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Start a chat with someone by their email address.',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.failure, required this.onRetry});
  final AppFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOffline = failure.kind == AppFailureKind.network;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isOffline ? LucideIcons.wifiOff : LucideIcons.alertTriangle,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(isOffline ? 'You are offline' : 'Could not load conversations',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              isOffline
                  ? 'Check your connection and try again.'
                  : (failure.message ?? 'An unexpected error occurred.'),
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
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
