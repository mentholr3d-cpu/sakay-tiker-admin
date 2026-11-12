import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'commission_period.dart';

/// Admin > Reports: day / week / month / year summaries with a PDF download.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _ReportData {
  final String title;
  final String rangeLabel;
  final DateTime generatedAt; // Manila time
  // Rides
  int total = 0, completed = 0, cancelled = 0, expired = 0, noShow = 0, active = 0;
  int regular = 0, arkila = 0, negotiated = 0;
  double fareTotal = 0, commissionEarned = 0;
  // Rankings
  List<MapEntry<String, int>> topPickups = [];
  List<MapEntry<String, int>> topDropoffs = [];
  List<MapEntry<String, int>> topDrivers = [];
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

  _ReportData(this.title, this.rangeLabel, this.generatedAt);

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

  String _period = 'day'; // day | week | month | year
  late DateTime _anchor; // Manila calendar date (y/m/d only)
  final _preparedBy = TextEditingController(text: 'Administrator');

  bool _loading = false;
  String? _error;
  _ReportData? _report;

  @override
  void initState() {
    super.initState();
    final m = _manilaNow();
    _anchor = DateTime(m.year, m.month, m.day);
    _generate();
  }

  @override
  void dispose() {
    _preparedBy.dispose();
    super.dispose();
  }

  // ---------- time helpers (Philippine time, UTC+8) ----------
  DateTime _manilaNow() => DateTime.now().toUtc().add(const Duration(hours: 8));
  DateTime _toManila(Timestamp t) => t.toDate().toUtc().add(const Duration(hours: 8));
  // Manila wall-clock date -> the real instant (as UTC) used for queries.
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
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor.isAfter(DateTime(now.year, now.month, now.day))
          ? DateTime(now.year, now.month, now.day)
          : _anchor,
      firstDate: DateTime(2024),
      lastDate: DateTime(now.year, now.month, now.day),
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

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = _startFor(_anchor);
      final end = _endFor(start);
      final r = _ReportData('$_periodName Report', _rangeLabel(start, end), _manilaNow());

      final docs = await _ridesBetween(start, end);
      final pickups = <String, int>{};
      final dropoffs = <String, int>{};
      final drivers = <String, int>{};

      for (final d in docs) {
        final x = d.data();
        r.total++;
        final status = x['status'];
        switch (status) {
          case 'completed':
            r.completed++;
            r.fareTotal += ((x['fare'] ?? 0) as num).toDouble();
            r.commissionEarned += ((x['commissionAmount'] ?? 0) as num).toDouble();
            final dn = (x['driverName'] ?? 'Unknown').toString();
            drivers[dn] = (drivers[dn] ?? 0) + 1;
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
        if (c is Timestamp) r.hours[_toManila(c).hour]++;
      }
      r.topPickups = _top(pickups);
      r.topDropoffs = _top(dropoffs);
      r.topDrivers = _top(drivers);

      // Previous period (for the comparison line).
      final ps = _prevStart(start);
      final prevDocs = await _ridesBetween(ps, start);
      for (final d in prevDocs) {
        final x = d.data();
        r.prevTotal++;
        if (x['status'] == 'completed') {
          r.prevCompleted++;
          r.prevFare += ((x['fare'] ?? 0) as num).toDouble();
        }
      }

      r.newPassengers = await _countUsers('passengers', start, end);
      r.newDrivers = await _countUsers('drivers', start, end);

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
        // Leave null: the section then shows only the commission earned from rides.
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

  List<MapEntry<String, int>> _peakHours(_ReportData r) {
    final list = <MapEntry<String, int>>[];
    for (var h = 0; h < 24; h++) {
      if (r.hours[h] > 0) list.add(MapEntry(_hourLabel(h), r.hours[h]));
    }
    list.sort((a, b) => b.value.compareTo(a.value));
    return list.take(3).toList();
  }

  // ---------- PDF ----------
  Future<void> _downloadPdf() async {
    final r = _report;
    if (r == null) return;
    final doc = pw.Document();
    final green = PdfColor.fromInt(0xFF1B5E20);
    final grey = PdfColors.grey700;
    String pm(double v) => _money(v, sign: 'PHP ');

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: green)),
        );

    pw.Widget table(List<String> head, List<List<String>> rows) => pw.TableHelper.fromTextArray(
          headers: head,
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
          headerDecoration: pw.BoxDecoration(color: green),
          cellStyle: const pw.TextStyle(fontSize: 10),
          cellAlignments: {for (var i = 1; i < head.length; i++) i: pw.Alignment.centerRight},
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        );

    List<List<String>> rank(List<MapEntry<String, int>> l) =>
        l.isEmpty ? [['No data', '-']] : [for (final e in l) [e.key, '${e.value}']];

    final peaks = _peakHours(r);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: grey)),
        ),
        build: (ctx) => [
          pw.Text('Sakay Tiker', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: green)),
          pw.Text('A Ride-Hailing App of Bontoc, Mountain Province', style: pw.TextStyle(fontSize: 10, color: grey)),
          pw.SizedBox(height: 10),
          pw.Divider(color: green, thickness: 1.5),
          pw.Text(r.title, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
          pw.Text('Period: ${r.rangeLabel}', style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
            'Generated: ${_fmtDate(r.generatedAt)}, ${r.generatedAt.hour % 12 == 0 ? 12 : r.generatedAt.hour % 12}:${r.generatedAt.minute.toString().padLeft(2, '0')} ${r.generatedAt.hour >= 12 ? 'PM' : 'AM'} (Philippine time)',
            style: pw.TextStyle(fontSize: 9, color: grey),
          ),
          pw.Text('Prepared by: ${_preparedBy.text.trim().isEmpty ? 'Administrator' : _preparedBy.text.trim()}',
              style: pw.TextStyle(fontSize: 9, color: grey)),
          heading('1. Ride summary'),
          table(['Measure', 'Value'], [
            ['Total ride requests', '${r.total}  (${_delta(r.total, r.prevTotal)})'],
            ['Completed', '${r.completed}  (${_delta(r.completed, r.prevCompleted)})'],
            ['Cancelled', '${r.cancelled}'],
            ['Expired (no driver)', '${r.expired}'],
            ['No-show', '${r.noShow}'],
            ['Still active / open', '${r.active}'],
            ['Completion rate', _pct(r.completionRate)],
            ['Regular rides', '${r.regular}'],
            ['Arkila rides', '${r.arkila}'],
            ['Negotiated fares', '${r.negotiated}'],
          ]),
          heading('2. Fares'),
          table(['Measure', 'Value'], [
            ['Total fare of completed rides', '${pm(r.fareTotal)}  (${_delta(r.fareTotal, r.prevFare)})'],
            ['Average fare per completed ride', pm(r.avgFare)],
          ]),
          heading('3. Commission'),
          table(['Measure', 'Value'], [
            ['Commission earned from completed rides', pm(r.commissionEarned)],
            if (r.recTotalEarned != null) ...[
              ['Commission recorded for the period', pm(r.recTotalEarned!)],
              ['Paid by drivers', pm(r.recPaid ?? 0)],
              ['Unpaid balance', pm(r.recBalance ?? 0)],
              ['Receipts waiting for review', '${r.recPendingReview ?? 0}'],
            ],
          ]),
          heading('4. Busiest places and times'),
          pw.Text('Top pickup places', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          table(['Place', 'Rides'], rank(r.topPickups)),
          pw.SizedBox(height: 8),
          pw.Text('Top dropoff places', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          table(['Place', 'Rides'], rank(r.topDropoffs)),
          pw.SizedBox(height: 8),
          pw.Text('Peak request hours', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          table(['Hour', 'Requests'], rank(peaks)),
          heading('5. Top drivers (completed rides)'),
          table(['Driver', 'Completed rides'], rank(r.topDrivers)),
          heading('6. Users and safety'),
          table(['Measure', 'Value'], [
            ['New passengers registered', '${r.newPassengers}'],
            ['New drivers registered', '${r.newDrivers}'],
            ['Cancelled by passenger', '${r.cancelledByPassenger}'],
            ['Cancelled by driver', '${r.cancelledByDriver}'],
            ['No-shows', '${r.noShow}'],
            ['Completed far from the dropoff', '${r.farFromDropoff}'],
          ]),
        ],
      ),
    );

    final name = 'sakay_tiker_${_period}_report_${r.rangeLabel.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf';
    await Printing.sharePdf(bytes: await doc.save(), filename: name);
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

  @override
  Widget build(BuildContext context) {
    final r = _report;
    final start = _startFor(_anchor);
    final end = _endFor(start);

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
            SizedBox(
              width: 200,
              child: TextField(
                controller: _preparedBy,
                decoration: const InputDecoration(
                  labelText: 'Prepared by',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white),
              onPressed: (_loading || r == null) ? null : _downloadPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 18),
              label: const Text('Download PDF'),
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
        else if (r != null) ...[
          const SizedBox(height: 16),
          Text('${r.title} - ${r.rangeLabel}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _card('Ride requests', '${r.total}', Icons.list_alt, Colors.blue.shade800, sub: _delta(r.total, r.prevTotal)),
              _card('Completed', '${r.completed}', Icons.check_circle, _green, sub: _pct(r.completionRate)),
              _card('Cancelled', '${r.cancelled}', Icons.cancel, Colors.red.shade700),
              _card('Total fare', _money(r.fareTotal), Icons.payments, Colors.orange.shade800, sub: _delta(r.fareTotal, r.prevFare)),
              _card('Average fare', _money(r.avgFare), Icons.trending_up, Colors.teal.shade700),
              _card('Commission earned', _money(r.commissionEarned), Icons.account_balance_wallet, _green),
            ],
          ),
          _section(
            'Rides',
            Column(children: [
              _kv('Completed', '${r.completed}'),
              _kv('Cancelled', '${r.cancelled}  (passenger ${r.cancelledByPassenger}, driver ${r.cancelledByDriver})'),
              _kv('Expired (no driver)', '${r.expired}'),
              _kv('No-show', '${r.noShow}'),
              _kv('Still active / open', '${r.active}'),
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
                _kv('Paid by drivers', _money(r.recPaid ?? 0)),
                _kv('Unpaid balance', _money(r.recBalance ?? 0)),
                _kv('Receipts waiting for review', '${r.recPendingReview ?? 0}'),
              ] else
                Text('Payment details could not be loaded.', style: TextStyle(color: Colors.grey.shade600)),
            ]),
          ),
          _section('Top pickup places', _rank(r.topPickups)),
          _section('Top dropoff places', _rank(r.topDropoffs)),
          _section('Requests by hour of day (Philippine time)', _hoursChart(r)),
          _section('Top drivers (completed rides)', _rank(r.topDrivers)),
          _section(
            'Users and safety',
            Column(children: [
              _kv('New passengers registered', '${r.newPassengers}'),
              _kv('New drivers registered', '${r.newDrivers}'),
              _kv('No-shows', '${r.noShow}'),
              _kv('Completed far from the dropoff', '${r.farFromDropoff}'),
            ]),
          ),
        ],
      ],
    );
  }
}