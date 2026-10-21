import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import '../widgets/animated_press.dart';
import '../widgets/photo_viewer.dart';

class AdminCommissionScreen extends StatefulWidget {
  const AdminCommissionScreen({super.key});

  @override
  State<AdminCommissionScreen> createState() => _AdminCommissionScreenState();
}

class _AdminCommissionScreenState extends State<AdminCommissionScreen> {
  // Created once so the page does not restart its live listeners on every rebuild.
  final Stream<QuerySnapshot> _driversStream =
      FirebaseFirestore.instance.collection('drivers').snapshots();
  final Stream<QuerySnapshot> _completedRidesStream = FirebaseFirestore.instance
      .collection('rides')
      .where('status', isEqualTo: 'completed')
      .snapshots();

  String _currentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🛺', style: TextStyle(fontSize: 30)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _editGcashSettings(BuildContext context) async {
    final settingsDoc = await FirebaseFirestore.instance.collection('settings').doc('payment').get();
    final currentData = settingsDoc.data() ?? {};

    final numberController = TextEditingController(text: currentData['gcashNumber'] ?? '');
    final nameController = TextEditingController(text: currentData['gcashName'] ?? '');
    Uint8List? qrBytes;
    final cloudinary = CloudinaryPublic('kdjcuv7w', 'sakay_tiker_unsigned', cache: false);

    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Admin GCash Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: numberController,
                    decoration: const InputDecoration(labelText: 'GCash Number'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Account Name'),
                  ),
                  const SizedBox(height: 12),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('QR Code (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                      if (picked != null) {
                        final bytes = await picked.readAsBytes();
                        setDialogState(() => qrBytes = bytes);
                      }
                    },
                    child: Container(
                      height: 160,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: qrBytes == null
                          ? (currentData['gcashQrUrl'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    currentData['gcashQrUrl'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => const Center(
                                      child: Icon(Icons.broken_image_outlined, color: Colors.grey),
                                    ),
                                  ),
                                )
                              : const Center(child: Icon(Icons.qr_code, size: 40, color: Colors.grey)))
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(qrBytes!, fit: BoxFit.cover),
                            ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Upload a screenshot of your GCash QR code', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    if (!context.mounted) return;

    final reallySave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Changes?'),
        content: const Text('This will update the GCash details shown to all drivers. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (reallySave != true) return;

    String? qrUrl = currentData['gcashQrUrl'];
    if (qrBytes != null) {
      try {
        final response = await cloudinary
            .uploadFile(
              CloudinaryFile.fromBytesData(
                qrBytes!,
                identifier: 'gcash_qr_${DateTime.now().millisecondsSinceEpoch}',
                resourceType: CloudinaryResourceType.Image,
              ),
            )
            .timeout(const Duration(seconds: 30));
        qrUrl = response.secureUrl;
      } catch (e) {
        debugPrint('QR upload error: $e');
      }
    }

    await FirebaseFirestore.instance.collection('settings').doc('payment').set({
      'gcashNumber': numberController.text.trim(),
      'gcashName': nameController.text.trim(),
      'gcashQrUrl': qrUrl,
    });
  }

  Future<void> _rejectPayment(BuildContext context, String driverId, String monthKey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Payment'),
        content: Text('Reject the submitted payment for $monthKey? The driver will see that it was not confirmed and can pay again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .collection('commission_records')
        .doc(monthKey)
        .update({'paymentSubmitted': false, 'paymentRejected': true});
  }

  /// Record a payment (reduce the balance) or correct one (add it back).
  /// A partial amount leaves the rest as balance and the month as "partial".
  Future<void> _markAsPaid(
      BuildContext context, String driverId, String monthKey, num balance, num earned) async {
    final ref = FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .collection('commission_records')
        .doc(monthKey);

    final snap = await ref.get();
    if (!context.mounted) return;
    final data = snap.data() ?? {};
    final recorded = (data['totalEarned'] ?? 0) as num;
    final total = recorded > earned ? recorded : earned;
    final alreadyPaid = (data['amountPaid'] ?? 0) as num;
    final submittedAmount = data['paymentSubmitted'] == true ? (data['submittedAmount'] as num?) : null;
    final suggested = (submittedAmount != null && submittedAmount > 0)
        ? submittedAmount
        : (total - alreadyPaid > 0 ? total - alreadyPaid : 0);

    final amountController = TextEditingController(text: suggested.toString());
    bool reduce = true;
    String? error;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Adjust balance - $monthKey'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Commission: ₱$total\nPaid so far: ₱$alreadyPaid\nBalance: ₱${total - alreadyPaid > 0 ? total - alreadyPaid : 0}'),
                if (submittedAmount != null) ...[
                  const SizedBox(height: 8),
                  Text('Driver says they paid: ₱$submittedAmount. Check your GCash first.',
                      style: const TextStyle(color: Colors.indigo, fontSize: 12.5)),
                ],
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Minus (payment)')),
                    ButtonSegment(value: false, label: Text('Add back')),
                  ],
                  selected: {reduce},
                  onSelectionChanged: (v) => setLocal(() => reduce = v.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: reduce ? 'Amount received (₱)' : 'Amount to add back to balance (₱)',
                    errorText: error,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reduce
                      ? 'The amount is subtracted from the balance. If something is left, the month stays "partial" and the driver sees the new balance.'
                      : 'Use this to fix a mistake. The amount is added back to the balance.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final value = num.tryParse(amountController.text.trim());
                if (value == null || value <= 0) {
                  setLocal(() => error = 'Enter an amount above 0');
                  return;
                }
                Navigator.pop(dialogContext, {'amount': value, 'reduce': reduce});
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    final amount = result['amount'] as num;
    final isReduce = result['reduce'] as bool;
    num newPaid = isReduce ? alreadyPaid + amount : alreadyPaid - amount;
    if (newPaid > total) newPaid = total;
    if (newPaid < 0) newPaid = 0;
    final newBalance = total - newPaid;

    await ref.set(
      {
        'month': monthKey,
        'totalEarned': total,
        'amountPaid': newPaid,
        'status': newBalance <= 0 ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid'),
        'paymentSubmitted': false,
        'paymentRejected': false,
        'verifiedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (newBalance <= 0) {
      await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
        'accountStatus': 'active',
      });
    }
  }

  Future<void> _toggleSuspend(BuildContext context, String driverId, bool suspend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'Suspend Driver' : 'Reactivate Driver'),
        content: Text(
          suspend
              ? 'This driver will be blocked from logging in until reactivated. Continue?'
              : 'This driver will be able to log in again. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: suspend ? Colors.red : Colors.green,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(suspend ? 'Suspend' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
      'accountStatus': suspend ? 'suspended' : 'active',
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentMonth = _currentMonthKey();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Align(
            alignment: Alignment.centerRight,
            child: AnimatedPress(
              onTap: () => _editGcashSettings(context),
              child: OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Set GCash Details'),
              ),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _completedRidesStream,
            builder: (context, ridesSnapshot) {
              // What every driver has earned for the admin, straight from completed rides
              // (driverId -> month -> commission). This works even if a driver's monthly
              // commission record is missing or out of date.
              final rideSums = <String, Map<String, num>>{};
              for (final ride in ridesSnapshot.data?.docs ?? <QueryDocumentSnapshot>[]) {
                final r = ride.data() as Map<String, dynamic>;
                final driverId = r['driverId'];
                final completedAt = r['completedAt'];
                if (driverId is! String || completedAt is! Timestamp) continue;
                final d = completedAt.toDate();
                final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
                final months = rideSums.putIfAbsent(driverId, () => {});
                months[key] = (months[key] ?? 0) + ((r['commissionAmount'] ?? 0) as num);
              }

              return StreamBuilder<QuerySnapshot>(
                stream: _driversStream,
                builder: (context, driverSnapshot) {
                  if (driverSnapshot.hasError) {
                    return Center(child: Text('Could not load drivers: ${driverSnapshot.error}'));
                  }
                  if (!driverSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (driverSnapshot.data!.docs.isEmpty) {
                    return _buildEmptyState('No drivers found');
                  }

                  final drivers = driverSnapshot.data!.docs
                      .where((d) => (d.data() as Map<String, dynamic>)['status'] == 'approved')
                      .toList();

                  if (drivers.isEmpty) return _buildEmptyState('No approved drivers yet');

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: drivers.length,
                    itemBuilder: (context, index) {
                      final driverDoc = drivers[index];
                      final driverData = driverDoc.data() as Map<String, dynamic>;
                      final isSuspended = driverData['accountStatus'] == 'suspended';

                      return _DriverCommissionCard(
                        key: ValueKey(driverDoc.id),
                        driverId: driverDoc.id,
                        driverData: driverData,
                        isSuspended: isSuspended,
                        currentMonth: currentMonth,
                        rideMonths: rideSums[driverDoc.id] ?? const {},
                        onMarkPaid: (monthKey, balance, earned) =>
                            _markAsPaid(context, driverDoc.id, monthKey, balance, earned),
                        onRejectPayment: (monthKey) => _rejectPayment(context, driverDoc.id, monthKey),
                        onToggleSuspend: () => _toggleSuspend(context, driverDoc.id, !isSuspended),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One driver's commission summary: total commission, total paid and total balance
/// across ALL months (including overdue ones), plus a breakdown per month.
class _DriverCommissionCard extends StatefulWidget {
  final String driverId;
  final Map<String, dynamic> driverData;
  final bool isSuspended;
  final String currentMonth;
  final Map<String, num> rideMonths;
  final void Function(String monthKey, num balance, num earned) onMarkPaid;
  final void Function(String monthKey) onRejectPayment;
  final VoidCallback onToggleSuspend;

  const _DriverCommissionCard({
    super.key,
    required this.driverId,
    required this.driverData,
    required this.isSuspended,
    required this.currentMonth,
    required this.rideMonths,
    required this.onMarkPaid,
    required this.onRejectPayment,
    required this.onToggleSuspend,
  });

  @override
  State<_DriverCommissionCard> createState() => _DriverCommissionCardState();
}

class _DriverCommissionCardState extends State<_DriverCommissionCard> {
  late final Stream<QuerySnapshot> _recordsStream = FirebaseFirestore.instance
      .collection('drivers')
      .doc(widget.driverId)
      .collection('commission_records')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    final driverData = widget.driverData;

    return StreamBuilder<QuerySnapshot>(
      stream: _recordsStream,
      builder: (context, commSnapshot) {
        // month -> {earned, paid}
        final months = <String, Map<String, num>>{};
        final records = <String, Map<String, dynamic>>{};

        for (final record in commSnapshot.data?.docs ?? <QueryDocumentSnapshot>[]) {
          final c = record.data() as Map<String, dynamic>;
          records[record.id] = c;
          months[record.id] = {
            'earned': (c['totalEarned'] ?? 0) as num,
            'paid': (c['amountPaid'] ?? 0) as num,
          };
        }

        // Use whichever is higher: the saved record or the sum of completed rides.
        widget.rideMonths.forEach((month, rideTotal) {
          final entry = months.putIfAbsent(month, () => {'earned': 0, 'paid': 0});
          if (rideTotal > entry['earned']!) entry['earned'] = rideTotal;
        });

        num totalEarned = 0;
        num totalPaid = 0;
        num totalBalance = 0;
        months.forEach((month, v) {
          totalEarned += v['earned']!;
          totalPaid += v['paid']!;
          final b = v['earned']! - v['paid']!;
          if (b > 0) totalBalance += b;
        });

        final monthKeys = months.keys.toList()..sort((a, b) => b.compareTo(a));
        final current = records[widget.currentMonth];
        final gcashRef = current?['gcashReference'];
        final receiptUrl = current?['receiptUrl'];
        final isEarlyPayment = current?['isEarlyPayment'] == true;
        final currentPaid = current?['status'] == 'paid';
        final anySubmitted = records.values.any((r) => r['paymentSubmitted'] == true && r['status'] != 'paid');

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: widget.isSuspended ? Colors.red.shade50 : null,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${driverData['fullName'] ?? 'Unknown'}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          if (widget.isSuspended)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'SUSPENDED',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (anySubmitted)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'PAYMENT TO VERIFY',
                                style: TextStyle(color: Colors.indigo.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (currentPaid && isEarlyPayment)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'EARLY PAYMENT',
                                style: TextStyle(color: Colors.blue.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      Text('${driverData['phoneNumber'] ?? '-'}'),
                      const SizedBox(height: 4),
                      Text('Total commission: ₱$totalEarned  •  Total paid: ₱$totalPaid'),
                      Text(
                        'Total balance: ₱$totalBalance',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: totalBalance > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                      if (monthKeys.isNotEmpty) const SizedBox(height: 6),
                      for (final month in monthKeys)
                        Builder(builder: (context) {
                          final earned = months[month]!['earned']!;
                          final paid = months[month]!['paid']!;
                          final balance = earned - paid;
                          final isCurrent = month == widget.currentMonth;
                          final rec = records[month];
                          final submitted = rec?['paymentSubmitted'] == true && rec?['status'] != 'paid';
                          final label = isCurrent
                              ? '$month (this month)'
                              : (balance > 0 ? '$month (OVERDUE)' : month);

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  '$label: ₱$earned earned, ₱$paid paid, ₱${balance > 0 ? balance : 0} balance',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: balance > 0 ? FontWeight.bold : FontWeight.normal,
                                    color: balance > 0 && !isCurrent ? Colors.red : null,
                                  ),
                                ),
                                if (submitted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.indigo.shade100,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'SUBMITTED',
                                      style: TextStyle(color: Colors.indigo.shade800, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                if (submitted && rec?['receiptUrl'] != null)
                                  GestureDetector(
                                    onTap: () => showDialog(
                                      context: context,
                                      builder: (_) => PhotoDialog(url: '${rec!['receiptUrl']}', title: 'Receipt $month'),
                                    ),
                                    child: const Text(
                                      '🧾 Receipt',
                                      style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                if (submitted && rec?['gcashReference'] != null)
                                  Text('Ref: ${rec!['gcashReference']}',
                                      style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
                                if (balance > 0)
                                  AnimatedPress(
                                    onTap: () => widget.onMarkPaid(month, balance, earned),
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 28),
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                      ),
                                      onPressed: () {},
                                      child: Text(submitted ? 'Confirm / Adjust' : 'Mark Paid', style: const TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                if (balance <= 0 && earned > 0)
                                  AnimatedPress(
                                    onTap: () => widget.onMarkPaid(month, balance, earned),
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        minimumSize: const Size(0, 28),
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                      onPressed: () {},
                                      child: const Text('Adjust', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                                if (submitted)
                                  AnimatedPress(
                                    onTap: () => widget.onRejectPayment(month),
                                    child: TextButton(
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        minimumSize: const Size(0, 28),
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                      onPressed: () {},
                                      child: const Text('Reject', style: TextStyle(fontSize: 12)),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }),
                      if (gcashRef != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'GCash Ref: $gcashRef',
                            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                          ),
                        ),
                      if (receiptUrl != null)
                        GestureDetector(
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => PhotoDialog(url: '$receiptUrl', title: 'Receipt'),
                          ),
                          child: const Text(
                            '🧾 View receipt',
                            style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedPress(
                  onTap: widget.onToggleSuspend,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: widget.isSuspended ? Colors.green : Colors.red,
                    ),
                    onPressed: () {},
                    child: Text(widget.isSuspended ? 'Reactivate' : 'Suspend'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}