import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Shows whether a driver or passenger is currently banned from rides
/// (`rideBanUntil` in the future): the kind of ban, the time left and the end
/// date. Also flags accounts that already passed the cancellation / no-show
/// limit and are waiting for their ban to be applied. The admin can lift a ban.
class AdminBanCell extends StatefulWidget {
  /// 'drivers' or 'passengers'
  final String collection;
  final String id;
  final Map<String, dynamic> data;

  const AdminBanCell({super.key, required this.collection, required this.id, required this.data});

  /// Same numbers as the app's CancelBan.
  static const int strikeLimit = 3;
  static const int strikeBanDays = 5;

  static DateTime? banUntil(Map<String, dynamic> data) {
    final v = data['rideBanUntil'];
    if (v is! Timestamp) return null;
    final d = v.toDate();
    return d.isAfter(DateTime.now()) ? d : null;
  }

  /// True when the account has full groups of 3 cancellations / no-shows that
  /// have not been punished yet (the app applies the ban when the user opens it).
  static bool banPending(Map<String, dynamic> data) {
    final count = ((data['cancelCount'] ?? 0) as num).toInt();
    final handled = ((data['strikeTierBanned'] ?? 0) as num).toInt();
    return count ~/ strikeLimit > handled;
  }

  static String _label(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String _left(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d ${d.inHours % 24}h left';
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes % 60}m left';
    if (d.inMinutes >= 1) return '${d.inMinutes} min left';
    return 'less than 1 min left';
  }

  @override
  State<AdminBanCell> createState() => _AdminBanCellState();
}

class _AdminBanCellState extends State<AdminBanCell> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Keep the "time left" text fresh while the page stays open.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _unban() async {
    final data = widget.data;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lift this ban?'),
        content: Text('${data['fullName'] ?? 'This account'} will be able to use rides again right away.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Unban')),
        ],
      ),
    );
    if (ok != true) return;
    final count = ((data['cancelCount'] ?? 0) as num).toInt();
    await FirebaseFirestore.instance.collection(widget.collection).doc(widget.id).update({
      'rideBanUntil': FieldValue.delete(),
      // Mark the current strikes as handled so the app does not ban again at once.
      'strikeTierBanned': count ~/ AdminBanCell.strikeLimit,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ban lifted.')));
  }

  @override
  Widget build(BuildContext context) {
    final until = AdminBanCell.banUntil(widget.data);

    if (until == null) {
      if (AdminBanCell.banPending(widget.data)) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Text(
            'Over limit · ${AdminBanCell.strikeBanDays}-day ban applies when the user opens the app',
            style: TextStyle(color: Colors.orange.shade900, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        );
      }
      return const Text('-');
    }

    final left = until.difference(DateTime.now());
    // The short ban (after cancelling an accepted ride) is 5 minutes; anything
    // longer is the strike ban.
    final isLong = left.inMinutes > 10;
    final title = isLong
        ? '${AdminBanCell.strikeBanDays}-day ban (${AdminBanCell.strikeLimit} cancellations / no-shows)'
        : '5-minute ban (cancelled an accepted ride)';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              Text(
                '${AdminBanCell._left(left)} · until ${AdminBanCell._label(until)}',
                style: TextStyle(color: Colors.red.shade700, fontSize: 11),
              ),
            ],
          ),
        ),
        TextButton(onPressed: _unban, child: const Text('Unban')),
      ],
    );
  }
}