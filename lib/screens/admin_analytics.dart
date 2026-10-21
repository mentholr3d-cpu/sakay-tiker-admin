import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'server_clock.dart';

class AdminAnalyticsScreen extends StatelessWidget {
  final void Function(int pageIndex, {int? driversSubTab, int? ridesSubTab})? onNavigate;

  const AdminAnalyticsScreen({super.key, this.onNavigate});

  List<DateTime> _lastSevenDays() {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return DateTime(d.year, d.month, d.day);
    });
  }

  String _dayLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  Widget _buildHeroBanner(int totalRides, double totalRevenue, int approvedDrivers) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final narrow = c.maxWidth < 560;
          final rides = _heroStat('$totalRides', 'Total Rides Facilitated', Icons.directions_car);
          final revenue = _heroStat('₱${totalRevenue.toStringAsFixed(0)}', 'Total Revenue Generated', Icons.trending_up);
          final drivers = _heroStat('$approvedDrivers', 'Verified Drivers', Icons.verified);
          final line = Colors.white.withValues(alpha: 0.25);
          if (narrow) {
            return Column(
              children: [
                rides,
                Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 12), color: line),
                revenue,
                Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 12), color: line),
                drivers,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: rides),
              Container(width: 1, height: 60, color: line),
              Expanded(child: revenue),
              Container(width: 1, height: 60, color: line),
              Expanded(child: drivers),
            ],
          );
        },
      ),
    );
  }

  Widget _heroStat(String value, String label, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white.withValues(alpha: 0.85), size: 22),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12.5),
        ),
      ],
    );
  }

  Widget _buildRidesChart(List<QueryDocumentSnapshot> rides) {
    final days = _lastSevenDays();
    final counts = <int>[];

    for (final day in days) {
      final nextDay = day.add(const Duration(days: 1));
      int count = 0;
      for (final doc in rides) {
        final data = doc.data() as Map<String, dynamic>;
        final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
        if (createdAt != null && !createdAt.isBefore(day) && createdAt.isBefore(nextDay)) {
          count++;
        }
      }
      counts.add(count);
    }

    final maxCount = counts.isEmpty ? 1 : counts.reduce((a, b) => a > b ? a : b);
    final chartMax = (maxCount < 5 ? 5 : maxCount).toDouble() * 1.2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B5E20).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.trending_up, color: Color(0xFF1B5E20), size: 20),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Rides — Last 7 Days',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: chartMax,
                  alignment: BarChartAlignment.spaceAround,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: chartMax / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: const Color(0xFF1B5E20).withValues(alpha: 0.08),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (value == meta.max) return const SizedBox.shrink();
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= days.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              _dayLabel(days[index]),
                              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: List.generate(days.length, (i) {
                    final isToday = i == days.length - 1;
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: counts[i].toDouble(),
                          color: isToday ? const Color(0xFF1B5E20) : const Color(0xFF6FA37A),
                          width: 26,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      // Re-check every 30 seconds which drivers are still active.
      stream: Stream.periodic(const Duration(seconds: 30), (i) => i),
      builder: (context, _) {
        return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('rides').snapshots(),
      builder: (context, ridesSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('drivers').snapshots(),
          builder: (context, driversSnapshot) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('passengers').snapshots(),
              builder: (context, passengersSnapshot) {
                if (ridesSnapshot.hasError || driversSnapshot.hasError || passengersSnapshot.hasError) {
                  return Center(
                    child: Text('Could not load data: ${ridesSnapshot.error ?? driversSnapshot.error ?? passengersSnapshot.error}'),
                  );
                }

                if (!ridesSnapshot.hasData || !driversSnapshot.hasData || !passengersSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rides = ridesSnapshot.data!.docs;
                final drivers = driversSnapshot.data!.docs;
                final passengers = passengersSnapshot.data!.docs;

                final now = DateTime.now();
                final todayStart = DateTime(now.year, now.month, now.day);

                int todayRides = 0;
                int completedRides = 0;
                int pendingRides = 0;
                double totalRevenue = 0;
                double totalCommission = 0;

                for (final doc in rides) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] ?? '';
                  final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

                  if (createdAt != null && createdAt.isAfter(todayStart)) todayRides++;
                  if (status == 'completed') {
                    completedRides++;
                    totalRevenue += ((data['fare'] ?? 0) as num).toDouble();
                    totalCommission += ((data['commissionAmount'] ?? 0) as num).toDouble();
                  }
                  if (status == 'pending') {
                    // Requests nobody accepted within 15 minutes are expired.
                    final stale = createdAt != null && now.difference(createdAt).inMinutes >= 15;
                    if (!stale) pendingRides++;
                  }
                }

                final approvedDrivers = drivers.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'approved').length;
                final pendingDrivers = drivers.where((d) => (d.data() as Map<String, dynamic>)['status'] == 'pending').length;
                // A driver counts as online only if marked online AND active in the last 3 minutes.
                final nowTime = ServerClock.now();
                final onlineDrivers = drivers.where((d) {
                  final driverData = d.data() as Map<String, dynamic>;
                  if (driverData['isOnline'] != true) return false;
                  final lastActive = driverData['lastActiveAt'];
                  return lastActive is Timestamp &&
                      nowTime.difference(lastActive.toDate()).inSeconds <= 180;
                }).length;

                // Page indexes: 0 Overview, 1 Drivers, 2 Passengers, 3 Rides, 4 Feedback
                final stats = [
                  _StatData('Rides Today', '$todayRides', Icons.today_outlined,
                      onTap: () => onNavigate?.call(3, ridesSubTab: 1)),
                  _StatData('Completed Rides', '$completedRides', Icons.check_circle_outline,
                      onTap: () => onNavigate?.call(3, ridesSubTab: 1)),
                  _StatData('Waiting for Driver', '$pendingRides', Icons.hourglass_empty,
                      onTap: () => onNavigate?.call(3, ridesSubTab: 0)),
                  _StatData('Total Commission', '₱${totalCommission.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined,
                      onTap: () => onNavigate?.call(1, driversSubTab: 2)),
                  _StatData('Pending Applications', '$pendingDrivers', Icons.pending_actions_outlined,
                      onTap: () => onNavigate?.call(1, driversSubTab: 0)),
                  _StatData('Drivers Online Now', '$onlineDrivers', Icons.wifi_tethering,
                      onTap: () => onNavigate?.call(1, driversSubTab: 1)),
                  _StatData('Total Passengers', '${passengers.length}', Icons.people_outline,
                      onTap: () => onNavigate?.call(2)),
                ];

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroBanner(rides.length, totalRevenue, approvedDrivers),
                      const SizedBox(height: 20),
                      _buildRidesChart(rides),
                      const SizedBox(height: 20),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 1.5,
                        ),
                        itemCount: stats.length,
                        itemBuilder: (context, index) {
                          final stat = stats[index];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: stat.onTap,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDDEEDF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: const Border(
                                    left: BorderSide(color: Color(0xFF1B5E20), width: 5),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1B5E20).withValues(alpha: 0.1),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(stat.icon, color: const Color(0xFF1B5E20), size: 24),
                                    const Spacer(),
                                    Text(
                                      stat.value,
                                      style: const TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1B5E20),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      stat.label,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF3D5C46), fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
            );  
          },
        );
      },
    );
      },
    );
  }
}

class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  _StatData(this.label, this.value, this.icon, {this.onTap});
}