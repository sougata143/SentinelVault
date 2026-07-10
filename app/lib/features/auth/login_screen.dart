import 'package:flutter/material.dart';
import 'package:core/core.dart';
import '../../theme/theme.dart';
import 'sign_up_screen.dart';
import 'unlock_screen.dart';

class LoginScreen extends StatefulWidget {
  final AuthClient authClient;

  const LoginScreen({
    super.key,
    required this.authClient,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      final token = await widget.authClient.login(email, password);

      if (mounted) {
        _passwordController.clear();
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => UnlockScreen(
              email: email,
              authClient: widget.authClient,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _passwordController.clear();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              color: AppTheme.surfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield, color: AppTheme.primaryColor, size: 32),
                            SizedBox(width: 12),
                            Text(
                              'SentinelVault',
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),
                      const Text(
                        'Log in to your account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.errorColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.errorColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        key: const Key('login-email-field'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email Address',
                          hintText: 'Enter your email',
                          prefixIcon: Icon(Icons.email_outlined, color: AppTheme.textSecondaryColor),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('login-password-field'),
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Account Password',
                          hintText: 'Enter your password',
                          prefixIcon: Icon(Icons.lock_outline, color: AppTheme.textSecondaryColor),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Password is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        key: const Key('login-button'),
                        onPressed: _isLoading ? null : _handleLogin,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Log In'),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        key: const Key('signup-link'),
                        onPressed: () {
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => SignUpScreen(authClient: widget.authClient),
                            ),
                          );
                        },
                        child: const Text(
                          "Don't have an account? Sign up",
                          style: TextStyle(color: AppTheme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
