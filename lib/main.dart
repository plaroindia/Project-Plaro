import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'views/intro_page.dart';
import 'views/home_page.dart';
import 'views/login_page.dart';
import 'views/navipg.dart';
import 'viewmodels/theme_provider.dart';
import 'views/chat_list.dart';
import 'config/app_config.dart';
import 'utils/error_handler.dart';


final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize global error handler
  GlobalErrorHandler.initialize();

  // Initialize Supabase BEFORE runApp
  try {
    if (!AppConfig.validate()) {
      throw Exception('Invalid app configuration. Missing Supabase credentials.');
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: true,
      ),
    );
  } catch (e) {
    debugPrint('❌ Failed to initialize Supabase: $e');
    // Continue anyway - error will be shown in UI
  }

  // Initialize app links
  initAppLinks();

  runApp(const ProviderScope(child: MyApp()));
}

Future<void> initAppLinks() async {
  final appLinks = AppLinks();

  // Handle initial deep link (cold start)
  final initialLink = await appLinks.getInitialLink();
  if (initialLink != null) {
    _handleLink(initialLink.toString());
  }

  // Handle links while app is running
  appLinks.uriLinkStream.listen((uri) {
    _handleLink(uri.toString());
  });
}

void _handleLink(String link) {
  debugPrint('Received deep link: $link');
  final uri = Uri.parse(link);

  // Check for reset-password route
  if (uri.path == '/reset-password' && uri.queryParameters['token'] != null) {
    final token = uri.queryParameters['token']!;
    navigatorKey.currentState?.pushNamed('/reset-password', arguments: token);
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      routes: {
        '/login': (context) => const LoginScreen(),
        '/home': (context) => const HomeScreen(),
        '/navipg': (context) => navCard(),
        '/chat_list': (context) {
          final currentUser = Supabase.instance.client.auth.currentUser;
          if (currentUser == null) {
            return const LoginScreen();
          }
          return ChatList(userId: currentUser.id);
        },
      },
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
      title: 'PLARO',
      home: const IntroPage(),
      builder: (context, child) {
        return child ?? const SizedBox.shrink();
      },
    );
  }
}