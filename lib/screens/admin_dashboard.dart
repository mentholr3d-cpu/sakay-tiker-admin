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
import 'admin_ban_cell.dart';
import 'commission_period.dart';

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

  // Ride history shows finished rides: completed, cancelled by the passenger, and no-shows.
  final Stream<QuerySnapshot> _historyRidesStream = FirebaseFirestore.instance
      .collection('rides')
      .where('status', whereIn: ['completed', 'cancelled', 'no_show'])
      .snapshots();
  String _historyFilter = 'all'; // all, completed, cancelled, no_show

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

  // ---- Live counts for the red badges ----
  final List<StreamSubscription> _badgeSubs = [];
  int _pendingDriverCount = 0;
  int _pendingPaymentCount = 0;
  List<Map<String, dynamic>> _activeRides = [];
  List<DateTime> _rideFeedbackTimes = [];
  List<DateTime> _appFeedbackTimes = [];
  bool _rideFeedbackLoaded = false;
  bool _appFeedbackLoaded = false;
  int? _feedbackSeenMs; // newest feedback the admin has already looked at

  // Requests nobody accepted within 15 minutes are not counted as ongoing.
  int get _ongoingRideCount => _activeRides.where((data) {
        final created = data['createdAt'];
        if (data['status'] == 'pending' && created is Timestamp) {
          return DateTime.now().difference(created.toDate()).inMinutes < 15;
        }
        return true;
      }).length;

  int get _unseenFeedbackCount {
    final seen = _feedbackSeenMs;
    if (seen == null) return 0;
    return [..._rideFeedbackTimes, ..._appFeedbackTimes]
        .where((t) => t.millisecondsSinceEpoch > seen)
        .length;
  }

  int get _driversBadgeCount => _pendingDriverCount + _pendingPaymentCount;

  DateTime? _newestFeedbackTime() {
    final all = [..._rideFeedbackTimes, ..._appFeedbackTimes];
    if (all.isEmpty) return null;
    all.sort();
    return all.last;
  }

  List<DateTime> _timesFrom(QuerySnapshot snap) {
    final times = <DateTime>[];
    for (final d in snap.docs) {
      final created = (d.data() as Map<String, dynamic>)['createdAt'];
      if (created is Timestamp) times.add(created.toDate());
    }
    return times;
  }

  Future<void> _setFeedbackSeen(int ms) async {
    _feedbackSeenMs = ms;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('adminFeedbackSeenMs', ms);
    } catch (_) {}
  }

  // Called when the admin opens the Feedback page (or while it is open).
  void _markFeedbackSeen() {
    final newest = _newestFeedbackTime();
    final ms = newest?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
    if (_feedbackSeenMs == null || ms > _feedbackSeenMs!) {
      _setFeedbackSeen(ms);
    }
  }

  // The first time this browser opens the dashboard, existing feedback counts
  // as already seen so the badge only shows feedback that arrives afterwards.
  void _afterFeedbackUpdate() {
    if (!_rideFeedbackLoaded || !_appFeedbackLoaded) return;
    if (_feedbackSeenMs == null) {
      final newest = _newestFeedbackTime();
      _setFeedbackSeen(newest?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch);
    } else if (_selectedIndex == 4) {
      _markFeedbackSeen();
    }
    if (mounted) setState(() {});
  }

  Future<void> _startBadgeListeners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _feedbackSeenMs = prefs.getInt('adminFeedbackSeenMs');
    } catch (_) {}

    final db = FirebaseFirestore.instance;

    _badgeSubs.add(db
        .collection('drivers')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _pendingDriverCount = snap.docs.length);
    }, onError: (_) {}));

    _badgeSubs.add(db
        .collection('drivers')
        .where('commissionPaymentPending', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() => _pendingPaymentCount = snap.docs.length);
    }, onError: (_) {}));

    _badgeSubs.add(db
        .collection('rides')
        .where('status', whereIn: ['pending', 'negotiating', 'accepted'])
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _activeRides = snap.docs.map((d) => d.data()).toList();
      });
    }, onError: (_) {}));

    _badgeSubs.add(db.collection('ride_feedback').snapshots().listen((snap) {
      _rideFeedbackTimes = _timesFrom(snap);
      _rideFeedbackLoaded = true;
      _afterFeedbackUpdate();
    }, onError: (_) {}));

    _badgeSubs.add(db.collection('app_feedback').snapshots().listen((snap) {
      _appFeedbackTimes = _timesFrom(snap);
      _appFeedbackLoaded = true;
      _afterFeedbackUpdate();
    }, onError: (_) {}));
  }

  // Small red number used on buttons and the sidebar. Shows nothing for 0.
  Widget _redBadge(int count) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _labelWithBadge(String text, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Text(text), _redBadge(count)],
    );
  }

  @override
  void initState() {
    super.initState();
    ServerClock.sync();
    _startBadgeListeners();
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
    for (final s in _badgeSubs) {
      s.cancel();
    }
    _driverSearchController.dispose();
    _rideHistorySearchController.dispose();
    super.dispose();
  }

  void _navigateTo(int pageIndex, {int? driversSubTab, int? ridesSubTab}) {
    setState(() {
      _selectedIndex = pageIndex;
      if (driversSubTab != null) _driversSubTab = driversSubTab;
      if (ridesSubTab != null) _ridesSubTab = ridesSubTab;
    });
    if (pageIndex == 4) _markFeedbackSeen();
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
                final key = CommissionPeriod.keyFor(d);
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
                    DataColumn(label: Text('Ride Ban')),
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
                      DataCell(_DriverBanCell(driverId: doc.id, data: data)),
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

  Widget _buildDriversTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: _labelWithBadge('Pending', _pendingDriverCount)),
              const ButtonSegment(value: 1, label: Text('All Drivers')),
              ButtonSegment(value: 2, label: _labelWithBadge('Commission', _pendingPaymentCount)),
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
                    Text(
                      'Ride: ${(data['rideType'] == 'Arkila' || data['offeredFare'] != null) ? 'Arkila' : 'Regular Ride'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      (data['typesConfirmed'] == true || data['agreedFare'] != null)
                          ? 'Type: ${data['passengerType'] ?? 'Regular'}'
                          : 'Type: waiting for the driver to confirm',
                    ),
                    Text('Passengers: ${data['passengerCount'] ?? 1}'),
                    if (data['hasBulkyItem'] == true) ...[
                      const Text(
                        'Carrying something big',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange),
                      ),
                      if ((data['bulkyItemPhotoUrl'] ?? '').toString().isNotEmpty)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
                            onPressed: () => launchUrl(
                              Uri.parse(data['bulkyItemPhotoUrl'].toString()),
                              mode: LaunchMode.externalApplication,
                            ),
                            icon: const Icon(Icons.photo_outlined, size: 18),
                            label: const Text('View bag / item photo'),
                          ),
                        ),
                    ],
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
                        Text('Agreed fare: ₱${data['agreedFare']}')
                      else if (data['typesConfirmed'] == true)
                        Text(
                          'Fare: ₱${(((data['passengerTypes'] as List?) ?? const []).fold<num>(0, (total, t) => total + (t == 'Regular' ? 17 : 14))).toStringAsFixed(2)}',
                        ),
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

  DateTime _rideEndTime(Map<String, dynamic> data) {
    for (final key in ['completedAt', 'cancelledAt', 'noShowAt', 'createdAt']) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  String _historyStatusLabel(Map<String, dynamic> data) {
    switch (data['status']) {
      case 'cancelled':
        return data['driverId'] != null ? 'Cancelled after accepted' : 'Cancelled before accepted';
      case 'no_show':
        return data['noShowBy'] == 'driver' ? 'Driver no-show' : 'Passenger no-show';
      default:
        return 'Completed';
    }
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
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final f in const [
                ['all', 'All'],
                ['completed', 'Completed'],
                ['cancelled', 'Cancelled'],
                ['no_show', 'No-show'],
              ])
                ChoiceChip(
                  label: Text(f[1]),
                  selected: _historyFilter == f[0],
                  selectedColor: const Color(0xFFC8E6C9),
                  onSelected: (_) => setState(() => _historyFilter = f[0]),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _historyRidesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Could not load rides: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.docs.isEmpty) {
                return _buildEmptyState('No finished rides yet');
              }

              final query = _rideHistorySearch.trim().toLowerCase();
              final rides = snapshot.data!.docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (_historyFilter != 'all' && data['status'] != _historyFilter) return false;
                final passenger = (data['passengerName'] ?? '').toString().toLowerCase();
                final driver = (data['driverName'] ?? '').toString().toLowerCase();
                return passenger.contains(query) || driver.contains(query);
              }).toList()
                ..sort((a, b) => _rideEndTime(b.data() as Map<String, dynamic>)
                    .compareTo(_rideEndTime(a.data() as Map<String, dynamic>)));

              if (rides.isEmpty) return _buildEmptyState('No matching rides');

              final completedCount =
                  rides.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'completed').length;

              // Group the rides by the day they ended.
              final groups = <String, List<QueryDocumentSnapshot>>{};
              for (final doc in rides) {
                final data = doc.data() as Map<String, dynamic>;
                final t = _rideEndTime(data);
                final key = t.millisecondsSinceEpoch == 0 ? 'Unknown date' : _dateLabel(t);
                groups.putIfAbsent(key, () => []).add(doc);
              }

              return Scrollbar(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        (query.isEmpty && _historyFilter == 'all')
                            ? 'Total rides: ${rides.length}  ·  Completed: $completedCount'
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
                            DataColumn(label: Text('Result')),
                            DataColumn(label: Text('Ride')),
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
                            final done = data['status'] == 'completed';
                            final t = _rideEndTime(data);
                            return DataRow(
                              key: ValueKey(doc.id),
                              color: done ? null : WidgetStatePropertyAll(Colors.red.shade50),
                              cells: [
                                DataCell(Text('${e.key + 1}')),
                                DataCell(Text(t.millisecondsSinceEpoch == 0 ? '-' : _timeLabel(t))),
                                DataCell(Text(
                                  _historyStatusLabel(data),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: done ? Colors.green.shade800 : Colors.red.shade800,
                                  ),
                                )),
                                DataCell(Text((data['rideType'] == 'Arkila' || data['offeredFare'] != null) ? 'Arkila' : 'Regular')),
                                DataCell(Text('${data['passengerName'] ?? '-'}')),
                                DataCell(Text(done ? '${data['passengerType'] ?? 'Regular'}' : '-')),
                                DataCell(Text('${data['driverName'] ?? '-'}')),
                                DataCell(Text('${data['pickupLocation'] ?? '-'}')),
                                DataCell(Text('${data['dropoffLocation'] ?? '-'}')),
                                DataCell(Text(done && data['fare'] != null ? '₱${data['fare']}' : '-')),
                                DataCell(Text(done ? (data['isNegotiated'] == true ? 'Yes' : 'No') : '-')),
                                DataCell(Text(done ? '₱${data['commissionAmount'] ?? 0}' : '-')),
                              ],
                            );
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

  Widget _buildRidesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: _labelWithBadge('Ongoing', _ongoingRideCount)),
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

  Widget _getSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return AdminAnalyticsScreen(onNavigate: _navigateTo);
      case 1:
        return _buildDriversTab();
      case 2:
        return const AdminPassengersScreen();
      case 3:
        return _buildRidesTab();
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

  Widget _buildTopHeader({bool compact = false}) {
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
                    builder: (ctx) => IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      tooltip: 'Menu',
                      onPressed: () => Scaffold.of(ctx).openDrawer(),
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
                Builder(
                  builder: (context) {
                    final pendingDrivers = _pendingDriverCount;
                    final pendingPayments = _pendingPaymentCount;
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

  int _sidebarBadgeFor(int index) {
    switch (index) {
      case 1:
        return _driversBadgeCount;
      case 3:
        return _ongoingRideCount;
      case 4:
        return _unseenFeedbackCount;
      default:
        return 0;
    }
  }

  Widget _buildSidebar({bool inDrawer = false}) {
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
                  setState(() => _selectedIndex = index);
                  if (index == 4) _markFeedbackSeen();
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
                      _redBadge(_sidebarBadgeFor(index)),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // On a phone-sized screen the side menu becomes a slide-out drawer.
        final narrow = constraints.maxWidth < 800;
        return Scaffold(
          drawer: narrow
              ? Drawer(
                  backgroundColor: const Color(0xFFEAF5EC),
                  child: SafeArea(child: _buildSidebar(inDrawer: true)),
                )
              : null,
          body: Column(
            children: [
              _buildTopHeader(compact: narrow),
              Expanded(
                child: Row(
                  children: [
                    if (!narrow) ...[
                      _buildSidebar(),
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
                          Expanded(child: _getSelectedPage()),
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


/// Ride Ban column for a driver: a short cancellation ban, and/or "blocked"
/// when a past week's commission is still unpaid (cleared by Mark Paid).
class _DriverBanCell extends StatefulWidget {
  final String driverId;
  final Map<String, dynamic> data;
  const _DriverBanCell({required this.driverId, required this.data});

  @override
  State<_DriverBanCell> createState() => _DriverBanCellState();
}

class _DriverBanCellState extends State<_DriverBanCell> {
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
        num overdue = 0;
        for (final record in snapshot.data?.docs ?? <QueryDocumentSnapshot>[]) {
          if (!CommissionPeriod.isOverdueKey(record.id)) continue;
          final r = record.data() as Map<String, dynamic>;
          final b = ((r['totalEarned'] ?? 0) as num) - ((r['amountPaid'] ?? 0) as num);
          if (b > 0) overdue += b;
        }
        final hasBan = AdminBanCell.banUntil(widget.data) != null;
        if (overdue <= 0) {
          return AdminBanCell(collection: 'drivers', id: widget.driverId, data: widget.data);
        }
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
                'Blocked: ₱$overdue unpaid',
                style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            if (hasBan) ...[
              const SizedBox(width: 6),
              AdminBanCell(collection: 'drivers', id: widget.driverId, data: widget.data),
            ],
          ],
        );
      },
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