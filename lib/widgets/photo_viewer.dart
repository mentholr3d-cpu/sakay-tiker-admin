import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Pop-up that shows a photo from the internet. It shows a spinner while the
/// photo loads, a clear message if it cannot load, fits tall photos on the
/// screen, and lets the user pinch to zoom.
class PhotoDialog extends StatelessWidget {
  final String url;
  final String title;

  const PhotoDialog({super.key, required this.url, this.title = 'Photo'});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (context, error, stack) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'Could not load the photo. Please check your internet connection and try again.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Pinch to zoom', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A blue "View ..." link that opens the photo pop-up. Shows nothing when
/// there is no photo.
class PhotoLink extends StatelessWidget {
  final String? url;
  final String label;
  final String title;

  const PhotoLink({
    super.key,
    required this.url,
    required this.label,
    this.title = 'Photo',
  });

  @override
  Widget build(BuildContext context) {
    final link = url;
    if (link == null || link.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => PhotoDialog(url: link, title: title),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

/// The "View tricycle photo" link for a driver. Uses the photo saved on the
/// ride when there is one, otherwise looks it up on the driver's profile, so
/// the passenger can still see it.
class DriverTricyclePhotoLink extends StatefulWidget {
  final String? driverId;
  final String? rideUrl;

  const DriverTricyclePhotoLink({super.key, required this.driverId, required this.rideUrl});

  @override
  State<DriverTricyclePhotoLink> createState() => _DriverTricyclePhotoLinkState();
}

class _DriverTricyclePhotoLinkState extends State<DriverTricyclePhotoLink> {
  late Future<String?> _future = _resolve();

  @override
  void didUpdateWidget(covariant DriverTricyclePhotoLink oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverId != widget.driverId || oldWidget.rideUrl != widget.rideUrl) {
      _future = _resolve();
    }
  }

  Future<String?> _resolve() async {
    final fromRide = widget.rideUrl;
    if (fromRide != null && fromRide.isNotEmpty) return fromRide;

    final id = widget.driverId;
    if (id == null || id.isEmpty) return null;

    try {
      final doc = await FirebaseFirestore.instance.collection('drivers').doc(id).get();
      final value = doc.data()?['tricyclePhotoUrl'];
      if (value == null || value.toString().isEmpty) return null;
      return value.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        return PhotoLink(
          url: snapshot.data,
          label: '🛺 View tricycle photo',
          title: 'Tricycle photo',
        );
      },
    );
  }
}