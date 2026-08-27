import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/personal_env.dart';
import '../../core/result.dart';

/// Single access point to the PERSONAL Supabase project.
///
/// This wrapper exists so that:
///  * widgets can never import supabase directly (lint-able boundary),
///  * a Business client can never be passed where a Personal one belongs,
///  * failures are translated into typed [AppFailure]s in one place.
class SupabasePersonalClient {
  SupabasePersonalClient(this.raw);

  /// Uses the app-wide instance initialised in main() from [PersonalEnv].
  factory SupabasePersonalClient.fromEnv() {
    if (!PersonalEnv.isConfigured) {
      throw const AppFailure(
        AppFailureKind.notConfigured,
        'Personal backend is not configured for this build.',
      );
    }
    return SupabasePersonalClient(Supabase.instance.client);
  }

  final SupabaseClient raw;

  static AppFailure mapError(Object error) {
    if (error is AppFailure) return error;
    if (error is AuthException) {
      return AppFailure(AppFailureKind.unauthorized, error.message);
    }
    if (error is PostgrestException) {
      final code = error.code ?? '';
      if (code == '42501' || code == 'PGRST301' || code == '401' || code == '403') {
        return AppFailure(AppFailureKind.unauthorized, error.message);
      }
      if (code == '23505') {
        return AppFailure(AppFailureKind.conflict, error.message);
      }
      if (code == 'PGRST116') {
        return AppFailure(AppFailureKind.notFound, error.message);
      }
      return AppFailure(AppFailureKind.unknown, error.message);
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('Connection') ||
        text.contains('Failed host lookup') ||
        text.contains('TimeoutException')) {
      return const AppFailure(AppFailureKind.network, 'Network unavailable');
    }
    return AppFailure(AppFailureKind.unknown, text);
  }
}
