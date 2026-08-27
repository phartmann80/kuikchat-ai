import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/personal/supabase_personal_auth_repository.dart';
import '../data/personal/supabase_personal_client.dart';
import '../data/personal/supabase_personal_conversation_repository.dart';
import '../data/personal/supabase_personal_message_repository.dart';
import '../domain/personal/repositories/personal_auth_repository.dart';
import '../domain/personal/repositories/personal_messaging_repositories.dart';
import '../domain/personal/usecases/load_message_history.dart';
import '../domain/personal/usecases/send_text_message.dart';

/// Repository wiring for the PERSONAL environment.
///
/// Tests override these providers with controlled fakes. Business will get
/// its own, parallel set of providers backed by the Business project —
/// the two must never share a client or a provider.
final personalClientProvider = Provider<SupabasePersonalClient>((ref) {
  return SupabasePersonalClient.fromEnv();
});

final personalAuthRepositoryProvider = Provider<PersonalAuthRepository>((ref) {
  return SupabasePersonalAuthRepository(ref.watch(personalClientProvider));
});

final personalProfileRepositoryProvider = Provider<PersonalProfileRepository>((ref) {
  return SupabasePersonalProfileRepository(ref.watch(personalClientProvider));
});

final personalConversationRepositoryProvider = Provider<PersonalConversationRepository>((ref) {
  return SupabasePersonalConversationRepository(ref.watch(personalClientProvider));
});

final personalMessageRepositoryProvider = Provider<PersonalMessageRepository>((ref) {
  return SupabasePersonalMessageRepository(ref.watch(personalClientProvider));
});

final sendTextMessageProvider = Provider<SendTextMessage>((ref) {
  return SendTextMessage(ref.watch(personalMessageRepositoryProvider));
});

final loadMessageHistoryProvider = Provider<LoadMessageHistory>((ref) {
  return LoadMessageHistory(ref.watch(personalMessageRepositoryProvider));
});
