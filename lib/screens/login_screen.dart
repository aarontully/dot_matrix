import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _homeserverController = TextEditingController(
    text: 'https://matrix.org',
  );

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();
    final theme = Theme.of(context);
    final isDark = Get.isDarkMode;
    final backgroundColor = isDark
        ? AppTheme.darkBackground
        : const Color(0xFFF7F8FC);
    final cardColor = isDark ? AppTheme.darkSurface : Colors.white;
    final accentPanel = isDark
        ? const Color(0xFF233146)
        : const Color(0xFFEAF3FF);
    final bodyColor = theme.colorScheme.onSurface.withValues(alpha: 0.78);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.18 : 0.06,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: accentPanel,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        color: AppTheme.primaryBlue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Connect to Matrix',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sign in with your homeserver to restore your Matrix chats, profile, and encryption state on this device.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: bodyColor,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(labelText: 'Password'),
                      obscureText: true,
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _homeserverController,
                      decoration: const InputDecoration(
                        labelText: 'Homeserver',
                      ),
                    ),
                    const SizedBox(height: 24),
                    authController.obx(
                      (state) => Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _login,
                              child: const Text('Login'),
                            ),
                          ),
                        ],
                      ),
                      onLoading: const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      onError: (error) => Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _login,
                              child: const Text('Login'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Error: $error',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _login() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final homeserver = _homeserverController.text.trim();

    if (username.isEmpty || password.isEmpty || homeserver.isEmpty) {
      Get.snackbar('Error', 'Please fill all fields');
      return;
    }

    Get.find<AuthController>().login(username, password, homeserver);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _homeserverController.dispose();
    super.dispose();
  }
}
