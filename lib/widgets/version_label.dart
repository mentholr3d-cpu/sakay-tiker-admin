import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Small grey "Sakay Tiker v1.1.0 (build 2)" text. The numbers come from the
/// `version:` line in pubspec.yaml, so bump it there for every new release.
class VersionLabel extends StatefulWidget {
  final String prefix;

  const VersionLabel({super.key, this.prefix = 'Sakay Tiker'});

  @override
  State<VersionLabel> createState() => _VersionLabelState();
}

class _VersionLabelState extends State<VersionLabel> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final info = snapshot.data!;
        return Center(
          child: Text(
            '${widget.prefix} v${info.version} (build ${info.buildNumber})',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        );
      },
    );
  }
}