import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../providers/hybrid_provider.dart';
import '../utils/text_formatter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    // Firebase Provider zaten main.dart'ta initialize ediliyor
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    debugPrint('Login attempt started for: ${_emailController.text}');

    final firebaseProvider = context.read<HybridProvider>();
    final success = await firebaseProvider.loginUser(
      _emailController.text.trim(),
      _passwordController.text,
    );

    debugPrint('Login result: $success');
    debugPrint('Firebase provider error: ${firebaseProvider.error}');

    if (success && mounted) {
      debugPrint('Login successful, navigating to home screen');
      
      // Save Remember Me preference
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool('remember_me', true);
      } else {
        await prefs.remove('remember_me');
      }

      // Navigate to home screen after successful login
      Navigator.of(context).pushReplacementNamed('/home');
    } else if (mounted) {
      debugPrint('Login failed, showing error message');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(firebaseProvider.error ?? 'Giriş başarısız'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppConstants.paddingLarge),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo ve başlık
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppConstants.primaryColor.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.receipt_long,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    AppConstants.appName,
                    style: AppConstants.headingStyle.copyWith(
                      color: AppConstants.primaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Hesabınıza giriş yapın',
                    style: AppConstants.bodyStyle.copyWith(
                      color: AppConstants.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // E-posta alanı
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      hintText: 'ornek@gmail.com',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    inputFormatters: [LowerCaseFormatter()],
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'E-posta gerekli';
                      }
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(value)) {
                        return 'Geçerli bir e-posta adresi girin';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Şifre alanı
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Şifre',
                      hintText: 'En az 8 karakter',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppConstants.textSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Şifre gerekli';
                      }
                      if (value.length < 8) {
                        return 'Şifre en az 8 karakter olmalı';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),

                  // Giriş butonu
                  Consumer<HybridProvider>(
                    builder: (context, firebaseProvider, child) {
                      return ElevatedButton(
                        onPressed: firebaseProvider.isLoading ? null : _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppConstants.primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppConstants.paddingMedium,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.borderRadius,
                            ),
                          ),
                        ),
                        child: firebaseProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                'Giriş Yap',
                                style: AppConstants.buttonStyle,
                              ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Beni Hatırla Checkbox
                  CheckboxListTile(
                    title: const Text('Beni Hatırla'),
                    value: _rememberMe,
                    onChanged: (newValue) {
                      setState(() {
                        _rememberMe = newValue ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    activeColor: AppConstants.primaryColor,
                  ),

                  const SizedBox(height: 24),

                  // Kayıt ol linki
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Hesabınız yok mu? ',
                        style: AppConstants.bodyStyle.copyWith(
                          color: AppConstants.textSecondary,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/register');
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppConstants.primaryColor,
                        ),
                        child: Text(
                          'Kayıt Ol',
                          style: AppConstants.bodyStyle.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppConstants.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
