import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/password_utils.dart';
import '../utils/admin_reset_service.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

void _msg(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Forgot password: email a code, then type the code and a new password.
Future<void> showForgotPasswordDialog(BuildContext context) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ForgotPasswordDialog(),
  );
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _code = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _codeSent = false;
  bool _obscure = true;
  String? _sentTo;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await AdminResetService.requestCode();
    if (!mounted) return;
    if (res['ok'] == true) {
      setState(() {
        _busy = false;
        _codeSent = true;
        _sentTo = res['sentTo']?.toString();
      });
    } else {
      setState(() {
        _busy = false;
        _error = AdminResetService.errorText(res['error']);
      });
    }
  }

  Future<void> _reset() async {
    if (!RegExp(r'^[0-9]{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    if (_pass.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (_pass.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final res = await AdminResetService.confirm(_code.text.trim(), hashPassword(_pass.text));
    if (!mounted) return;
    if (res['ok'] == true) {
      Navigator.pop(context);
      _msg(context, 'Password changed. You can log in now.');
    } else {
      setState(() {
        _busy = false;
        _error = AdminResetService.errorText(res['error'], left: res['left']);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forgot Password'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_codeSent)
                const Text('We will email a 6-digit code to the recovery email saved on the admin account.')
              else ...[
                Text('A code was sent to ${_sentTo ?? 'your email'}. Check your Spam folder too. It expires in 10 minutes.'),
                const SizedBox(height: 14),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pass,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'New password',
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _confirm,
                  obscureText: _obscure,
                  decoration: const InputDecoration(labelText: 'Confirm new password'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        if (_codeSent)
          TextButton(onPressed: _busy ? null : _sendCode, child: const Text('Resend code')),
        ElevatedButton(
          onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
          child: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(_codeSent ? 'Change Password' : 'Send Code'),
        ),
      ],
    );
  }
}

/// Change password (and recovery email) while logged in.
Future<void> showChangePasswordDialog(BuildContext context) async {
  final ref = FirebaseFirestore.instance.collection('admin_config').doc('credentials');
  final snap = await ref.get();
  if (!context.mounted) return;
  final currentEmail = (snap.data()?['email'] ?? '').toString();
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ChangePasswordDialog(initialEmail: currentEmail),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  final String initialEmail;
  const _ChangePasswordDialog({required this.initialEmail});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  late final TextEditingController _email = TextEditingController(text: widget.initialEmail);
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final email = _email.text.trim();
    if (_current.text.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _error = 'Enter a valid recovery email.');
      return;
    }
    final changing = _new.text.isNotEmpty || _confirm.text.isNotEmpty;
    if (changing) {
      if (_new.text.length < 6) {
        setState(() => _error = 'New password must be at least 6 characters.');
        return;
      }
      if (_new.text != _confirm.text) {
        setState(() => _error = 'New passwords do not match.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ref = FirebaseFirestore.instance.collection('admin_config').doc('credentials');
    final snap = await ref.get();
    if (!mounted) return;
    if (snap.data()?['passwordHash'] != hashPassword(_current.text)) {
      setState(() {
        _busy = false;
        _error = 'Current password is incorrect.';
      });
      return;
    }
    final update = <String, dynamic>{
      'email': email,
      'passwordChangedAt': FieldValue.serverTimestamp(),
    };
    if (changing) update['passwordHash'] = hashPassword(_new.text);
    await ref.update(update);
    if (!mounted) return;
    Navigator.pop(context);
    _msg(context, changing ? 'Password updated.' : 'Recovery email saved.');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change Password'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _current,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Current password',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _new,
                obscureText: _obscure,
                decoration: const InputDecoration(labelText: 'New password (leave blank to keep)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: const InputDecoration(labelText: 'Confirm new password'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Recovery email',
                  helperText: 'Used to send the Forgot Password code',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }
}