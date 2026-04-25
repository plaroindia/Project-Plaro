import 'package:flutter/material.dart';
import 'package:plaro_3/views/login_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plaro_3/viewmodels/auth_provider.dart';
import '../Viewmodels/theme_provider.dart';
import 'OTPVerificationPage.dart';
import 'legal_page.dart';

class SigninScreen extends ConsumerStatefulWidget {
  const SigninScreen({super.key});

  @override
  ConsumerState<SigninScreen> createState() => _SigninScreenState();
}

class _SigninScreenState extends ConsumerState<SigninScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptTerms = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this, duration: const Duration(seconds: 2),
    );
    _animation = Tween<double>(begin: 0.9, end: 1.0)
        .animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _animationController.reverse();
        else if (status == AnimationStatus.dismissed) _animationController.forward();
      });
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, Color color, IconData icon) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(10),
    ));
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      _showFeedback('Please accept the terms and conditions', Colors.red, Icons.error);
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await ref.read(authControllerProvider).signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        if (result['success'] == true) {
          _showFeedback('Verification code sent!', Colors.green, Icons.check_circle);
          Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => OTPVerificationPage(
              email: _emailController.text.trim(),
              userId: result['userId'],
              purpose: 'signup',
              password: _passwordController.text,
            ),
          ));
        } else {
          _showFeedback(result['error'] ?? 'Sign up failed', Colors.red, Icons.error);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
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
    if (value == null || value.isEmpty) return 'Please enter a password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != _passwordController.text) return 'Passwords do not match';
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
    ref.watch(themeNotifierProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cursorColor = isDark ? Colors.white : Colors.black87; // ← FIX

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
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back, color: Theme.of(context).iconTheme.color),
                    ),
                    IconButton(
                      onPressed: () => ref.read(themeNotifierProvider.notifier).toggleTheme(!isDark),
                      icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode,
                          color: Theme.of(context).iconTheme.color),
                    ),
                  ],
                ),
                ScaleTransition(
                  scale: _animation,
                  child: CircleAvatar(
                    radius: 50,
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
                Text("Create Account",
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 32, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text("Join our community today",
                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 16),
                    textAlign: TextAlign.center),
                const SizedBox(height: 40),

                TextFormField(
                  controller: _emailController,
                  decoration: _inputDecoration('Email Address',
                      prefixIcon: Icon(Icons.email, color: isDark ? Colors.grey : Colors.grey[600])),
                  keyboardType: TextInputType.emailAddress,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  cursorColor: cursorColor, // ← FIX
                  validator: _validateEmail,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  decoration: _inputDecoration('Password',
                      prefixIcon: Icon(Icons.lock, color: isDark ? Colors.grey : Colors.grey[600]),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: isDark ? Colors.grey : Colors.grey[600]),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      )),
                  obscureText: _obscurePassword,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  cursorColor: cursorColor, // ← FIX
                  validator: _validatePassword,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: _inputDecoration('Confirm Password',
                      prefixIcon: Icon(Icons.lock_outline, color: isDark ? Colors.grey : Colors.grey[600]),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                            color: isDark ? Colors.grey : Colors.grey[600]),
                        onPressed: () =>
                            setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      )),
                  obscureText: _obscureConfirmPassword,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  cursorColor: cursorColor, // ← FIX
                  validator: _validateConfirmPassword,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _signUp(),
                ),
                const SizedBox(height: 16),

                // Terms row — tappable links navigate to LegalPage
                Row(
                  children: [
                    Checkbox(
                      value: _acceptTerms,
                      onChanged: (v) => setState(() => _acceptTerms = v ?? false),
                      fillColor: WidgetStateProperty.resolveWith<Color>((states) =>
                      _acceptTerms
                          ? Colors.blue
                          : (isDark ? Colors.grey[800]! : Colors.grey[300]!)),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const LegalPage(showTerms: true))),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                                color: isDark ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                            children: [
                              const TextSpan(text: 'I agree to the '),
                              TextSpan(
                                text: 'Terms & Conditions',
                                style: TextStyle(
                                    color: Colors.blue[300],
                                    decoration: TextDecoration.underline),
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(
                                    color: Colors.blue[300],
                                    decoration: TextDecoration.underline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                ElevatedButton(
                  onPressed: _isLoading ? null : _signUp,
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
                      : const Text('Create Account',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Already have an account?",
                        style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600])),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.pushReplacement(context,
                          MaterialPageRoute(builder: (_) => const LoginScreen())),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text('Sign In',
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