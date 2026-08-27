/// Compile-time configuration for the PERSONAL environment only.
///
/// Values are injected at build time with `--dart-define` and are the
/// project URL and the *anon* (publishable) key of the dedicated Personal
/// Supabase project. The anon key is safe to embed in a client because all
/// data access is enforced by Row Level Security on the server.
///
/// NEVER add a service-role key here. NEVER add Business project values
/// here — Business gets its own isolated configuration and client.
class PersonalEnv {
  const PersonalEnv._();

  static const String supabaseUrl =
      String.fromEnvironment('PERSONAL_SUPABASE_URL');

  static const String supabaseAnonKey =
      String.fromEnvironment('PERSONAL_SUPABASE_ANON_KEY');

  /// True when the build was given a Personal backend to talk to.
  /// When false the app shows an explicit "backend not configured" state
  /// instead of pretending to work.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
