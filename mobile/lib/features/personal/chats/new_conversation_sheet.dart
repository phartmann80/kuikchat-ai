import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/result.dart';
import '../../../domain/personal/entities/conversation.dart';
import '../../../state/conversations_controller.dart';

/// Bottom sheet to start a direct conversation by exact email lookup.
/// States: idle, searching, not found, blocked, offline, success (pops with
/// the conversation).
class NewConversationSheet extends ConsumerStatefulWidget {
  const NewConversationSheet({super.key});

  @override
  ConsumerState<NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends ConsumerState<NewConversationSheet> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(conversationsControllerProvider.notifier)
        .openDirectByEmail(email);
    if (!mounted) return;
    result.fold(
      (conversation) => Navigator.of(context).pop<Conversation>(conversation),
      (failure) => setState(() {
        _busy = false;
        _error = switch (failure.kind) {
          AppFailureKind.notFound => 'No KuikChat user with that email.',
          AppFailureKind.blocked => 'You cannot message this user.',
          AppFailureKind.network => 'No connection. Try again.',
          AppFailureKind.unauthorized => 'You are not allowed to do that.',
          _ => failure.message ?? 'Could not open the conversation.',
        };
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(
          left: 24, right: 24, top: 24, bottom: 24 + viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New chat', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _open(),
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(LucideIcons.atSign, size: 18),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _open,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.messageSquarePlus, size: 18),
            label: const Text('Start chat'),
          ),
        ],
      ),
    );
  }
}
