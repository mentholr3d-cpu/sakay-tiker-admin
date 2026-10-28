import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'admin_commission.dart';
import 'admin_feedback.dart';
import 'admin_analytics.dart';
import 'admin_passengers.dart';
import 'admin_login.dart';
import 'server_clock.dart';
import '../widgets/version_label.dart';
import 'dart:async';
import '../widgets/mountain_silhouette.dart';
import '../widgets/animated_press.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/sms_service.dart';
import 'admin_account_dialogs.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  int _driversSubTab = 0;
  int _ridesSubTab = 0;

  String _driverSearch = '';
  String _driverStatusFilter = 'all'; // all, pending, approved, rejected
  String _rideHistorySearch = '';

  // Created once so typing in a search box never restarts the live listeners.
  final Stream<QuerySnapshot> _driversStream =
      FirebaseFirestore.instance.collection('drivers').snapshots();
  final Stream<QuerySnapshot> _completedRidesStream = FirebaseFirestore.instance
      .collection('rides')
      .where('status', isEqualTo: 'completed')
      .snapshots();

  // Live streams used only for the red number badges.
  final Stream<QuerySnapshot> _pendingDriversStream = FirebaseFirestore.instance
      .collection('drivers')
      .where('status', isEqualTo: 'pending')
      .snapshots();
  final Stream<QuerySnapshot> _pendingPaymentsStream = FirebaseFirestore.instance
      .collection('drivers')
      .where('commissionPaymentPending', isEqualTo: true)
      .snapshots();
  final Stream<QuerySnapshot> _ongoingRidesStream = FirebaseFirestore.instance
      .collection('rides')
      .where('status', whereIn: ['pending', 'negotiating', 'accepted'])
      .snapshots();
  final Stream<QuerySnapshot> _rideFeedbackStream =
      FirebaseFirestore.instance.collection('ride_feedback').snapshots();
  final Stream<QuerySnapshot> _appFeedbackStream =
      FirebaseFirestore.instance.collection('app_feedback').snapshots();

  // When the admin last looked at the Feedback page. Newer feedback counts as "new".
  DateTime? _feedbackLastSeen;

  final _driverSearchController = TextEditingController();
  final _rideHistorySearchController = TextEditingController();

  final List<String> _pages = [
    'Overview',
    'Drivers',
    'Passengers',
    'Rides',
    'Feedback',
  ];

  static const List<Map<String, dynamic>> _navItems = [
    {'icon': Icons.dashboard, 'label': 'Overview'},
    {'icon': Icons.people, 'label': 'Drivers'},
    {'icon': Icons.person_pin, 'label': 'Passengers'},
    {'icon': Icons.directions_car, 'label': 'Rides'},
    {'icon': Icons.feedback, 'label': 'Feedback'},
  ];

  static const List<String> _rejectionReasons = [
    'Incomplete or unclear license photo',
    'Incomplete or unclear tricycle photo',
    "Invalid or expired driver's license",
    'MTOP or plate number could not be verified',
    'Information does not match submitted documents',
    'Other (see notes)',
  ];

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    ServerClock.sync();
    _loadFeedbackLastSeen();
    // Re-sync the clock every 5 minutes and refresh the page every 30 seconds
    // so online/offline status stays current without pressing refresh.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (t.tick % 10 == 0) ServerClock.sync();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _driverSearchController.dispose();
    _rideHistorySearchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeedbackLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('adminFeedbackLastSeen');
    if (!mounted) return;
    if (ms == null) {
      // First time on this device: start from zero instead of flagging old feedback.
      setState(_markFeedbackSeen);
    } else {
      setState(() => _feedbackLastSeen = DateTime.fromMillisecondsSinceEpoch(ms));
    }
  }

  void _markFeedbackSeen() {
    final now = ServerClock.now();
    _feedbackLastSeen = now;
    SharedPreferences.getInstance()
        .then((p) => p.setInt('adminFeedbackLastSeen', now.millisecondsSinceEpoch));
  }

  // Call inside setState. Feedback counts as seen when you open or leave that page.
  void _selectPage(int index) {
    if (_selectedIndex == 4 || index == 4) _markFeedbackSeen();
    _selectedIndex = index;
  }

  // Wraps the screen with the live counts used by all the red badges.
  Widget _withCounts(Widget Function(_Counts counts) builder) {
    return StreamBuilder<QuerySnapshot>(
      stream: _pendingDriversStream,
      builder: (context, pendingSnap) => StreamBuilder<QuerySnapshot>(
        stream: _pendingPaymentsStream,
        builder: (context, paySnap) => StreamBuilder<QuerySnapshot>(
          stream: _ongoingRidesStream,
          builder: (context, ongoingSnap) => StreamBuilder<QuerySnapshot>(
            stream: _rideFeedbackStream,
            builder: (context, rideFbSnap) => StreamBuilder<QuerySnapshot>(
              stream: _appFeedbackStream,
              builder: (context, appFbSnap) {
                int ongoing = 0;
                for (final d in ongoingSnap.data?.docs ?? <QueryDocumentSnapshot>[]) {
                  final m = d.data() as Map<String, dynamic>;
                  final created = m['createdAt'];
                  // Same rule as the Ongoing list: hide requests nobody accepted in 15 minutes.
                  if (m['status'] == 'pending' &&
                      created is Timestamp &&
                      DateTime.now().difference(created.toDate()).inMinutes >= 15) {
                    continue;
                  }
                  ongoing++;
                }

                int newFeedback = 0;
                final seen = _feedbackLastSeen;
                if (seen != null && _selectedIndex != 4) {
                  for (final snap in [rideFbSnap, appFbSnap]) {
                    for (final d in snap.data?.docs ?? <QueryDocumentSnapshot>[]) {
                      final t = (d.data() as Map<String, dynamic>)['createdAt'];
                      if (t is Timestamp && t.toDate().isAfter(seen)) newFeedback++;
                    }
                  }
                }

                return builder(_Counts(
                  pendingDrivers: pendingSnap.data?.docs.length ?? 0,
                  pendingPayments: paySnap.data?.docs.length ?? 0,
                  ongoingRides: ongoing,
                  newFeedback: newFeedback,
                ));
              },
            ),
          ),
        ),
      ),
    );
  }

  // A tab label with a red number next to it when count > 0.
  Widget _tabLabel(String text, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (count > 0) ...[
          const SizedBox(width: 6),
          _CountBadge(count: count),
        ],
      ],
    );
  }

  void _navigateTo(int pageIndex, {int? driversSubTab, int? ridesSubTab}) {
    setState(() {
      _selectPage(pageIndex);
      if (driversSubTab != null) _driversSubTab = driversSubTab;
      if (ridesSubTab != null) _ridesSubTab = ridesSubTab;
    });
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

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log Out?'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('adminLoggedIn', false);
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AdminLoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _updateDriverStatus(String driverId, String newStatus) async {
    await FirebaseFirestore.instance
        .collection('drivers')
        .doc(driverId)
        .update({'status': newStatus});

    if (newStatus == 'approved') {
      await _notifyDriver(
        driverId,
        'Sakay Tiker: Your driver application has been APPROVED. You can now log in and start accepting rides.',
      );
    }
  }

  /// Texts the driver through the SMS Worker. If it cannot be sent the admin gets a button to send it by hand.
  Future<void> _notifyDriver(String driverId, String message) async {
    String? phone;
    try {
      final doc = await FirebaseFirestore.instance.collection('drivers').doc(driverId).get();
      phone = doc.data()?['phoneNumber']?.toString();
    } catch (_) {}

    final sent = await SmsService.notifyDriver(driverId);
    if (!mounted) return;

    final number = phone;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: sent ? 4 : 10),
        content: Text(sent
            ? 'Saved. The driver was notified by SMS.'
            : 'Saved, but the SMS was not sent. You can text the driver yourself.'),
        action: (!sent && number != null && number.isNotEmpty)
            ? SnackBarAction(
                label: 'Text driver',
                onPressed: () => launchUrl(
                  Uri(
                    scheme: 'sms',
                    path: SmsService.formatPhone(number),
                    queryParameters: {'body': message},
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Future<void> _showRejectDialog(BuildContext context, String driverId) async {
    String? selectedReason;
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Reject Application'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select a reason for rejecting this application:'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: _rejectionReasons
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (value) => setDialogState(() => selectedReason = value),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Additional notes (optional)',
                      hintText: 'e.g., which detail needs fixing',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: selectedReason == null ? null : () => Navigator.pop(context, true),
                child: const Text('Reject'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selectedReason == null) return;

    final notes = notesController.text.trim();
    final fullReason = notes.isEmpty ? selectedReason! : '$selectedReason — $notes';

    await FirebaseFirestore.instance.collection('drivers').doc(driverId).update({
      'status': 'rejected',
      'rejectionReason': fullReason,
    });

    await _notifyDriver(
      driverId,
      'Sakay Tiker: Your driver application was declined. Reason: $fullReason. You can register again with clearer documents. Questions? sakaytiker.support@gmail.com',
    );
  }

  Widget _docImage(dynamic url) {
    if (url == null || url.toString().isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('No photo uploaded'),
      );
    }
    return Image.network(
      url.toString(),
      errorBuilder: (_, _, _) => const Padding(
        padding: EdgeInsets.all(24),
        child: Text('Could not load photo'),
      ),
    );
  }

  Widget _buildPendingDrivers() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('drivers')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load applications: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('No pending applications');
        }

        final drivers = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: drivers.length,
          itemBuilder: (context, index) {
            final doc = drivers[index];
            final data = doc.data() as Map<String, dynamic>;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['fullName'] ?? 'Unknown',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text('Address: ${data['address'] ?? '-'}'),
                          Text('Phone: ${data['phoneNumber'] ?? '-'}'),
                          Text('Email: ${(data['email'] ?? '').toString().isEmpty ? '-' : data['email']}'),
                          Text('MTOP Number: ${data['mtopNumber'] ?? '-'}'),
                          Text('Plate Number: ${data['plateNumber'] ?? '-'}'),
                          const SizedBox(height: 8),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: _docImage(data['licenseFrontUrl']),
                                  ),
                                ),
                                child: const Text('View License Front'),
                              ),
                              TextButton(
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: _docImage(data['licenseBackUrl']),
                                  ),
                                ),
                                child: const Text('View License Back'),
                              ),
                              TextButton(
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: _docImage(data['tricyclePhotoUrl']),
                                  ),
                                ),
                                child: const Text('View Tricycle Photo'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        AnimatedPress(
                          onTap: () => _updateDriverStatus(doc.id, 'approved'),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            onPressed: () {},
                            child: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedPress(
                          onTap: () => _showRejectDialog(context, doc.id),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () {},
                            child: const Text('Reject'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // A driver counts as online only if they are marked online AND were active
  // in the last 3 minutes (the driver app refreshes this while it is open).
  bool _isDriverOnline(Map<String, dynamic> data) {
    if (data['isOnline'] != true) return false;
    final lastActive = data['lastActiveAt'];
    if (lastActive is! Timestamp) return false;
    return ServerClock.now().difference(lastActive.toDate()).inSeconds <= 180;
  }

  Widget _buildSearchField(TextEditingController controller, String label, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        onChanged: onChanged,
      ),
    );
  }

  // Helps spot why a driver is not counted as online.
  String _lastActiveText(Map<String, dynamic> data) {
    final v = data['lastActiveAt'];
    if (v is! Timestamp) return 'never';
    final secs = ServerClock.now().difference(v.toDate()).inSeconds;
    if (secs < 0) return 'just now';
    if (secs < 60) return '${secs}s ago';
    if (secs < 3600) return '${secs ~/ 60}m ago';
    if (secs < 86400) return '${secs ~/ 3600}h ago';
    return '${secs ~/ 86400}d ago';
  }

  Widget _buildAllDrivers() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchField(
          _driverSearchController,
          'Search by name or phone',
          (value) => setState(() => _driverSearch = value),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in const [
                ['all', 'All'],
                ['pending', 'Pending'],
                ['approved', 'Approved'],
                ['rejected', 'Rejected'],
              ])
                ChoiceChip(
                  label: Text(f[1]),
                  selected: _driverStatusFilter == f[0],
                  selectedColor: const Color(0xFFC8E6C9),
                  onSelected: (_) => setState(() => _driverStatusFilter = f[0]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _completedRidesStream,
            builder: (context, ridesSnap) {
              // driverId -> month -> commission earned from completed rides
              final rideSums = <String, Map<String, num>>{};
              for (final ride in ridesSnap.data?.docs ?? <QueryDocumentSnapshot>[]) {
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
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Could not load drivers: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return _buildEmptyState('No drivers found');
              }

              final query = _driverSearch.trim().toLowerCase();
              final drivers = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final name = (data['fullName'] ?? '').toString().toLowerCase();
                final phone = (data['phoneNumber'] ?? '').toString().toLowerCase();
                if (_driverStatusFilter != 'all' &&
                    (data['status'] ?? '').toString().toLowerCase() != _driverStatusFilter) {
                  return false;
                }
                return name.contains(query) || phone.contains(query);
              }).toList();

              if (drivers.isEmpty) return _buildEmptyState('No matching drivers');

              return _scrollableTable(
                countText: (query.isEmpty && _driverStatusFilter == 'all')
                    ? 'Total drivers: ${drivers.length}'
                    : 'Showing ${drivers.length} of ${snapshot.data!.docs.length} drivers',
                DataTable(
                  columns: const [
                    DataColumn(label: Text('#')),
                    DataColumn(label: Text('Name')),
                    DataColumn(label: Text('Phone')),
                    DataColumn(label: Text('Email')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Account')),
                    DataColumn(label: Text('Online')),
                    DataColumn(label: Text('Last Active')),
                    DataColumn(label: Text('No-Shows')),
                    DataColumn(label: Text('Cancellations')),
                    DataColumn(label: Text('Commission Owed')),
                  ],
                  rows: drivers.asMap().entries.map((entry) {
                    final doc = entry.value;
                    final data = doc.data() as Map<String, dynamic>;
                    final cancels = (data['cancelCount'] ?? 0) as num;
                    final online = _isDriverOnline(data);
                    return DataRow(key: ValueKey(doc.id), cells: [
                      DataCell(Text('${entry.key + 1}')),
                      DataCell(Text('${data['fullName'] ?? '-'}')),
                      DataCell(Text('${data['phoneNumber'] ?? '-'}')),
                      DataCell(Text((data['email'] ?? '').toString().isEmpty ? '-' : '${data['email']}')),
                      DataCell(Text('${data['status'] ?? '-'}')),
                      DataCell(Text('${data['accountStatus'] ?? 'active'}')),
                      DataCell(Text(
                        online ? 'Yes' : 'No',
                        style: TextStyle(
                          color: online ? Colors.green.shade700 : null,
                          fontWeight: online ? FontWeight.bold : FontWeight.normal,
                        ),
                      )),
                      DataCell(Text(_lastActiveText(data))),
                      DataCell(Text('${data['noShowCount'] ?? 0}')),
                      DataCell(Text(
                        '$cancels',
                        style: TextStyle(
                          fontWeight: cancels >= 3 ? FontWeight.bold : FontWeight.normal,
                          color: cancels >= 3 ? Colors.red : null,
                        ),
                      )),
                      DataCell(_CommissionOwedCell(driverId: doc.id, rideMonths: rideSums[doc.id] ?? const {})),
                    ]);
                  }).toList(),
                ),
              );
            },
              );
            },
          ),
        ),
      ],
    );
  }

  // Lets wide tables scroll sideways as well as up/down (prevents overflow errors).
  Widget _scrollableTable(Widget table, {String? countText}) {
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (countText != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  countText,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: table,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriversTab(_Counts counts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: _tabLabel('Pending', counts.pendingDrivers)),
              const ButtonSegment(value: 1, label: Text('All Drivers')),
              ButtonSegment(value: 2, label: _tabLabel('Commission', counts.pendingPayments)),
            ],
            selected: {_driversSubTab},
            onSelectionChanged: (newSelection) {
              setState(() => _driversSubTab = newSelection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (_driversSubTab) {
            0 => _buildPendingDrivers(),
            1 => _buildAllDrivers(),
            _ => const AdminCommissionScreen(),
          },
        ),
      ],
    );
  }

  Widget _buildOngoingRides() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .where('status', whereIn: ['pending', 'negotiating', 'accepted'])
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load rides: ${snapshot.error}'));
        }

        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('No ongoing rides right now');
        }

        final rides = _sortNewestFirst(snapshot.data!.docs, 'createdAt').where((d) {
          final data = d.data() as Map<String, dynamic>;
          final created = data['createdAt'];
          // Hide requests nobody accepted within 15 minutes.
          if (data['status'] == 'pending' && created is Timestamp) {
            return DateTime.now().difference(created.toDate()).inMinutes < 15;
          }
          return true;
        }).toList();

        if (rides.isEmpty) return _buildEmptyState('No ongoing rides right now');

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rides.length,
          itemBuilder: (context, index) {
            final data = rides[index].data() as Map<String, dynamic>;
            final status = (data['status'] ?? 'pending').toString();

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: status == 'accepted'
                  ? Colors.green.shade50
                  : (status == 'negotiating' ? Colors.blue.shade50 : Colors.orange.shade50),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          status == 'accepted'
                              ? 'ONGOING'
                              : (status == 'negotiating' ? 'NEGOTIATING FARE' : 'WAITING FOR DRIVER'),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: status == 'accepted'
                                ? Colors.green.shade800
                                : (status == 'negotiating' ? Colors.blue.shade800 : Colors.orange.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('Passenger: ${data['passengerName'] ?? '-'} (${data['passengerPhone'] ?? '-'})'),
                    Text('Type: ${data['passengerType'] ?? 'Regular'}'),
                    Text('Passengers: ${data['passengerCount'] ?? 1}'),
                    Text('Pickup: ${data['pickupLocation'] ?? '-'}'),
                    Text('Drop-off: ${data['dropoffLocation'] ?? '-'}'),
                    if (data['offeredFare'] != null)
                      Text('Passenger offered: ₱${data['offeredFare']}'),
                    if (status == 'negotiating')
                      Text(
                        'Counter offer: ₱${data['counterFare'] ?? '-'} from ${data['negotiatingDriverName'] ?? '-'} (${data['negotiatingDriverPhone'] ?? '-'})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    if (status == 'accepted') ...[
                      Text(
                        'Driver: ${data['driverName'] ?? '-'} (${data['driverPhone'] ?? '-'})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (data['agreedFare'] != null)
                        Text('Agreed fare: ₱${data['agreedFare']}'),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    final text = '${_weekday(d.weekday)}, ${_month(d.month)} ${d.day}, ${d.year}';
    if (diff == 0) return 'Today - $text';
    if (diff == 1) return 'Yesterday - $text';
    return text;
  }

  String _timeLabel(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  List<QueryDocumentSnapshot> _sortNewestFirst(List<QueryDocumentSnapshot> docs, String field) {
    final list = List<QueryDocumentSnapshot>.from(docs);
    DateTime time(QueryDocumentSnapshot d) {
      final v = (d.data() as Map<String, dynamic>)[field];
      return v is Timestamp ? v.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
    }
    list.sort((a, b) => time(b).compareTo(time(a)));
    return list;
  }

  Widget _buildRideHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchField(
          _rideHistorySearchController,
          'Search by passenger or driver name',
          (value) => setState(() => _rideHistorySearch = value),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _completedRidesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Could not load rides: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return _buildEmptyState('No completed rides yet');
              }

              final query = _rideHistorySearch.trim().toLowerCase();
              final rides = _sortNewestFirst(snapshot.data!.docs, 'completedAt').where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final passenger = (data['passengerName'] ?? '').toString().toLowerCase();
                final driver = (data['driverName'] ?? '').toString().toLowerCase();
                return passenger.contains(query) || driver.contains(query);
              }).toList();

              if (rides.isEmpty) return _buildEmptyState('No matching rides');

              // Group the rides by the day they were completed.
              final groups = <String, List<QueryDocumentSnapshot>>{};
              for (final doc in rides) {
                final data = doc.data() as Map<String, dynamic>;
                final ts = data['completedAt'];
                final key = ts is Timestamp ? _dateLabel(ts.toDate()) : 'Unknown date';
                groups.putIfAbsent(key, () => []).add(doc);
              }

              return Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        query.isEmpty
                            ? 'Total completed rides: ${rides.length}'
                            : 'Showing ${rides.length} of ${snapshot.data!.docs.length} rides',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                      ),
                    ),
                    for (final entry in groups.entries) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDEEDF),
                          borderRadius: BorderRadius.circular(8),
                          border: const Border(left: BorderSide(color: Color(0xFF1B5E20), width: 5)),
                        ),
                        child: Text(
                          '${entry.key}  ·  ${entry.value.length} ride${entry.value.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                        ),
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('#')),
                            DataColumn(label: Text('Time')),
                            DataColumn(label: Text('Passenger')),
                            DataColumn(label: Text('Type')),
                            DataColumn(label: Text('Driver')),
                            DataColumn(label: Text('Pickup')),
                            DataColumn(label: Text('Drop-off')),
                            DataColumn(label: Text('Fare')),
                            DataColumn(label: Text('Negotiated')),
                            DataColumn(label: Text('Commission')),
                          ],
                          rows: entry.value.asMap().entries.map((e) {
                            final doc = e.value;
                            final data = doc.data() as Map<String, dynamic>;
                            final ts = data['completedAt'];
                            return DataRow(key: ValueKey(doc.id), cells: [
                              DataCell(Text('${e.key + 1}')),
                              DataCell(Text(ts is Timestamp ? _timeLabel(ts.toDate()) : '-')),
                              DataCell(Text('${data['passengerName'] ?? '-'}')),
                              DataCell(Text('${data['passengerType'] ?? 'Regular'}')),
                              DataCell(Text('${data['driverName'] ?? '-'}')),
                              DataCell(Text('${data['pickupLocation'] ?? '-'}')),
                              DataCell(Text('${data['dropoffLocation'] ?? '-'}')),
                              DataCell(Text(data['fare'] != null ? '₱${data['fare']}' : '-')),
                              DataCell(Text(data['isNegotiated'] == true ? 'Yes' : 'No')),
                              DataCell(Text('₱${data['commissionAmount'] ?? 0}')),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRidesTab(_Counts counts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: _tabLabel('Ongoing', counts.ongoingRides)),
              const ButtonSegment(value: 1, label: Text('History')),
            ],
            selected: {_ridesSubTab},
            onSelectionChanged: (newSelection) {
              setState(() => _ridesSubTab = newSelection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _ridesSubTab == 0 ? _buildOngoingRides() : _buildRideHistory(),
        ),
      ],
    );
  }

  Widget _getSelectedPage(_Counts counts) {
    switch (_selectedIndex) {
      case 0:
        return AdminAnalyticsScreen(onNavigate: _navigateTo);
      case 1:
        return _buildDriversTab(counts);
      case 2:
        return const AdminPassengersScreen();
      case 3:
        return _buildRidesTab(counts);
      case 4:
        return const AdminFeedbackScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  String _weekday(int day) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[day - 1];
  }

  String _month(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  Widget _buildTopHeader(_Counts counts, {bool compact = false}) {
    return SizedBox(
      height: compact ? 64 : 76,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MountainSilhouette(height: 12),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 8 : 24, 0, compact ? 8 : 24, 8),
            child: Row(
              children: [
                if (compact)
                  Builder(
                    builder: (ctx) => Stack(
                      clipBehavior: Clip.none,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white),
                          tooltip: 'Menu',
                          onPressed: () => Scaffold.of(ctx).openDrawer(),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IgnorePointer(child: _CountBadge(count: counts.total)),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: EdgeInsets.all(compact ? 3 : 4),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset('assets/images/logo.png', height: compact ? 32 : 40),
                ),
                SizedBox(width: compact ? 10 : 14),
                Expanded(
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sakay Tiker Admin',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 16 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 1),
                      Text(
                        'Central Bontoc, Mountain Province',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                  ),
                ),
                if (!compact) ...[
                  Text(
                    '${_weekday(DateTime.now().weekday)}, ${_month(DateTime.now().month)} ${DateTime.now().day}',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Container(
                    height: 24,
                    width: 1,
                    color: Colors.white.withValues(alpha: 0.35),
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ],
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('drivers')
                      .where('status', isEqualTo: 'pending')
                      .snapshots(),
                  builder: (context, snapshot) {
                    final pendingDrivers = snapshot.data?.docs.length ?? 0;
                    return StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('drivers')
                          .where('commissionPaymentPending', isEqualTo: true)
                          .snapshots(),
                      builder: (context, paySnapshot) {
                        final pendingPayments = paySnapshot.data?.docs.length ?? 0;
                        final count = pendingDrivers + pendingPayments;
                        return Padding(
                          padding: EdgeInsets.zero,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              PopupMenuButton<int>(
                                tooltip: 'Notifications',
                                iconSize: 24,
                                padding: const EdgeInsets.all(8),
                                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                                onSelected: (tab) => _navigateTo(1, driversSubTab: tab),
                                itemBuilder: (context) => [
                                  if (pendingDrivers > 0)
                                    PopupMenuItem(
                                      value: 0,
                                      child: Text('$pendingDrivers driver registration${pendingDrivers == 1 ? '' : 's'} to review'),
                                    ),
                                  if (pendingPayments > 0)
                                    PopupMenuItem(
                                      value: 2,
                                      child: Text('$pendingPayments commission payment${pendingPayments == 1 ? '' : 's'} to verify'),
                                    ),
                                  if (count == 0)
                                    const PopupMenuItem(
                                      enabled: false,
                                      value: -1,
                                      child: Text('No new notifications'),
                                    ),
                                ],
                              ),
                              if (count > 0)
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                                      child: Text(
                                        '$count',
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Change password',
                  iconSize: 24,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: const Icon(Icons.key, color: Colors.white),
                  onPressed: () => showChangePasswordDialog(context),
                ),
                IconButton(
                  tooltip: 'Logout',
                  iconSize: 24,
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: const Icon(Icons.logout, color: Colors.white),
                  onPressed: () => _confirmLogout(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(_Counts counts, {bool inDrawer = false}) {
    return Container(
      width: inDrawer ? double.infinity : 220,
      color: const Color(0xFFEAF5EC),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 16),
        itemCount: _navItems.length,
        itemBuilder: (context, index) {
          final item = _navItems[index];
          final selected = _selectedIndex == index;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            child: Material(
              color: selected ? const Color(0xFF1B5E20) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _selectPage(index));
                  if (inDrawer) Navigator.pop(context);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        item['icon'] as IconData,
                        color: selected ? Colors.white : const Color(0xFF1B5E20),
                        size: 22,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          item['label'] as String,
                          style: TextStyle(
                            color: selected ? Colors.white : const Color(0xFF1B3A22),
                            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      _CountBadge(count: counts.forPage(index)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
            ),
          ),
          const VersionLabel(prefix: 'Sakay Tiker Admin'),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _withCounts(_buildLayout);
  }

  Widget _buildLayout(_Counts counts) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a phone-sized screen the side menu becomes a slide-out drawer.
        final narrow = constraints.maxWidth < 800;
        return Scaffold(
          drawer: narrow
              ? Drawer(
                  backgroundColor: const Color(0xFFEAF5EC),
                  child: SafeArea(child: _buildSidebar(counts, inDrawer: true)),
                )
              : null,
          body: Column(
            children: [
              _buildTopHeader(counts, compact: narrow),
              Expanded(
                child: Row(
                  children: [
                    if (!narrow) ...[
                      _buildSidebar(counts),
                      const VerticalDivider(width: 1),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.all(narrow ? 12.0 : 16.0),
                            child: Text(
                              _pages[_selectedIndex],
                              style: TextStyle(
                                fontSize: narrow ? 20 : 24,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1B5E20),
                              ),
                            ),
                          ),
                          Expanded(child: _getSelectedPage(counts)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


/// The numbers shown in the red badges.
class _Counts {
  final int pendingDrivers;
  final int pendingPayments;
  final int ongoingRides;
  final int newFeedback;

  const _Counts({
    required this.pendingDrivers,
    required this.pendingPayments,
    required this.ongoingRides,
    required this.newFeedback,
  });

  int get drivers => pendingDrivers + pendingPayments;
  int get total => drivers + ongoingRides + newFeedback;

  // Badge for each side-menu page (0 Overview, 1 Drivers, 2 Passengers, 3 Rides, 4 Feedback).
  int forPage(int index) {
    switch (index) {
      case 1:
        return drivers;
      case 3:
        return ongoingRides;
      case 4:
        return newFeedback;
      default:
        return 0;
    }
  }
}

/// Small red number. Shows nothing when the count is 0.
class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Shows the total unpaid commission across all months for one driver.
/// Keeps its own stream so the table can rebuild (e.g. while searching) without flicker.
class _CommissionOwedCell extends StatefulWidget {
  final String driverId;
  final Map<String, num> rideMonths;
  const _CommissionOwedCell({required this.driverId, required this.rideMonths});

  @override
  State<_CommissionOwedCell> createState() => _CommissionOwedCellState();
}

class _CommissionOwedCellState extends State<_CommissionOwedCell> {
  late final Stream<QuerySnapshot> _stream = FirebaseFirestore.instance
      .collection('drivers')
      .doc(widget.driverId)
      .collection('commission_records')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snapshot) {
        // Per month, use the higher of the saved record and the completed rides.
        final earned = <String, num>{};
        final paid = <String, num>{};
        for (final record in snapshot.data?.docs ?? <QueryDocumentSnapshot>[]) {
          final r = record.data() as Map<String, dynamic>;
          earned[record.id] = (r['totalEarned'] ?? 0) as num;
          paid[record.id] = (r['amountPaid'] ?? 0) as num;
        }
        widget.rideMonths.forEach((month, rideTotal) {
          if (rideTotal > (earned[month] ?? 0)) earned[month] = rideTotal;
        });
        num owed = 0;
        earned.forEach((month, e) {
          final b = e - (paid[month] ?? 0);
          if (b > 0) owed += b;
        });
        return Text(
          '₱$owed',
          style: TextStyle(
            fontWeight: owed > 0 ? FontWeight.bold : FontWeight.normal,
            color: owed > 0 ? Colors.red : null,
          ),
        );
      },
    );
  }
}