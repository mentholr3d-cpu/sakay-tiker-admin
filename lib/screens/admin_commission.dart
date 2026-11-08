import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'commission_period.dart';
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

  // Every driver's commission records in one live listener (used for the summary and filters).
  final Stream<QuerySnapshot> _allRecordsStream =
      FirebaseFirestore.instance.collectionGroup('commission_records').snapshots();
  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  String _filter = 'all'; // all | balance | overdue | review

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _currentMonthKey() => CommissionPeriod.currentKey();

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
    final noteController = TextEditingController();
    const quick = ['Wrong amount', 'Receipt is blurry', 'Payment not received in GCash', 'Wrong reference number'];

    final note = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Reject Payment'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reject the payment submitted for ${CommissionPeriod.label(monthKey)}? '
                    'The driver will see your note and can send a new receipt.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final q in quick)
                        ActionChip(
                          label: Text(q, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setLocal(() => noteController.text = q),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    maxLength: 200,
                    decoration: const InputDecoration(
                      labelText: 'Note to the driver',
                      hintText: 'Tell the driver what to fix',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(dialogContext, noteController.text.trim()),
              child: const Text('Reject'),
            ),
          ],
        ),
      ),
    );
    if (note == null) return;

    final reason = note.isEmpty ? 'Please check the amount and receipt, then send your payment again.' : note;

    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .collection('commission_records')
        .doc(monthKey)
        .update({
      'paymentSubmitted': false,
      'paymentRejected': true,
      'rejectReason': reason,
      'rejectedAt': FieldValue.serverTimestamp(),
    });

    // Tell the driver (shows as a pop-up in the driver app).
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'recipientId': driverId,
        'recipientRole': 'driver',
        'title': 'Payment Not Confirmed',
        'message': 'Your commission payment for ${CommissionPeriod.label(monthKey)} was not confirmed. Reason: $reason '
            'Please open Commission and send a new receipt.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
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
          title: Text('Adjust balance - ${CommissionPeriod.label(monthKey)}'),
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
        'rejectReason': FieldValue.delete(),
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Driver Commission', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  AnimatedPress(
                    onTap: () => _editGcashSettings(context),
                    child: OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.settings_outlined, size: 18),
                      label: const Text('Set GCash Details'),
                    ),
                  ),
                ],
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
                    final key = CommissionPeriod.keyFor(d);
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

                      return StreamBuilder<QuerySnapshot>(
                        stream: _allRecordsStream,
                        builder: (context, recSnapshot) {
                          // driverId -> month -> record. Null means the shared listener is not
                          // available, so each card falls back to its own listener (no summary/filters).
                          Map<String, Map<String, Map<String, dynamic>>>? byDriver;
                          if (recSnapshot.hasData && !recSnapshot.hasError) {
                            byDriver = {};
                            for (final doc in recSnapshot.data!.docs) {
                              final did = doc.reference.parent.parent?.id;
                              if (did == null) continue;
                              byDriver.putIfAbsent(did, () => {})[doc.id] = doc.data() as Map<String, dynamic>;
                            }
                          } else if (!recSnapshot.hasError) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          // Per-driver summaries (only when the shared listener works).
                          final summaries = <String, _DriverSummary>{};
                          num totalEarned = 0, totalPaid = 0, totalBalance = 0;
                          var toReview = 0;
                          if (byDriver != null) {
                            for (final d in drivers) {
                              final sm = _summarize(byDriver[d.id] ?? const {}, rideSums[d.id] ?? const {}, currentMonth);
                              summaries[d.id] = sm;
                              totalEarned += sm.earned;
                              totalPaid += sm.paid;
                              totalBalance += sm.balance;
                              toReview += sm.submittedCount;
                            }
                          }

                          // Search + filter.
                          final q = _search.trim().toLowerCase();
                          final shown = drivers.where((d) {
                            final data = d.data() as Map<String, dynamic>;
                            if (q.isNotEmpty) {
                              final name = '${data['fullName'] ?? ''}'.toLowerCase();
                              final phone = '${data['phoneNumber'] ?? ''}'.toLowerCase();
                              if (!name.contains(q) && !phone.contains(q)) return false;
                            }
                            final sm = summaries[d.id];
                            if (sm != null) {
                              if (_filter == 'balance' && sm.balance <= 0) return false;
                              if (_filter == 'overdue' && !sm.overdue) return false;
                              if (_filter == 'review' && !sm.toVerify) return false;
                            }
                            return true;
                          }).toList();

                          // Drivers who need attention first.
                          if (byDriver != null) {
                            int rank(QueryDocumentSnapshot d) {
                              final sm = summaries[d.id]!;
                              if (sm.toVerify) return 0;
                              if (sm.overdue) return 1;
                              if (sm.balance > 0) return 2;
                              return 3;
                            }
                            shown.sort((a, b) => rank(a).compareTo(rank(b)));
                          }

                          return ListView(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            children: [
                              if (byDriver != null) ...[
                                _buildSummaryRow(totalEarned, totalPaid, totalBalance, toReview),
                                const SizedBox(height: 12),
                              ],
                              _buildToolbar(showFilters: byDriver != null),
                              const SizedBox(height: 12),
                              if (shown.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 40),
                                  child: _buildEmptyState('No drivers match'),
                                ),
                              for (final driverDoc in shown)
                                Builder(builder: (context) {
                                  final driverData = driverDoc.data() as Map<String, dynamic>;
                                  final isSuspended = driverData['accountStatus'] == 'suspended';
                                  return _DriverCommissionCard(
                                    key: ValueKey(driverDoc.id),
                                    driverId: driverDoc.id,
                                    driverData: driverData,
                                    isSuspended: isSuspended,
                                    currentMonth: currentMonth,
                                    rideMonths: rideSums[driverDoc.id] ?? const {},
                                    records: byDriver == null ? null : (byDriver[driverDoc.id] ?? const {}),
                                    onMarkPaid: (monthKey, balance, earned) =>
                                        _markAsPaid(context, driverDoc.id, monthKey, balance, earned),
                                    onRejectPayment: (monthKey) => _rejectPayment(context, driverDoc.id, monthKey),
                                    onToggleSuspend: () => _toggleSuspend(context, driverDoc.id, !isSuspended),
                                  );
                                }),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(num earned, num paid, num balance, int toReview) {
    Widget card(String label, String value, IconData icon, Color color) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    const SizedBox(height: 2),
                    Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  ],
                ),
              ),
            ],
          ),
        );

    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 760 ? 4 : 2;
      final w = (c.maxWidth - 10 * (cols - 1)) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          SizedBox(width: w, child: card('Total commission', '₱$earned', Icons.account_balance_wallet_outlined, Colors.green.shade800)),
          SizedBox(width: w, child: card('Total paid', '₱$paid', Icons.check_circle_outline, Colors.teal.shade700)),
          SizedBox(width: w, child: card('Unpaid balance', '₱$balance', Icons.pending_actions_outlined, balance > 0 ? Colors.red.shade700 : Colors.green.shade700)),
          SizedBox(width: w, child: card('Receipts to review', '$toReview', Icons.receipt_long_outlined, Colors.indigo.shade700)),
        ],
      );
    });
  }

  Widget _buildToolbar({required bool showFilters}) {
    Widget chip(String key, String label) => ChoiceChip(
          label: Text(label),
          selected: _filter == key,
          onSelected: (_) => setState(() => _filter = key),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(
            hintText: 'Search driver name or phone',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            suffixIcon: _search.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _searchController.clear();
                      _search = '';
                    }),
                  ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        if (showFilters) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              chip('all', 'All'),
              chip('balance', 'With balance'),
              chip('overdue', 'Overdue'),
              chip('review', 'Receipt to review'),
            ],
          ),
        ],
      ],
    );
  }
}

/// Totals for one driver, combining the saved records with the sum of completed rides.
class _DriverSummary {
  final Map<String, Map<String, num>> months; // month -> {earned, paid}
  final Map<String, Map<String, dynamic>> records;
  final List<String> keys; // newest first
  num earned = 0;
  num paid = 0;
  num balance = 0;
  bool overdue = false;
  bool toVerify = false;
  int submittedCount = 0;

  _DriverSummary(this.months, this.records, this.keys);
}

_DriverSummary _summarize(
  Map<String, Map<String, dynamic>> records,
  Map<String, num> rideMonths,
  String currentMonth,
) {
  final months = <String, Map<String, num>>{};
  records.forEach((id, c) {
    months[id] = {
      'earned': (c['totalEarned'] ?? 0) as num,
      'paid': (c['amountPaid'] ?? 0) as num,
    };
  });

  // Use whichever is higher: the saved record or the sum of completed rides.
  rideMonths.forEach((month, rideTotal) {
    final entry = months.putIfAbsent(month, () => {'earned': 0, 'paid': 0});
    if (rideTotal > entry['earned']!) entry['earned'] = rideTotal;
  });

  final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
  final s = _DriverSummary(months, records, keys);
  months.forEach((month, v) {
    s.earned += v['earned']!;
    s.paid += v['paid']!;
    final b = v['earned']! - v['paid']!;
    if (b > 0) {
      s.balance += b;
      if (month != currentMonth) s.overdue = true;
    }
  });
  for (final r in records.values) {
    if (r['paymentSubmitted'] == true && r['status'] != 'paid') {
      s.toVerify = true;
      s.submittedCount++;
    }
  }
  return s;
}

/// One driver's commission summary: totals across ALL periods (including overdue
/// ones), plus a table per period with receipt review.
class _DriverCommissionCard extends StatefulWidget {
  final String driverId;
  final Map<String, dynamic> driverData;
  final bool isSuspended;
  final String currentMonth;
  final Map<String, num> rideMonths;
  // Records handed in by the page (month -> record). Null = load them here.
  final Map<String, Map<String, dynamic>>? records;
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
    required this.records,
    required this.onMarkPaid,
    required this.onRejectPayment,
    required this.onToggleSuspend,
  });

  @override
  State<_DriverCommissionCard> createState() => _DriverCommissionCardState();
}

class _DriverCommissionCardState extends State<_DriverCommissionCard> {
  // Only created (lazily) when the page did not hand in the records.
  late final Stream<QuerySnapshot> _recordsStream = FirebaseFirestore.instance
      .collection('drivers')
      .doc(widget.driverId)
      .collection('commission_records')
      .snapshots();

  bool _showHistory = false;

  @override
  Widget build(BuildContext context) {
    final handed = widget.records;
    if (handed != null) return _buildCard(context, handed);

    return StreamBuilder<QuerySnapshot>(
      stream: _recordsStream,
      builder: (context, snap) {
        final records = <String, Map<String, dynamic>>{};
        for (final d in snap.data?.docs ?? <QueryDocumentSnapshot>[]) {
          records[d.id] = d.data() as Map<String, dynamic>;
        }
        return _buildCard(context, records);
      },
    );
  }

  Widget _chip(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
      );

  Widget _tile(String label, String value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
              const SizedBox(height: 2),
              Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ),
      );

  Widget _smallButton(String label, VoidCallback onTap, {bool filled = false, Color? color}) {
    final c = color ?? Colors.green.shade800;
    return AnimatedPress(
      onTap: onTap,
      child: filled
          ? ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: () {},
              child: Text(label),
            )
          : OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: c,
                side: BorderSide(color: c.withValues(alpha: 0.6)),
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              onPressed: () {},
              child: Text(label),
            ),
    );
  }

  Widget _buildCard(BuildContext context, Map<String, Map<String, dynamic>> records) {
    final s = _summarize(records, widget.rideMonths, widget.currentMonth);
    final dd = widget.driverData;
    final name = '${dd['fullName'] ?? 'Unknown'}';
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final current = records[widget.currentMonth];
    final currentPaid = current?['status'] == 'paid';
    final isEarly = current?['isEarlyPayment'] == true;

    // Periods that need attention stay visible; settled older ones go under "history".
    final visible = <String>[];
    final history = <String>[];
    for (final k in s.keys) {
      final earned = s.months[k]!['earned']!;
      final paid = s.months[k]!['paid']!;
      final rec = records[k];
      final needs = k == widget.currentMonth ||
          earned - paid > 0 ||
          (rec?['paymentSubmitted'] == true && rec?['status'] != 'paid') ||
          rec?['paymentRejected'] == true;
      (needs ? visible : history).add(k);
    }

    Widget settled = _chip('SETTLED', Colors.green.shade100, Colors.green.shade800);
    if (s.overdue) {
      settled = _chip('OVERDUE', Colors.red.shade100, Colors.red.shade800);
    } else if (s.balance > 0) {
      settled = _chip('HAS BALANCE', Colors.orange.shade100, Colors.orange.shade900);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      color: widget.isSuspended ? Colors.red.shade50 : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: widget.isSuspended ? Colors.red.shade200 : Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.green.shade100,
                  child: Text(initial, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${dd['phoneNumber'] ?? '-'}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (widget.isSuspended) _chip('SUSPENDED', Colors.red, Colors.white),
                          settled,
                          if (s.toVerify) _chip('RECEIPT TO REVIEW', Colors.indigo.shade100, Colors.indigo.shade800),
                          if (currentPaid && isEarly) _chip('EARLY PAYMENT', Colors.blue.shade100, Colors.blue.shade800),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedPress(
                  onTap: widget.onToggleSuspend,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: widget.isSuspended ? Colors.green.shade700 : Colors.red.shade700,
                      side: BorderSide(color: (widget.isSuspended ? Colors.green : Colors.red).withValues(alpha: 0.5)),
                    ),
                    onPressed: () {},
                    icon: Icon(widget.isSuspended ? Icons.check_circle_outline : Icons.block, size: 18),
                    label: Text(widget.isSuspended ? 'Reactivate' : 'Suspend'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Totals
            Row(
              children: [
                _tile('Earned', '₱${s.earned}', Colors.green.shade800),
                const SizedBox(width: 8),
                _tile('Paid', '₱${s.paid}', Colors.teal.shade700),
                const SizedBox(width: 8),
                _tile('Balance', '₱${s.balance}', s.balance > 0 ? Colors.red.shade700 : Colors.green.shade700),
              ],
            ),
            const SizedBox(height: 14),

            // Periods
            if (s.keys.isEmpty)
              Text('No commission yet.', style: TextStyle(color: Colors.grey.shade600))
            else
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: Colors.grey.shade300),
                      _periodRow(context, visible[i], s, records),
                    ],
                    if (_showHistory)
                      for (final k in history) ...[
                        Divider(height: 1, color: Colors.grey.shade300),
                        _periodRow(context, k, s, records),
                      ],
                  ],
                ),
              ),
            if (history.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showHistory = !_showHistory),
                  icon: Icon(_showHistory ? Icons.expand_less : Icons.expand_more, size: 18),
                  label: Text(_showHistory ? 'Hide history' : 'Show history (${history.length})'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _periodRow(
    BuildContext context,
    String month,
    _DriverSummary s,
    Map<String, Map<String, dynamic>> records,
  ) {
    final earned = s.months[month]!['earned']!;
    final paid = s.months[month]!['paid']!;
    final balance = earned - paid;
    final isCurrent = month == widget.currentMonth;
    final rec = records[month];
    final submitted = rec?['paymentSubmitted'] == true && rec?['status'] != 'paid';
    final rejected = rec?['paymentRejected'] == true && !submitted;
    final receiptUrl = rec?['receiptUrl'];
    final pretty = CommissionPeriod.label(month);

    Widget status;
    if (submitted) {
      status = _chip('TO REVIEW', Colors.indigo.shade100, Colors.indigo.shade800);
    } else if (earned > 0 && balance <= 0) {
      status = _chip('PAID', Colors.green.shade100, Colors.green.shade800);
    } else if (balance > 0 && !isCurrent) {
      status = _chip('OVERDUE', Colors.red.shade100, Colors.red.shade800);
    } else if (balance > 0) {
      status = _chip('ONGOING', Colors.orange.shade100, Colors.orange.shade900);
    } else {
      status = _chip('NO EARNINGS', Colors.grey.shade200, Colors.grey.shade700);
    }

    final labelWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(pretty, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
        if (isCurrent)
          Text('This ${CommissionPeriod.name(month)}', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        if (!submitted && balance > 0) _smallButton('Mark Paid', () => widget.onMarkPaid(month, balance, earned), filled: true),
        if (!submitted && balance <= 0 && earned > 0) _smallButton('Adjust', () => widget.onMarkPaid(month, balance, earned)),
        if (!submitted && balance > 0 && paid > 0) _smallButton('Adjust', () => widget.onMarkPaid(month, balance, earned)),
        if (!submitted && receiptUrl != null)
          TextButton.icon(
            style: TextButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 8)),
            onPressed: () => showDialog(
              context: context,
              builder: (_) => PhotoDialog(url: '$receiptUrl', title: 'Receipt - $pretty'),
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 16),
            label: const Text('View receipt', style: TextStyle(fontSize: 12.5)),
          ),
      ],
    );

    Widget money(String text, {Color? color, bool bold = false}) => Text(
          text,
          style: TextStyle(fontSize: 13.5, color: color, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
        );

    final balanceColor = balance > 0 ? Colors.red.shade700 : Colors.green.shade700;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 620) {
              return Row(
                children: [
                  Expanded(flex: 4, child: labelWidget),
                  Expanded(flex: 2, child: money('₱$earned')),
                  Expanded(flex: 2, child: money('₱$paid')),
                  Expanded(flex: 2, child: money('₱${balance > 0 ? balance : 0}', color: balanceColor, bold: true)),
                  SizedBox(width: 100, child: Align(alignment: Alignment.centerLeft, child: status)),
                  const SizedBox(width: 8),
                  Expanded(flex: 4, child: actions),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Expanded(child: labelWidget), status]),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  children: [
                    money('Earned ₱$earned'),
                    money('Paid ₱$paid'),
                    money('Balance ₱${balance > 0 ? balance : 0}', color: balanceColor, bold: true),
                  ],
                ),
                const SizedBox(height: 8),
                actions,
              ],
            );
          }),
          if (submitted)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.indigo.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (receiptUrl != null)
                    GestureDetector(
                      onTap: () => showDialog(
                        context: context,
                        builder: (_) => PhotoDialog(url: '$receiptUrl', title: 'Receipt - $pretty'),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '$receiptUrl',
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 64,
                            height: 64,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.receipt_long_outlined, color: Colors.grey),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.receipt_long_outlined, color: Colors.grey),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Receipt submitted', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                        const SizedBox(height: 2),
                        Text(
                          'Driver says: ₱${rec?['submittedAmount'] ?? balance}'
                          '${rec?['gcashReference'] != null ? '  •  Ref: ${rec!['gcashReference']}' : ''}',
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          'Check your GCash first, then approve or reject.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _smallButton('Approve', () => widget.onMarkPaid(month, balance, earned), filled: true),
                            _smallButton('Reject', () => widget.onRejectPayment(month), color: Colors.red.shade700),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (rejected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.red.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Last receipt rejected${rec?['rejectReason'] != null ? ': ${rec!['rejectReason']}' : ''}',
                      style: TextStyle(fontSize: 12.5, color: Colors.red.shade800),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}