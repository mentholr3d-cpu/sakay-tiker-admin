import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});

  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  bool _showRideFeedback = true;

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

  Widget _buildRideFeedback() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ride_feedback')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('No ride feedback yet');
        }

        final feedbacks = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: feedbacks.length,
          itemBuilder: (context, index) {
            final data = feedbacks[index].data() as Map<String, dynamic>;
            final rating = (data['rating'] ?? 0) as int;
            final createdAt = data['createdAt'] as Timestamp?;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Driver: ${data['driverName'] ?? 'Unknown'}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        Row(
                          children: List.generate(5, (i) {
                            return Icon(
                              i < rating ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 18,
                            );
                          }),
                        ),
                      ],
                    ),
                    if ((data['comment'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(data['comment']),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      createdAt != null ? createdAt.toDate().toString().substring(0, 16) : '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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

  Widget _buildAppFeedback() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_feedback')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState('No app feedback yet');
        }

        final feedbacks = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: feedbacks.length,
          itemBuilder: (context, index) {
            final data = feedbacks[index].data() as Map<String, dynamic>;
            final createdAt = data['createdAt'] as Timestamp?;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data['comment'] ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      createdAt != null ? createdAt.toDate().toString().substring(0, 16) : '',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Ride Feedback')),
              ButtonSegment(value: false, label: Text('App Feedback')),
            ],
            selected: {_showRideFeedback},
            onSelectionChanged: (newSelection) {
              setState(() => _showRideFeedback = newSelection.first);
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _showRideFeedback ? _buildRideFeedback() : _buildAppFeedback(),
        ),
      ],
    );
  }
}