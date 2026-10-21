/// Build-time configuration for the Sanai3y Supabase project.
///
/// Pass [publishableKey] with `--dart-define-from-file=supabase.local.json`.
/// This client never uses a Supabase service-role or secret key.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://oflqzgnbpbufoxzynaoq.supabase.co',
  );

  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static void validate() {
    if (publishableKey.isEmpty) {
      throw StateError(
        'Missing SUPABASE_PUBLISHABLE_KEY. Run with '
        '--dart-define-from-file=supabase.local.json.',
      );
    }
  }
}
