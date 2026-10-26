import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'scan_page.dart';

/// How a [Grade] reads and looks: a word and an icon shape next to the
/// colour, so colour is never the only cue.
extension GradeLook on Grade {
  String get label => switch (this) {
    Grade.red => 'Exposed',
    Grade.amber => 'At risk',
    Grade.green => 'No issues found',
  };

  String get meaning => switch (this) {
    Grade.red => 'Anyone on your network can get in. Fix the red items first.',
    Grade.amber => 'Easier to break into than it needs to be.',
    Grade.green => 'Nothing to fix on its open ports and stream.',
  };

  IconData get icon => switch (this) {
    Grade.red => Icons.gpp_bad_outlined,
    Grade.amber => Icons.gpp_maybe_outlined,
    Grade.green => Icons.gpp_good_outlined,
  };

  Color color(ColorScheme colors) => switch (this) {
    Grade.red => colors.error,
    Grade.amber =>
      colors.brightness == Brightness.dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
    Grade.green => colors.primary,
  };
}

/// One device's grade and the findings behind it; [streams] is null while
/// the stream check is still running. [onWatch] opens the player, absent
/// for a device without RTSP.
class ReportPage extends StatelessWidget {
  const ReportPage({super.key, required this.device, required this.streams, this.onWatch});

  final Device device;
  final Map<String, PathStatus>? streams;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final found = findings(device, streams ?? const {});
    if (streams == null) found.remove(uncheckedStream);
    final grade = gradeOf(found);
    final color = grade.color(colors);
    return Scaffold(
      appBar: AppBar(title: Text(device.address)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(grade.icon, size: 64, color: color),
                    const SizedBox(height: 16),
                    Text(grade.label, style: text.headlineSmall, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      grade.meaning,
                      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Open ports: ${device.openPorts.map(portLabel).join(' · ')}',
                      style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    if (streams == null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Checking the stream…',
                        style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              for (final finding in found)
                Card(
                  margin: const EdgeInsets.only(top: 8),
                  child: ListTile(
                    leading: Icon(finding.grade.icon, color: finding.grade.color(colors)),
                    title: Text(finding.title),
                    subtitle: Text(finding.advice),
                    isThreeLine: true,
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: onWatch == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onWatch,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Watch'),
            ),
    );
  }
}
