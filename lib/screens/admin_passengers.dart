import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/animated_press.dart';

class AdminPassengersScreen extends StatefulWidget {
  const AdminPassengersScreen({super.key});

  @override
  State<AdminPassengersScreen> createState() => _AdminPassengersScreenState();
}

class _AdminPassengersScreenState extends State<AdminPassengersScreen> {
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final Stream<QuerySnapshot> _passengersStream =
      FirebaseFirestore.instance.collection('passengers').snapshots();

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

  Future<void> _toggleSuspend(BuildContext context, String passengerId, bool suspend) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(suspend ? 'Suspend Passenger' : 'Reactivate Passenger'),
        content: Text(
          suspend
              ? 'This passenger will be blocked from logging in and requesting rides. Continue?'
              : 'This passenger will be able to log in again. Continue?',
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

    await FirebaseFirestore.instance.collection('passengers').doc(passengerId).update({
      'accountStatus': suspend ? 'suspended' : 'active',
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search by name or phone',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _passengersStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Could not load passengers: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState('No passengers found');
                }

                final query = _searchQuery.trim().toLowerCase();
                final passengers = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['fullName'] ?? '').toString().toLowerCase();
                  final phone = (data['phoneNumber'] ?? '').toString().toLowerCase();
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  return name.contains(query) || phone.contains(query) || email.contains(query);
                }).toList();

                if (passengers.isEmpty) return _buildEmptyState('No matching passengers');

                return Scrollbar(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            query.isEmpty
                                ? 'Total passengers: ${passengers.length}'
                                : 'Showing ${passengers.length} of ${snapshot.data!.docs.length} passengers',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B5E20)),
                          ),
                        ),
                        SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('#')),
                          DataColumn(label: Text('Name')),
                          DataColumn(label: Text('Phone')),
                          DataColumn(label: Text('Email')),
                          DataColumn(label: Text('Address')),
                          DataColumn(label: Text('Cancel / No-Show')),
                          DataColumn(label: Text('Account')),
                          DataColumn(label: Text('Action')),
                        ],
                        rows: passengers.asMap().entries.map((entry) {
                          final doc = entry.value;
                          final data = doc.data() as Map<String, dynamic>;
                          final isSuspended = data['accountStatus'] == 'suspended';
                          final cancels = (data['cancelCount'] ?? 0) as num;

                          return DataRow(key: ValueKey(doc.id), cells: [
                            DataCell(Text('${entry.key + 1}')),
                            DataCell(Text('${data['fullName'] ?? '-'}')),
                            DataCell(Text('${data['phoneNumber'] ?? '-'}')),
                            DataCell(Text((data['email'] ?? '').toString().isEmpty ? '-' : '${data['email']}')),
                            DataCell(Text('${data['address'] ?? '-'}')),
                            DataCell(Text(
                              '$cancels',
                              style: TextStyle(
                                fontWeight: cancels >= 3 ? FontWeight.bold : FontWeight.normal,
                                color: cancels >= 3 ? Colors.red : null,
                              ),
                            )),
                            DataCell(Text(isSuspended ? 'Suspended' : 'Active')),
                            DataCell(
                              AnimatedPress(
                                onTap: () => _toggleSuspend(context, doc.id, !isSuspended),
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: isSuspended ? Colors.green : Colors.red,
                                  ),
                                  onPressed: () {},
                                  child: Text(isSuspended ? 'Reactivate' : 'Suspend'),
                                ),
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}