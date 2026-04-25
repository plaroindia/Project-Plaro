import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ResetPasswordPage.dart';
import 'onboarding_flow.dart';

class OTPVerificationPage extends StatefulWidget {
  final String email;
  final String userId;
  final String purpose; // 'signup' | 'password_reset' | 'email_change'
  final String? password;
  final String? newEmail;

  const OTPVerificationPage({
    super.key,
    required this.email,
    required this.userId,
    required this.purpose,
    this.password,
    this.newEmail,
  });

  @override
  State<OTPVerificationPage> createState() => _OTPVerificationPageState();
}

class _OTPVerificationPageState extends State<OTPVerificationPage> {
  final List<TextEditingController> _controllers =
  List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _fieldNodes = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  bool _resending = false;

  // ── Resend cooldown (Supabase free plan: 60 s rate limit) ─────────────────
  int _resendCooldown = 0; // seconds remaining
  bool get _canResend => _resendCooldown == 0 && !_resending;

  void _startCooldown() {
    setState(() => _resendCooldown = 60);
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _resendCooldown = (_resendCooldown - 1).clamp(0, 60));
      return _resendCooldown > 0;
    });
  }

  @override
  void initState() {
    super.initState();
    // Start cooldown on arrival — OTP was just sent
    _startCooldown();
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final n in _fieldNodes) n.dispose();
    super.dispose();
  }

  String get _otp => _controllers.map((c) => c.text).join();

  // ── Verify ────────────────────────────────────────────────────────────────
  Future<void> _verifyOTP() async {
    final code = _otp.trim();
    if (code.length != 6) {
      _msg('Please enter the complete 6-digit code', Colors.orange);
      return;
    }
    setState(() => _loading = true);

    try {
      if (widget.purpose == 'email_change') {
        await _verifyEmailChangeViaEdge(code);
        return;
      }

      // signup + password_reset → verifyOTP client-side (type: email)
      await Supabase.instance.client.auth.verifyOTP(
        email: widget.email.trim(),
        token: code,
        type: OtpType.email,
      );

      if (widget.purpose == 'signup') {
        await Supabase.instance.client.auth
            .updateUser(UserAttributes(data: {'onboarding_complete': false}));
        if (mounted) {
          _msg('Email verified!', Colors.green);
          await Future.delayed(const Duration(milliseconds: 400));
          Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const OnboardingFlow()));
        }
      } else if (widget.purpose == 'password_reset') {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) throw Exception('No session after OTP verify');
        if (mounted) {
          _msg('Code verified! Set your new password.', Colors.green);
          await Future.delayed(const Duration(milliseconds: 400));
          Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (_) => ResetPasswordPage(
                    accessToken: session.accessToken,
                    refreshToken: session.refreshToken,
                  )));
        }
      }
    } catch (e) {
      // Fallback via edge function
      if (widget.purpose != 'email_change') {
        try {
          final response = await Supabase.instance.client.functions.invoke(
            'verify-otp',
            body: {
              'email': widget.email.trim(),
              'otp': code,
              'purpose': widget.purpose
            },
          );
          if (response.data['success'] == true) {
            if (widget.purpose == 'signup') {
              final sessionData = response.data['session'];
              if (sessionData?['refresh_token'] != null) {
                await Supabase.instance.client.auth
                    .setSession(sessionData['refresh_token']);
              }
              if (mounted) {
                _msg('Verified!', Colors.green);
                await Future.delayed(const Duration(milliseconds: 400));
                Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const OnboardingFlow()));
              }
            } else {
              final access = response.data['accessToken'] as String?;
              final refresh = response.data['refreshToken'] as String?;
              if (access != null && refresh != null && mounted) {
                _msg('Code verified!', Colors.green);
                await Future.delayed(const Duration(milliseconds: 400));
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ResetPasswordPage(
                          accessToken: access,
                          refreshToken: refresh,
                        )));
              } else {
                throw Exception('No tokens received');
              }
            }
            return;
          } else {
            throw Exception(response.data['error'] ?? 'Verification failed');
          }
        } catch (_) {}
      }
      if (mounted) {
        _msg('Incorrect or expired code. Try again.', Colors.red);
        _clearOTP();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyEmailChangeViaEdge(String code) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'verify-otp',
        body: {
          'email': widget.email.trim(),
          'otp': code,
          'purpose': 'email_change',
          'new_email': widget.newEmail,
        },
      );
      if (response.data['success'] == true) {
        if (mounted) {
          _msg('Email updated!', Colors.green);
          await Future.delayed(const Duration(milliseconds: 400));
          Navigator.pop(context, true);
        }
      } else {
        throw Exception(response.data['error'] ?? 'Verification failed');
      }
    } catch (e) {
      if (mounted) {
        _msg('Incorrect or expired code. Try again.', Colors.red);
        _clearOTP();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearOTP() {
    for (final c in _controllers) c.clear();
    if (_fieldNodes[0].canRequestFocus) _fieldNodes[0].requestFocus();
  }

  Future<void> _resendOTP() async {
    if (!_canResend) return;
    setState(() => _resending = true);
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'send-otp',
        body: {
          'email': widget.email,
          'purpose': widget.purpose,
          if (widget.password != null) 'password': widget.password,
          if (widget.newEmail != null) 'new_email': widget.newEmail,
        },
      );
      if (response.data['success'] == true) {
        if (mounted) {
          _msg('New code sent!', Colors.green);
          _clearOTP();
          _startCooldown(); // restart 60-second cooldown
        }
      } else {
        throw Exception(response.data['error'] ?? 'Failed to resend');
      }
    } catch (e) {
      final errStr = e.toString();
      // Supabase 429 rate limit — show friendly message, start cooldown anyway
      if (errStr.contains('429') || errStr.contains('rate') || errStr.contains('60 seconds')) {
        if (mounted) {
          _msg('Please wait 60 seconds before requesting another code.', Colors.orange);
          _startCooldown();
        }
      } else {
        if (mounted) _msg('Could not resend. Try again shortly.', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _msg(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          color == Colors.green
              ? Icons.check_circle
              : color == Colors.orange
              ? Icons.warning
              : Icons.error,
          color: Colors.white,
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ]),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(10),
    ));
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 5) {
        _fieldNodes[index + 1].requestFocus();
      } else {
        _fieldNodes[index].unfocus();
        if (_otp.length == 6) _verifyOTP();
      }
    } else {
      if (index > 0) {
        _controllers[index - 1].clear();
        _fieldNodes[index - 1].requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cursorColor = isDark ? Colors.white : Colors.black87;

    String title;
    String subtitle;
    switch (widget.purpose) {
      case 'email_change':
        title = 'Confirm Email Change';
        subtitle = 'Enter the 6-digit code sent to your current email\n${widget.email}';
        break;
      case 'password_reset':
        title = 'Reset Password';
        subtitle = 'Enter the 6-digit code sent to\n${widget.email}';
        break;
      default:
        title = 'Verify Email';
        subtitle = 'Enter the 6-digit code sent to\n${widget.email}';
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
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
              const Icon(Icons.mail_outline, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              Text('Check Your Email',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[400] : Colors.grey[600]),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),

              // ── 6 OTP boxes ────────────────────────────────────────────────
              // FIX: digits display as decorative glyphs when the app uses a
              // stylistic font. Force 'RobotoMono' (always bundled with Flutter)
              // on just these fields so digits are plain, monospaced, and large.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (i) {
                  return SizedBox(
                    width: 46,
                    height: 58,
                    child: TextFormField(
                      controller: _controllers[i],
                      focusNode: _fieldNodes[i],
                      autofocus: i == 0,
                      textAlign: TextAlign.center,
                      // FIX: bypass app font entirely with a system monospace font
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace', // system monospace — always plain digits
                        letterSpacing: 0,
                        height: 1.2,
                      ),
                      cursorColor: cursorColor,
                      cursorHeight: 24,
                      keyboardType: TextInputType.number,
                      maxLength: 1,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: isDark
                            ? Colors.grey[900]?.withOpacity(0.3)
                            : Colors.grey[100],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: isDark ? Colors.grey[800]! : Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.blue, width: 2),
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.redAccent),
                        ),
                        // Ensure content is vertically centred inside the box
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (v) => _onChanged(v, i),
                      enabled: !_loading,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: (_loading || _otp.length != 6) ? null : _verifyOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                  disabledBackgroundColor: Colors.blue.withOpacity(0.6),
                ),
                child: _loading
                    ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3))
                    : const Text('Verify Code',
                    style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 24),

              // Resend row with live 60-second cooldown counter
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Didn't receive the code? ",
                      style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600])),
                  _resending
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.blue))
                      : TextButton(
                    onPressed: _canResend ? _resendOTP : null,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _resendCooldown > 0
                          ? 'Resend in ${_resendCooldown}s'
                          : 'Resend',
                      style: TextStyle(
                        color: _canResend ? Colors.blue : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withOpacity(0.2)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: isDark
                          ? Colors.blue.shade800
                          : Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Check your spam folder if you don't see the email. The code expires in 10 minutes.",
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark
                                ? Colors.blue.shade300
                                : Colors.blue.shade700),
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