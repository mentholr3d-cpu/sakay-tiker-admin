import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Shows whether a driver or passenger is currently banned from rides
/// (`rideBanUntil` in the future) and lets the admin lift the ban.
class AdminBanCell extends StatelessWidget {
  /// 'drivers' or 'passengers'
  final String collection;
  final String id;
  final Map<String, dynamic> data;

  const AdminBanCell({super.key, required this.collection, required this.id, required this.data});

  static DateTime? banUntil(Map<String, dynamic> data) {
    final v = data['rideBanUntil'];
    if (v is! Timestamp) return null;
    final d = v.toDate();
    return d.isAfter(DateTime.now()) ? d : null;
  }

  static String _label(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, $hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  Future<void> _unban(BuildContext context) async {
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
    await FirebaseFirestore.instance.collection(collection).doc(id).update({
      'rideBanUntil': FieldValue.delete(),
    });
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ban lifted.')));
  }

  @override
  Widget build(BuildContext context) {
    final until = banUntil(data);
    if (until == null) return const Text('-');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.red.shade300),
          ),
          child: Text(
            'Banned until ${_label(until)}',
            style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(onPressed: () => _unban(context), child: const Text('Unban')),
      ],
    );
  }
}