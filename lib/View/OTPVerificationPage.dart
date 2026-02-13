import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ResetPasswordPage.dart';
import 'onboarding_flow.dart';

class OTPVerificationPage extends StatefulWidget {
  final String email;
  final String userId;
  final String purpose; // 'signup' or 'password_reset'

  const OTPVerificationPage({
    super.key,
    required this.email,
    required this.userId,
    required this.purpose,
  });
  @override
  State<OTPVerificationPage> createState() => _OTPVerificationPageState();
}

class _OTPVerificationPageState extends State<OTPVerificationPage> {
  final List<TextEditingController> _controllers = List.generate(
    6,
        (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  bool _loading = false;
  bool _resending = false;

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  Future<void> _verifyOTP() async {
    if (_otp.length != 6) {
      _showMessage('Please enter the complete 6-digit code', Colors.orange);
      return;
    }

    setState(() => _loading = true);

    try {
      // Direct Supabase OTP verification (RECOMMENDED - no Edge Function needed)
      if (widget.purpose == 'signup') {
        // For signup verification
        await Supabase.instance.client.auth.verifyOTP(
          email: widget.email.trim(),
          token: _otp.trim(),
          type: OtpType.magiclink, // signInWithOtp sends magiclink token type
        );

        // Check if user is now authenticated
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser != null) {
          // Update user metadata for onboarding
          await Supabase.instance.client.auth.updateUser(
            UserAttributes(
              data: {'onboarding_complete': false},
            ),
          );

          if (mounted) {
            _showMessage('Email verified successfully!', Colors.green);
            await Future.delayed(const Duration(milliseconds: 500));

            // Navigate to onboarding
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const OnboardingFlow()),
            );
          }
        } else {
          throw Exception('User not authenticated after verification');
        }
      } else {
        // For password reset verification
        await Supabase.instance.client.auth.verifyOTP(
          email: widget.email.trim(),
          token: _otp.trim(),
          type: OtpType.recovery,
        );

        // Get the current session — contains both tokens after verifyOTP
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          if (mounted) {
            _showMessage('OTP verified! You can now reset your password.', Colors.green);
            await Future.delayed(const Duration(milliseconds: 500));

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ResetPasswordPage(
                  accessToken: session.accessToken,
                  refreshToken: session.refreshToken,   // ✅ required by setSession
                ),
              ),
            );
          }
        } else {
          throw Exception('No session available for password reset');
        }
      }
    } catch (e) {
      print('OTP Verification Error: $e');

      // Fallback: Try Edge Function if direct verification fails
      try {
        final response = await Supabase.instance.client.functions.invoke(
          'verify-otp',
          body: {
            'email': widget.email.trim(),
            'otp': _otp.trim(),
            'purpose': widget.purpose,
          },
        );

        if (response.data['success'] == true) {
          if (mounted) {
            _showMessage('Verification successful!', Colors.green);
            await Future.delayed(const Duration(milliseconds: 500));

            if (widget.purpose == 'signup') {
              // Try to get session from Edge Function response
              final sessionData = response.data['session'];
              if (sessionData != null && sessionData['refresh_token'] != null) {
                // Set session using refresh token from Edge Function
                await Supabase.instance.client.auth.setSession(
                  sessionData['refresh_token'],
                );
              }

              // Navigate to onboarding
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const OnboardingFlow()),
              );
            } else {
              // For password reset fallback via edge function
              final accessToken = response.data['accessToken'];
              final refreshToken = response.data['refreshToken'];
              if (accessToken != null && refreshToken != null) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ResetPasswordPage(
                      accessToken: accessToken,
                      refreshToken: refreshToken,       // ✅ required by setSession
                    ),
                  ),
                );
              } else {
                throw Exception('No tokens received for password reset');
              }
            }
          }
        } else {
          throw Exception(response.data['error'] ?? 'Verification failed');
        }
      } catch (edgeError) {
        print('Edge Function Error: $edgeError');
        if (mounted) {
          _showMessage('Verification failed: ${e.toString()}', Colors.red);
          _clearOTP();
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  void _clearOTP() {
    for (var controller in _controllers) {
      controller.clear();
    }
    if (_focusNodes[0].canRequestFocus) {
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resendOTP() async {
    setState(() => _resending = true);

    try {
      await Supabase.instance.client.functions.invoke(
        'send-otp',
        body: {
          'email': widget.email,
          'purpose': widget.purpose,
        },
      );

      if (mounted) {
        _showMessage('New code sent to your email', Colors.green);
        _clearOTP();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Error resending code: ${e.toString()}', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green
                  ? Icons.check_circle
                  : color == Colors.orange
                  ? Icons.warning
                  : Icons.error,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        // Auto-verify when all 6 digits are entered
        if (_otp.length == 6) {
          _verifyOTP();
        }
      }
    }
  }

  void _onKeyDown(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text("Verify Email"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              Icon(Icons.mail_outline, size: 80, color: Colors.blue),
              const SizedBox(height: 24),

              Text(
                'Check Your Email',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onBackground,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              Text.rich(
                TextSpan(
                  text: 'We sent a 6-digit verification code to\n',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  children: [
                    TextSpan(
                      text: widget.email,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // OTP Input Fields
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  return SizedBox(
                    width: 45,
                    height: 55,
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) => _onKeyDown(event, index),
                      child: TextFormField(
                        controller: _controllers[index],
                        focusNode: _focusNodes[index],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onBackground,
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 1,
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor:
                          isDark
                              ? Colors.grey[900]?.withOpacity(0.3)
                              : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color:
                              isDark
                                  ? Colors.grey[800]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Colors.blue,
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) => _onChanged(value, index),
                        enabled: !_loading, // Disable input during verification
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),

              // Verify Button
              ElevatedButton(
                onPressed: (_loading || _otp.length != 6) ? null : _verifyOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                  disabledBackgroundColor: Colors.blue.withOpacity(0.6),
                ),
                child:
                _loading
                    ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                )
                    : const Text(
                  'Verify Code',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Resend Code
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't receive the code? ",
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  TextButton(
                    onPressed: _resending ? null : _resendOTP,
                    child:
                    _resending
                        ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue,
                      ),
                    )
                        : const Text(
                      'Resend',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Help text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                  isDark
                      ? Colors.blue.shade900.withOpacity(0.2)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Check your spam folder if you don\'t see the email. The code expires in 10 minutes.',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                          isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}