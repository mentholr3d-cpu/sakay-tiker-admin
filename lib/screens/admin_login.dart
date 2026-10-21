import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/password_utils.dart';
import '../widgets/animated_press.dart';
import '../widgets/mountain_silhouette.dart';
import 'admin_dashboard.dart';
import 'admin_account_dialogs.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _emailController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  bool? _accountExists;

  @override
  void initState() {
    super.initState();
    _checkAccountExists();
  }

  Future<void> _checkAccountExists() async {
    final doc = await FirebaseFirestore.instance.collection('admin_config').doc('credentials').get();
    if (!mounted) return;
    setState(() => _accountExists = doc.exists);
  }

  Future<void> _setupAccount() async {
    if (_usernameController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailController.text.trim())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid recovery email')),
      );
      return;
    }

    if (_passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    setState(() => _isLoading = true);

    await FirebaseFirestore.instance.collection('admin_config').doc('credentials').set({
      'username': _usernameController.text.trim(),
      'passwordHash': hashPassword(_passwordController.text),
      'email': _emailController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _completeLogin();
  }

  Future<void> _login() async {
    if (_usernameController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter username and password')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final doc = await FirebaseFirestore.instance.collection('admin_config').doc('credentials').get();

    if (!mounted) return;

    final data = doc.data();
    if (data == null ||
        data['username'] != _usernameController.text.trim() ||
        data['passwordHash'] != hashPassword(_passwordController.text)) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incorrect username or password')),
      );
      return;
    }

    await _completeLogin();
  }

  Future<void> _completeLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('adminLoggedIn', true);

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const AdminDashboardScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSetup = _accountExists == false;

    return Scaffold(
      body: _accountExists == null
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 400,
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 8)),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        child: SizedBox(
                          height: 190,
                          width: double.infinity,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                const Align(
                                  alignment: Alignment.bottomCenter,
                                  child: MountainSilhouette(height: 50),
                                ),
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                        child: Image.asset('assets/images/logo.png', height: 60),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Sakay Tiker Admin',
                                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(28.0),
                        child: Column(
                          children: [
                            Text(
                              isSetup ? 'Create Admin Account' : 'Admin Login',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            if (isSetup) ...[
                              const SizedBox(height: 4),
                              const Text(
                                'No admin account found. Set one up now.',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 20),
                            TextField(
                              controller: _usernameController,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            if (isSetup) ...[
                              const SizedBox(height: 14),
                              TextField(
                                controller: _confirmPasswordController,
                                obscureText: _obscure,
                                decoration: const InputDecoration(
                                  labelText: 'Confirm Password',
                                  prefixIcon: Icon(Icons.lock_outline),
                                ),
                              ),
                            ],
                            if (isSetup) ...[
                              const SizedBox(height: 14),
                              TextField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                decoration: const InputDecoration(
                                  labelText: 'Recovery Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                              ),
                            ] else ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => showForgotPasswordDialog(context),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            AnimatedPress(
                              onTap: _isLoading ? null : (isSetup ? _setupAccount : _login),
                              child: SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () {},
                                  child: _isLoading
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(isSetup ? 'Create Account & Log In' : 'Log In'),
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
            ),
    );
  }
}