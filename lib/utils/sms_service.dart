import 'dart:convert';
import 'package:http/http.dart' as http;

/// Asks the Sakay Tiker SMS Worker (on Cloudflare) to text a driver.
/// The Semaphore key is kept only inside the Worker, never in this app.
class SmsService {
  /// Paste your Worker address here, for example
  /// 'https://sakay-tiker-sms.your-name.workers.dev'
  static const String workerUrl = 'https://sakay-tiker-sms.mentholr3d.workers.dev';

  /// Returns true if the Worker sent the driver's approval/decline text.
  static Future<bool> notifyDriver(String driverId) async {
    if (!workerUrl.startsWith('https://')) return false;
    try {
      final response = await http
          .post(
            Uri.parse(workerUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'driverId': driverId}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body);
      return data is Map && data['ok'] == true && data['sent'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Used by the "Text driver" fallback button.
  static String formatPhone(String phoneNumber) {
    var cleaned = phoneNumber.trim().replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.startsWith('+63')) {
      cleaned = '0${cleaned.substring(3)}';
    } else if (cleaned.startsWith('63') && cleaned.length == 12) {
      cleaned = '0${cleaned.substring(2)}';
    }
    return cleaned;
  }
}