import 'package:flutter/material.dart';
import 'package:video_call_poc/uipages/chat_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();

  void _login() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Username cannot be empty.'),
        ),
      );
      return;
    }

    // Navigate to the ChatPage and replace the LoginPage in the stack,
    // so the user can't go back to the login screen.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ChatPage(username: username),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to CurrentLighting!'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Enter Your Username',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _login(),
              ),
              const SizedBox(height: 10),
              TextField(
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Enter Your Password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) {},
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                ),
                child: const Text('Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
