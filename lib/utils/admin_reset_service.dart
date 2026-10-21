import 'dart:convert';
import 'package:http/http.dart' as http;
import 'sms_service.dart';

/// Talks to the Sakay Tiker Worker for the admin "Forgot password" email code.
/// The email service key (Brevo) lives only inside the Worker.
class AdminResetService {
  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(
            Uri.parse(SmsService.workerUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 25));
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
    } catch (_) {}
    return {'ok': false, 'error': 'network'};
  }

  /// Emails a 6-digit code to the admin's email on file.
  static Future<Map<String, dynamic>> requestCode() =>
      _post({'action': 'adminResetRequest'});

  /// Checks the code; if right, the Worker saves the new password hash.
  static Future<Map<String, dynamic>> confirm(String code, String newPasswordHash) =>
      _post({'action': 'adminResetConfirm', 'code': code, 'newPasswordHash': newPasswordHash});

  static String errorText(Object? error, {Object? left}) {
    switch (error) {
      case 'no_email':
        return 'No recovery email is saved yet. Log in and add one in Change Password, or ask the developer.';
      case 'no_account':
        return 'No admin account found.';
      case 'too_soon':
        return 'A code was just sent. Please wait a minute before asking again.';
      case 'email_failed':
        return 'The email could not be sent. Try again later.';
      case 'wrong_code':
        return 'Wrong code. Attempts left: ${left ?? 0}.';
      case 'expired':
        return 'The code has expired. Ask for a new one.';
      case 'too_many':
        return 'Too many wrong tries. Ask for a new code.';
      case 'no_code':
        return 'No code was requested. Ask for a new one.';
      default:
        return 'Something went wrong. Check your internet and try again.';
    }
  }
}