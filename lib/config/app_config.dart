/// App configuration with environment variable support
/// 
/// Usage:
/// - For development: Use --dart-define flags
/// - For production: Set environment variables or use CI/CD secrets
class AppConfig {
  // Supabase configuration
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gcsundjelxodkbdnuaxr.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imdjc3VuZGplbHhvZGtiZG51YXhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTEzNDM0NjEsImV4cCI6MjA2NjkxOTQ2MX0.TLblseK15hGH4h1nrc5vbQ52_rjfx8NPFzAmO8ZwIXU',
  );

  // Google Sign-In configuration
  static const String googleSignInServerClientId = String.fromEnvironment(
    'GOOGLE_SIGN_IN_CLIENT_ID',
    defaultValue: '381063348704-crl2r9amlaer6v747t0hsurj89g076pi.apps.googleusercontent.com',
  );

  // App configuration
  static const bool isDebugMode = bool.fromEnvironment(
    'DEBUG_MODE',
    defaultValue: false,
  );

  /// Validate that required configuration is present
  static bool validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      return false;
    }
    return true;
  }
}

