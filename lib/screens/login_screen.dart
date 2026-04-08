import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _homeserverController = TextEditingController(text: 'https://matrix.org');

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Login to Matrix')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Username'),
            ),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            TextField(
              controller: _homeserverController,
              decoration: const InputDecoration(labelText: 'Homeserver'),
            ),
            const SizedBox(height: 20),
            authState.maybeWhen(
              loading: () => const CircularProgressIndicator(),
              orElse: () => ElevatedButton(
                onPressed: _login,
                child: const Text('Login'),
              ),
            ),
            if (authState.hasError)
              Text('Error: ${authState.error}', style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  void _login() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final homeserver = _homeserverController.text.trim();

    if (username.isEmpty || password.isEmpty || homeserver.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields')),
      );
      return;
    }

    ref.read(authProvider.notifier).login(username, password, homeserver);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _homeserverController.dispose();
    super.dispose();
  }
}