import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/foundation.dart';
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
    Grade.green => 'Nothing to fix among what camwatch checked.',
  };

  IconData get icon => switch (this) {
    Grade.red => Icons.gpp_bad_outlined,
    Grade.amber => Icons.gpp_maybe_outlined,
    Grade.green => Icons.gpp_good_outlined,
  };

  /// Amber and green are not theme roles; both pairs pass AA on the card
  /// surfaces of their theme, and green is not the action colour.
  Color color(ColorScheme colors) {
    final dark = colors.brightness == Brightness.dark;
    return switch (this) {
      Grade.red => colors.error,
      Grade.amber => dark ? const Color(0xFFFBBF24) : const Color(0xFF92400E),
      Grade.green => dark ? const Color(0xFF81C995) : const Color(0xFF1B5E20),
    };
  }
}

/// The grade line of a device, or the checking state while [streams] is null.
({IconData icon, String label, Color color, List<Finding> found}) gradeLine(
  Device device,
  Map<String, PathStatus>? streams,
  ColorScheme colors,
) {
  final found = findings(device, streams ?? const {});
  if (streams == null) {
    found.remove(uncheckedStream);
    return (
      icon: Icons.videocam_outlined,
      label: 'Checking stream…',
      color: colors.onSurfaceVariant,
      found: found,
    );
  }
  final grade = gradeOf(found);
  final count = found.length;
  final noun = count == 1 ? 'finding' : 'findings';
  final label = grade == Grade.green ? grade.label : '${grade.label} · $count $noun';
  return (icon: grade.icon, label: label, color: grade.color(colors), found: found);
}

/// One device's grade and the findings behind it, following [streams] as
/// the stream check completes. [onWatch] opens the player, absent for a
/// device without RTSP.
class ReportPage extends StatelessWidget {
  const ReportPage({super.key, required this.device, required this.streams, this.onWatch});

  final Device device;
  final ValueListenable<Map<String, PathStatus>?> streams;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(device.address)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ValueListenableBuilder(
            valueListenable: streams,
            builder: (context, streams, _) => Column(
              children: [
                if (streams == null) const LinearProgressIndicator(),
                Expanded(child: _Report(device, streams)),
              ],
            ),
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

class _Report extends StatelessWidget {
  const _Report(this.device, this.streams);

  final Device device;
  final Map<String, PathStatus>? streams;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final line = gradeLine(device, streams, colors);
    final grade = streams == null ? null : gradeOf(line.found);
    final meaning =
        grade?.meaning ??
        'camwatch is trying the common stream paths. The grade follows in a moment.';
    final secondary = text.bodyMedium?.copyWith(color: colors.onSurfaceVariant);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(line.icon, size: 64, color: line.color),
              const SizedBox(height: 16),
              Text(
                grade?.label ?? line.label,
                style: text.headlineMedium?.copyWith(color: line.color),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(meaning, style: secondary, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Text(
                'Open ports: ${device.openPorts.map(portLabel).join(' · ')}',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              if (grade == Grade.green) ...[
                const SizedBox(height: 16),
                Text(
                  'Grades are only as current as the last scan. Scan again after a '
                  'firmware update or a settings change.',
                  style: secondary,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        for (final finding in line.found)
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
    );
  }
}
