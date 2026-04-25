// DEPRECATED: Use AppConfig instead
// This file is kept for backward compatibility but will be removed in future versions
import '../config/app_config.dart';

@Deprecated('Use AppConfig.supabaseUrl instead')
const String url = AppConfig.supabaseUrl;

@Deprecated('Use AppConfig.supabaseAnonKey instead')
const String anonKey = AppConfig.supabaseAnonKey;
