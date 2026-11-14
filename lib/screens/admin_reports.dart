import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'commission_period.dart';
import 'admin_logo_data.dart';

/// Admin > Reports: day / week / month / year summaries for all drivers or one driver.
/// On screen it is detailed; the printed page is a short one-page version with a signature line.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _DriverOption {
  final String id;
  final String name;
  final String plate;
  final String mtop;
  const _DriverOption(this.id, this.name, this.plate, this.mtop);
}

class _RideRow {
  final DateTime? when; // Manila time
  final String pickup;
  final String dropoff;
  final String passenger;
  final String driver;
  final String status;
  final double? fare;
  const _RideRow(this.when, this.pickup, this.dropoff, this.passenger, this.driver, this.status, this.fare);
}

class _ReportData {
  final String title;
  final String rangeLabel;
  final DateTime generatedAt; // Manila time
  final _DriverOption? driver; // null = all drivers
  // Rides
  int total = 0, completed = 0, cancelled = 0, expired = 0, noShow = 0, active = 0;
  int regular = 0, arkila = 0, negotiated = 0, declined = 0;
  double fareTotal = 0, commissionEarned = 0;
  // Rankings
  List<MapEntry<String, int>> topPickups = [];
  List<MapEntry<String, int>> topDropoffs = [];
  List<int> hours = List.filled(24, 0);
  // Safety
  int cancelledByPassenger = 0, cancelledByDriver = 0, farFromDropoff = 0;
  // Users
  int newPassengers = 0, newDrivers = 0;
  // Commission records (null = could not be read)
  double? recTotalEarned, recPaid, recBalance;
  int? recPendingReview;
  // Previous period
  int prevTotal = 0, prevCompleted = 0;
  double prevFare = 0;
  // Ride list (newest first)
  List<_RideRow> rows = [];

  _ReportData(this.title, this.rangeLabel, this.generatedAt, this.driver);

  double get avgFare => completed == 0 ? 0 : fareTotal / completed;
  double get completionRate => total == 0 ? 0 : completed * 100 / total;
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  static const _green = Color(0xFF1B5E20);
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _shortMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  static const int _pageSize = 10;

  String _period = 'day'; // day | week | month | year
  String _scope = 'all'; // all | driver
  late DateTime _anchor; // Manila calendar date (y/m/d only)
  final _preparedBy = TextEditingController();

  List<_DriverOption> _drivers = [];
  String? _driverId;

  bool _loading = false;
  String? _error;
  _ReportData? _report;
  int _visibleRides = _pageSize;

  @override
  void initState() {
    super.initState();
    final m = _manilaNow();
    _anchor = DateTime(m.year, m.month, m.day);
    _loadDrivers();
    _generate();
  }

  @override
  void dispose() {
    _preparedBy.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('drivers').get();
      final list = <_DriverOption>[];
      for (final d in snap.docs) {
        final x = d.data();
        final status = (x['status'] ?? '').toString();
        if (status == 'pending' || status == 'rejected') continue;
        list.add(_DriverOption(
          d.id,
          (x['fullName'] ?? 'Unnamed driver').toString(),
          (x['plateNumber'] ?? '').toString(),
          (x['mtopNumber'] ?? '').toString(),
        ));
      }
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() => _drivers = list);
    } catch (_) {
      // The one-driver option then simply has no names to pick from.
    }
  }

  // ---------- time helpers (Philippine time, UTC+8) ----------
  DateTime _manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
  DateTime _toManila(Timestamp t) => t.toDate().toUtc().add(const Duration(hours: 8));
  DateTime _instant(DateTime manilaWall) =>
      DateTime.utc(manilaWall.year, manilaWall.month, manilaWall.day).subtract(const Duration(hours: 8));

  DateTime _startFor(DateTime a) {
    switch (_period) {
      case 'week':
        return DateTime(a.year, a.month, a.day).subtract(Duration(days: a.weekday - 1));
      case 'month':
        return DateTime(a.year, a.month, 1);
      case 'year':
        return DateTime(a.year, 1, 1);
      default:
        return DateTime(a.year, a.month, a.day);
    }
  }

  DateTime _endFor(DateTime start) {
    switch (_period) {
      case 'week':
        return DateTime(start.year, start.month, start.day + 7);
      case 'month':
        return DateTime(start.year, start.month + 1, 1);
      case 'year':
        return DateTime(start.year + 1, 1, 1);
      default:
        return DateTime(start.year, start.month, start.day + 1);
    }
  }

  DateTime _prevStart(DateTime start) {
    switch (_period) {
      case 'week':
        return DateTime(start.year, start.month, start.day - 7);
      case 'month':
        return DateTime(start.year, start.month - 1, 1);
      case 'year':
        return DateTime(start.year - 1, 1, 1);
      default:
        return DateTime(start.year, start.month, start.day - 1);
    }
  }

  String _fmtDate(DateTime d) => '${_shortMonths[d.month - 1]} ${d.day}, ${d.year}';

  String _fmtTime(DateTime d) =>
      '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';

  String _rangeLabel(DateTime start, DateTime end) {
    final last = DateTime(end.year, end.month, end.day - 1);
    switch (_period) {
      case 'week':
        return '${_fmtDate(start)} - ${_fmtDate(last)}';
      case 'month':
        return '${_months[start.month - 1]} ${start.year}';
      case 'year':
        return '${start.year}';
      default:
        return _fmtDate(start);
    }
  }

  String get _periodName => switch (_period) {
        'week' => 'Weekly',
        'month' => 'Monthly',
        'year' => 'Yearly',
        _ => 'Daily',
      };

  Future<void> _pickDate() async {
    final now = _manilaNow();
    if (_period == 'year') {
      final y = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Select year'),
          children: [
            for (var y = now.year; y >= now.year - 5; y--)
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, y), child: Text('$y')),
          ],
        ),
      );
      if (y != null) {
        setState(() => _anchor = DateTime(y, 1, 1));
        _generate();
      }
      return;
    }
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor.isAfter(today) ? today : _anchor,
      firstDate: DateTime(2024),
      lastDate: today,
    );
    if (picked != null) {
      setState(() => _anchor = picked);
      _generate();
    }
  }

  // ---------- data ----------
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _ridesBetween(DateTime s, DateTime e) async {
    final snap = await FirebaseFirestore.instance
        .collection('rides')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_instant(s)))
        .where('createdAt', isLessThan: Timestamp.fromDate(_instant(e)))
        .get();
    return snap.docs;
  }

  Future<int> _countUsers(String collection, DateTime s, DateTime e) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(collection)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_instant(s)))
          .where('createdAt', isLessThan: Timestamp.fromDate(_instant(e)))
          .get();
      return snap.docs.length;
    } catch (_) {
      return 0;
    }
  }

  List<MapEntry<String, int>> _top(Map<String, int> m, [int n = 5]) {
    final list = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  _DriverOption? get _selectedDriver {
    for (final d in _drivers) {
      if (d.id == _driverId) return d;
    }
    return null;
  }

  Future<void> _generate() async {
    if (_scope == 'driver' && _driverId == null) {
      setState(() {
        _report = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _visibleRides = _pageSize;
    });
    try {
      final start = _startFor(_anchor);
      final end = _endFor(start);
      final driver = _scope == 'driver' ? _selectedDriver : null;
      final driverId = _scope == 'driver' ? _driverId : null;
      final r = _ReportData(
        driver == null ? '$_periodName Report' : '$_periodName Driver Report',
        _rangeLabel(start, end),
        _manilaNow(),
        driver,
      );

      bool mine(Map<String, dynamic> x) => driverId == null || x['driverId'] == driverId;

      final allDocs = await _ridesBetween(start, end);
      final pickups = <String, int>{};
      final dropoffs = <String, int>{};
      final rows = <_RideRow>[];

      for (final d in allDocs) {
        final x = d.data();
        if (driverId != null) {
          final declinedBy = x['declinedBy'];
          if (declinedBy is List && declinedBy.contains(driverId)) r.declined++;
        }
        if (!mine(x)) continue;

        r.total++;
        final status = (x['status'] ?? '').toString();
        switch (status) {
          case 'completed':
            r.completed++;
            r.fareTotal += ((x['fare'] ?? 0) as num).toDouble();
            r.commissionEarned += ((x['commissionAmount'] ?? 0) as num).toDouble();
            if (x['completedFarFromDropoff'] == true) r.farFromDropoff++;
            break;
          case 'cancelled':
            r.cancelled++;
            if (x['cancelledByPassenger'] == true) r.cancelledByPassenger++;
            if (x['cancelledByDriver'] == true) r.cancelledByDriver++;
            break;
          case 'expired':
            r.expired++;
            break;
          case 'no_show':
            r.noShow++;
            break;
          default:
            r.active++;
        }
        if (x['rideType'] == 'Arkila') {
          r.arkila++;
        } else {
          r.regular++;
        }
        if (x['isNegotiated'] == true) r.negotiated++;
        final p = (x['pickupLocation'] ?? '').toString().trim();
        if (p.isNotEmpty) pickups[p] = (pickups[p] ?? 0) + 1;
        final dr = (x['dropoffLocation'] ?? '').toString().trim();
        if (dr.isNotEmpty) dropoffs[dr] = (dropoffs[dr] ?? 0) + 1;
        final c = x['createdAt'];
        DateTime? when;
        if (c is Timestamp) {
          when = _toManila(c);
          r.hours[when.hour]++;
        }
        final fareNum = x['fare'];
        rows.add(_RideRow(
          when,
          p.isEmpty ? '-' : p,
          dr.isEmpty ? '-' : dr,
          (x['passengerName'] ?? 'Passenger').toString(),
          (x['driverName'] ?? '').toString(),
          status,
          fareNum is num ? fareNum.toDouble() : null,
        ));
      }
      rows.sort((a, b) {
        final aw = a.when, bw = b.when;
        if (aw == null && bw == null) return 0;
        if (aw == null) return 1;
        if (bw == null) return -1;
        return bw.compareTo(aw);
      });
      r.rows = rows;
      r.topPickups = _top(pickups);
      r.topDropoffs = _top(dropoffs);

      // Previous period (for the on-screen comparison).
      final prevDocs = await _ridesBetween(_prevStart(start), start);
      for (final d in prevDocs) {
        final x = d.data();
        if (!mine(x)) continue;
        r.prevTotal++;
        if (x['status'] == 'completed') {
          r.prevCompleted++;
          r.prevFare += ((x['fare'] ?? 0) as num).toDouble();
        }
      }

      if (driverId == null) {
        r.newPassengers = await _countUsers('passengers', start, end);
        r.newDrivers = await _countUsers('drivers', start, end);
      }

      // Commission records for the months inside this period.
      try {
        final keys = <String>{};
        var cur = DateTime(start.year, start.month, 1);
        while (cur.isBefore(end)) {
          keys.add(CommissionPeriod.keyFor(cur));
          cur = DateTime(cur.year, cur.month + 1, 1);
        }
        final snap = await FirebaseFirestore.instance.collectionGroup('commission_records').get();
        double earned = 0, paid = 0;
        int review = 0;
        for (final d in snap.docs) {
          if (!keys.contains(d.id)) continue;
          if (driverId != null && d.reference.parent.parent?.id != driverId) continue;
          final x = d.data();
          earned += ((x['totalEarned'] ?? 0) as num).toDouble();
          paid += ((x['amountPaid'] ?? 0) as num).toDouble();
          if (x['paymentSubmitted'] == true && x['status'] != 'paid') review++;
        }
        r.recTotalEarned = earned;
        r.recPaid = paid;
        r.recBalance = (earned - paid) < 0 ? 0 : earned - paid;
        r.recPendingReview = review;
      } catch (_) {
        // Leave null: only the commission earned from rides is shown.
      }

      if (!mounted) return;
      setState(() {
        _report = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not build the report: $e';
        _loading = false;
      });
    }
  }

  // ---------- formatting ----------
  String _money(double v, {String sign = '₱'}) {
    final fixed = v.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
    return '$sign$whole.${parts[1]}';
  }

  String _pct(double v) => '${v.toStringAsFixed(1)}%';

  String _delta(num now, num before) {
    if (before == 0) return now == 0 ? 'no change' : 'new activity (none before)';
    final p = (now - before) * 100 / before;
    return '${p >= 0 ? '+' : ''}${p.toStringAsFixed(0)}% vs previous';
  }

  String _hourLabel(int h) {
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hh = h % 12 == 0 ? 12 : h % 12;
    return '$hh $suffix';
  }

  String _statusLabel(String s) => switch (s) {
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'expired' => 'Expired',
        'no_show' => 'No-show',
        'pending' => 'Waiting',
        'negotiating' => 'Negotiating',
        'accepted' => 'On the way',
        _ => s.isEmpty ? '-' : s,
      };

  Color _statusColor(String s) => switch (s) {
        'completed' => _green,
        'cancelled' => Colors.red.shade700,
        'no_show' => Colors.orange.shade800,
        'expired' => Colors.grey.shade700,
        _ => Colors.blue.shade700,
      };

  // ---------- Print (one short page, A4 width x short-bond height) ----------
  Future<void> _print() async {
    final r = _report;
    if (r == null) return;
    final doc = pw.Document();
    final green = PdfColor.fromInt(0xFF1B5E20);
    final grey = PdfColors.grey700;
    String pm(double v) => _money(v, sign: 'PHP ');

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 5),
          child: pw.Text(t, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: green)),
        );

    pw.Widget table(List<String> head, List<List<String>> rows) => pw.TableHelper.fromTextArray(
          headers: head,
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
          headerDecoration: pw.BoxDecoration(color: green),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignments: {for (var i = 1; i < head.length; i++) i: pw.Alignment.centerRight},
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        );

    List<List<String>> rank(List<MapEntry<String, int>> l) =>
        l.isEmpty ? [['No data', '-']] : [for (final e in l) [e.key, '${e.value}']];

    final d = r.driver;
    final name = _preparedBy.text.trim().toUpperCase();

    final commissionRows = <List<String>>[
      ['Commission earned from completed rides', pm(r.commissionEarned)],
      if (r.recTotalEarned != null) ...[
        ['Paid', pm(r.recPaid ?? 0)],
        ['Unpaid', pm(r.recBalance ?? 0)],
      ],
    ];

    pw.Widget signature() => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.SizedBox(
              width: 250,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Prepared by:', style: pw.TextStyle(fontSize: 10, color: grey)),
                  pw.SizedBox(height: 34),
                  pw.Container(height: 0.8, color: PdfColors.black),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    name.isEmpty ? 'Name and signature' : name,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: name.isEmpty ? pw.FontWeight.normal : pw.FontWeight.bold,
                      color: name.isEmpty ? grey : PdfColors.black,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

    final body = <pw.Widget>[
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Image(pw.MemoryImage(base64Decode(kReportLogoBase64)), width: 62, height: 62),
          pw.SizedBox(width: 14),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(r.title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: green)),
                pw.SizedBox(height: 2),
                pw.Text('Period: ${r.rangeLabel}', style: const pw.TextStyle(fontSize: 10.5)),
                pw.Text('Date generated: ${_fmtDate(r.generatedAt)}, ${_fmtTime(r.generatedAt)}',
                    style: pw.TextStyle(fontSize: 9, color: grey)),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Divider(color: green, thickness: 1.5),
      if (d != null) ...[
        heading('Driver'),
        table(['Name', 'Plate number', 'MTOP number'], [
          [d.name, d.plate.isEmpty ? '-' : d.plate, d.mtop.isEmpty ? '-' : d.mtop],
        ]),
      ],
      heading('Rides and fares'),
      if (d == null)
        table(['Measure', 'Total'], [
          ['Ride requests', '${r.total}'],
          ['Completed', '${r.completed}'],
          ['Cancelled', '${r.cancelled}'],
          ['Expired (no driver found)', '${r.expired}'],
          ['No-show', '${r.noShow}'],
          ['Completion rate', _pct(r.completionRate)],
          ['Total fare', pm(r.fareTotal)],
          ['Average fare per completed ride', pm(r.avgFare)],
        ])
      else
        table(['Measure', 'Total'], [
          ['Rides accepted', '${r.total}'],
          ['Completed', '${r.completed}'],
          ['Cancelled', '${r.cancelled}'],
          ['No-show', '${r.noShow}'],
          ['Offers declined', '${r.declined}'],
          ['Completion rate', _pct(r.completionRate)],
          ['Total fare', pm(r.fareTotal)],
          ['Average fare per completed ride', pm(r.avgFare)],
        ]),
      heading('Commission'),
      table(['Measure', 'Amount'], commissionRows),
      if (d == null) ...[
        heading('Busiest places'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: table(['Top 5 pickup', 'Rides'], rank(r.topPickups))),
            pw.SizedBox(width: 12),
            pw.Expanded(child: table(['Top 5 drop-off', 'Rides'], rank(r.topDropoffs))),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'New passengers registered: ${r.newPassengers}     New drivers registered: ${r.newDrivers}',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
      pw.Spacer(),
      signature(),
    ];

    doc.addPage(
      pw.Page(
        // A4 width and short-bond height, so it fits either paper without cutting.
        pageFormat: PdfPageFormat(210 * PdfPageFormat.mm, 279 * PdfPageFormat.mm, marginAll: 14 * PdfPageFormat.mm),
        build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: body),
      ),
    );

    final bytes = await doc.save();
    await Printing.layoutPdf(
      name: 'sakay_tiker_${_period}_report_${r.rangeLabel.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}',
      onLayout: (format) async => bytes,
    );
  }

  // ---------- UI ----------
  Widget _card(String label, String value, IconData icon, Color color, {String? sub}) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (sub != null) Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _green)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _rank(List<MapEntry<String, int>> list) {
    if (list.isEmpty) return Text('No data for this period.', style: TextStyle(color: Colors.grey.shade600));
    final maxV = list.first.value;
    return Column(
      children: [
        for (final e in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(width: 150, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxV == 0 ? 0 : e.value / maxV,
                      minHeight: 10,
                      backgroundColor: Colors.grey.shade200,
                      color: _green,
                    ),
                  ),
                ),
                SizedBox(width: 36, child: Text('${e.value}', textAlign: TextAlign.right)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _hoursChart(_ReportData r) {
    final maxV = r.hours.reduce((a, b) => a > b ? a : b);
    if (maxV == 0) return Text('No data for this period.', style: TextStyle(color: Colors.grey.shade600));
    return SizedBox(
      height: 110,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var h = 0; h < 24; h++)
            Expanded(
              child: Tooltip(
                message: '${_hourLabel(h)}: ${r.hours[h]}',
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      height: 80 * r.hours[h] / maxV,
                      color: r.hours[h] == maxV ? _green : Colors.green.shade300,
                    ),
                    const SizedBox(height: 4),
                    Text(h % 6 == 0 ? '$h' : '', style: const TextStyle(fontSize: 10)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ridesList(_ReportData r) {
    if (r.rows.isEmpty) {
      return Text('No rides in this period.', style: TextStyle(color: Colors.grey.shade600));
    }
    final shown = r.rows.length < _visibleRides ? r.rows.length : _visibleRides;
    final showDriver = r.driver == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < shown; i++) ...[
          if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.rows[i].pickup}  →  ${r.rows[i].dropoff}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (r.rows[i].when != null) '${_fmtDate(r.rows[i].when!)}, ${_fmtTime(r.rows[i].when!)}',
                          'Passenger: ${r.rows[i].passenger}',
                          if (showDriver && r.rows[i].driver.isNotEmpty) 'Driver: ${r.rows[i].driver}',
                        ].join('  •  '),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      r.rows[i].fare == null ? '-' : _money(r.rows[i].fare!),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(r.rows[i].status).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _statusLabel(r.rows[i].status),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(r.rows[i].status)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            Text('Showing $shown of ${r.rows.length}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const Spacer(),
            if (_visibleRides > _pageSize)
              TextButton(
                onPressed: () => setState(() => _visibleRides = _pageSize),
                child: const Text('Show less'),
              ),
            if (shown < r.rows.length)
              TextButton.icon(
                onPressed: () => setState(() => _visibleRides += _pageSize),
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('See more'),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final start = _startFor(_anchor);
    final end = _endFor(start);
    final isDriver = r?.driver != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: Text('Day')),
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
                ButtonSegment(value: 'year', label: Text('Year')),
              ],
              selected: {_period},
              onSelectionChanged: (s) {
                setState(() => _period = s.first);
                _generate();
              },
            ),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month, size: 18),
              label: Text(_rangeLabel(start, end)),
            ),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('All drivers')),
                ButtonSegment(value: 'driver', label: Text('One driver')),
              ],
              selected: {_scope},
              onSelectionChanged: (s) {
                setState(() => _scope = s.first);
                _generate();
              },
            ),
            if (_scope == 'driver')
              DropdownMenu<String>(
                width: 260,
                enableFilter: true,
                requestFocusOnTap: true,
                label: const Text('Choose a driver'),
                initialSelection: _driverId,
                dropdownMenuEntries: [
                  for (final d in _drivers)
                    DropdownMenuEntry(
                      value: d.id,
                      label: d.plate.isEmpty ? d.name : '${d.name} (${d.plate})',
                    ),
                ],
                onSelected: (v) {
                  setState(() => _driverId = v);
                  _generate();
                },
              ),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _preparedBy,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  // Letters, spaces, periods and dashes only (no numbers), always shown in capitals.
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-zÑñ .\-]')),
                  TextInputFormatter.withFunction(
                    (oldValue, newValue) => newValue.copyWith(text: newValue.text.toUpperCase()),
                  ),
                ],
                decoration: const InputDecoration(
                  labelText: 'Prepared by (name)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
              onPressed: (_loading || r == null) ? null : _print,
              icon: const Icon(Icons.print, size: 18),
              label: const Text('Print'),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _generate,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          )
        else if (r == null)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Center(
              child: Text('Choose a driver to see the report.', style: TextStyle(color: Colors.grey.shade700)),
            ),
          )
        else ...[
          const SizedBox(height: 16),
          Text(
            isDriver ? '${r.title} - ${r.driver!.name} - ${r.rangeLabel}' : '${r.title} - ${r.rangeLabel}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          if (isDriver)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Plate: ${r.driver!.plate.isEmpty ? '-' : r.driver!.plate}    MTOP: ${r.driver!.mtop.isEmpty ? '-' : r.driver!.mtop}',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _card(isDriver ? 'Rides accepted' : 'Ride requests', '${r.total}', Icons.list_alt, Colors.blue.shade800,
                  sub: _delta(r.total, r.prevTotal)),
              _card('Completed', '${r.completed}', Icons.check_circle, _green, sub: _pct(r.completionRate)),
              _card('Cancelled', '${r.cancelled}', Icons.cancel, Colors.red.shade700),
              _card('Total fare', _money(r.fareTotal), Icons.payments, Colors.orange.shade800,
                  sub: _delta(r.fareTotal, r.prevFare)),
              _card('Average fare', _money(r.avgFare), Icons.trending_up, Colors.teal.shade700),
              _card('Commission earned', _money(r.commissionEarned), Icons.account_balance_wallet, _green),
            ],
          ),
          _section(
            isDriver ? 'Rides of this driver' : 'Rides',
            _ridesList(r),
          ),
          _section(
            'Totals',
            Column(children: [
              _kv('Completed', '${r.completed}'),
              _kv('Cancelled', '${r.cancelled}  (passenger ${r.cancelledByPassenger}, driver ${r.cancelledByDriver})'),
              if (!isDriver) _kv('Expired (no driver found)', '${r.expired}'),
              _kv('No-show', '${r.noShow}'),
              _kv('Still active / open', '${r.active}'),
              if (isDriver) _kv('Offers declined', '${r.declined}'),
              const Divider(),
              _kv('Regular rides', '${r.regular}'),
              _kv('Arkila rides', '${r.arkila}'),
              _kv('Negotiated fares', '${r.negotiated}'),
            ]),
          ),
          _section(
            'Commission',
            Column(children: [
              _kv('Earned from completed rides', _money(r.commissionEarned)),
              if (r.recTotalEarned != null) ...[
                _kv('Recorded for the period', _money(r.recTotalEarned!)),
                _kv('Paid', _money(r.recPaid ?? 0)),
                _kv('Unpaid balance', _money(r.recBalance ?? 0)),
                _kv('Receipts waiting for review', '${r.recPendingReview ?? 0}'),
              ] else
                Text('Payment details could not be loaded.', style: TextStyle(color: Colors.grey.shade600)),
            ]),
          ),
          _section('Top pickup places', _rank(r.topPickups)),
          _section('Top drop-off places', _rank(r.topDropoffs)),
          _section('Requests by hour of day (Philippine time)', _hoursChart(r)),
          _section(
            isDriver ? 'Safety' : 'Users and safety',
            Column(children: [
              if (!isDriver) ...[
                _kv('New passengers registered', '${r.newPassengers}'),
                _kv('New drivers registered', '${r.newDrivers}'),
              ],
              _kv('No-shows', '${r.noShow}'),
              _kv('Completed far from the drop-off', '${r.farFromDropoff}'),
            ]),
          ),
        ],
      ],
    );
  }
}