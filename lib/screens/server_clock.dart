import 'package:cloud_firestore/cloud_firestore.dart';

/// Measures how far this computer's clock is from Firebase's server clock, so
/// "is this driver still active?" does not depend on the admin PC's clock being exact.
class ServerClock {
  static Duration _offset = Duration.zero;

  /// The current time according to the Firebase server.
  static DateTime now() => DateTime.now().add(_offset);

  static Future<void> sync() async {
    try {
      final ref = FirebaseFirestore.instance.collection('admin_meta').doc('clock');
      final sentAt = DateTime.now();
      await ref.set({'t': FieldValue.serverTimestamp()});
      final snap = await ref.get(const GetOptions(source: Source.server));
      final t = snap.data()?['t'];
      if (t is Timestamp) {
        final receivedAt = DateTime.now();
        // Use the middle of the round trip as the local moment the server stamped.
        final localMid = sentAt.add(receivedAt.difference(sentAt) ~/ 2);
        _offset = t.toDate().difference(localMid);
      }
    } catch (_) {
      // Keep the previous offset if the sync fails.
    }
  }
}