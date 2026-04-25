import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'signup_page.dart';
import 'package:plaro_3/viewmodels/auth_provider.dart';
import '../Viewmodels/theme_provider.dart';
import 'forgot_password_page.dart';
import 'onboarding_flow.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _animation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _animationController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _animationController.forward();
      }
    });
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final success = await ref.read(authControllerProvider).login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        if (success) {
          _showFeedback('Login Successful!', Colors.green, Icons.check_circle);
          Future.delayed(const Duration(seconds: 1), () {
            Navigator.pushReplacementNamed(context, '/navipg');
          });
        } else {
          _showFeedback('Invalid email or password', Colors.red, Icons.error);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showFeedback('Error: ${e.toString()}', Colors.red, Icons.error);
      }
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final result = await ref.read(authControllerProvider).googleSignIn();
      if (mounted) {
        setState(() => _isGoogleLoading = false);
        if (result['success'] == true) {
          if (result['requiresOnboarding'] == true) {
            _showFeedback('Welcome! Let\'s set up your profile', Colors.green, Icons.check_circle);
            Future.delayed(const Duration(seconds: 1), () {
              Navigator.pushReplacement(context,
                  MaterialPageRoute(builder: (_) => const OnboardingFlow()));
            });
          } else {
            _showFeedback('Welcome back!', Colors.green, Icons.check_circle);
            Future.delayed(const Duration(seconds: 1), () {
              Navigator.pushReplacementNamed(context, '/navipg');
            });
          }
        } else if (result['cancelled'] == true) {
          _showFeedback('Sign-in cancelled', Colors.orange, Icons.info);
        } else {
          _showFeedback(result['error'] ?? 'Google Sign-In failed', Colors.red, Icons.error);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
        _showFeedback('Error: ${e.toString()}', Colors.red, Icons.error);
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    return null;
  }

  InputDecoration _inputDecoration(String label, {Widget? prefixIcon, Widget? suffixIcon}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? Colors.grey[900]?.withOpacity(0.3) : Colors.grey[100],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cursorColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    onPressed: () =>
                        ref.read(themeNotifierProvider.notifier).toggleTheme(!isDark),
                    icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                        color: Theme.of(context).iconTheme.color),
                  ),
                ),
                ScaleTransition(
                  scale: _animation,
                  child: CircleAvatar(
                    radius: 60,
                    backgroundColor: Colors.transparent,
                    child: ClipOval(
                      child: Image.asset('assets/plaro_logo.png',
                          fit: BoxFit.cover, alignment: Alignment.center),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text("PLARO",
                    style: TextStyle(color: Colors.blue, fontSize: 20,
                        fontWeight: FontWeight.bold, letterSpacing: 2),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text("Sign In",
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 32, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 40),

                // Email field
                TextFormField(
                  controller: _emailController,
                  decoration: _inputDecoration('Email',
                      prefixIcon: Icon(Icons.email,
                          color: isDark ? Colors.grey : Colors.grey[600])),
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  cursorColor: cursorColor,
                  validator: _validateEmail,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.next,
                  // FIX: place cursor at tap position instead of selecting all text
                  onTap: () {
                    final pos = _emailController.text.length;
                    _emailController.selection = TextSelection.fromPosition(
                      TextPosition(offset: pos),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Password field
                TextFormField(
                  controller: _passwordController,
                  decoration: _inputDecoration('Password',
                      prefixIcon: Icon(Icons.lock,
                          color: isDark ? Colors.grey : Colors.grey[600]),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: isDark ? Colors.grey : Colors.grey[600]),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      )),
                  obscureText: _obscurePassword,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  cursorColor: cursorColor,
                  validator: _validatePassword,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  // FIX: place cursor at tap position instead of selecting all text
                  onTap: () {
                    final pos = _passwordController.text.length;
                    _passwordController.selection = TextSelection.fromPosition(
                      TextPosition(offset: pos),
                    );
                  },
                ),
                const SizedBox(height: 8),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? false),
                          fillColor: WidgetStateProperty.resolveWith<Color>((states) =>
                          _rememberMe
                              ? Colors.blue
                              : (isDark ? Colors.grey[800]! : Colors.grey[300]!)),
                        ),
                        Text('Remember me',
                            style: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[600])),
                      ],
                    ),
                    TextButton(
                      onPressed: () {
                        try {
                          Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const ForgotPasswordPage()));
                        } catch (_) {
                          _showFeedback(
                              'Forgot password coming soon!', Colors.blue, Icons.info);
                        }
                      },
                      child: Text('Forgot Password?',
                          style: TextStyle(color: Colors.blue[300])),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                    disabledBackgroundColor: Colors.blue.withOpacity(0.6),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 24, width: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text('Sign In',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),

                Row(children: [
                  Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[300])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('or', style: TextStyle(
                        color: isDark ? Colors.grey[500] : Colors.grey[600])),
                  ),
                  Expanded(child: Divider(color: isDark ? Colors.grey[800] : Colors.grey[300])),
                ]),
                const SizedBox(height: 24),

                Center(
                  child: SizedBox(
                    width: 200,
                    child: OutlinedButton(
                      onPressed: _isGoogleLoading ? null : _googleSignIn,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        side: BorderSide(color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(60)),
                        elevation: 0,
                      ),
                      child: _isGoogleLoading
                          ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                          : Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset('assets/google_icon.png',
                                height: 30, filterQuality: FilterQuality.high),
                            const SizedBox(width: 16),
                            const Text("Sign in with Google"),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Don't have an account?",
                        style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600])),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const SigninScreen())),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Sign Up',
                          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}