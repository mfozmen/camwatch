import 'dart:async';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'credential_store.dart';

import 'player.dart';
import 'player_page.dart';
import 'report_page.dart';
import 'status_message.dart';

const _portNames = {
  21: 'FTP',
  23: 'Telnet',
  80: 'HTTP',
  443: 'HTTPS',
  554: 'RTSP',
  8000: 'SDK',
  8080: 'HTTP',
  8554: 'RTSP',
};

/// A port number as a person reads it on a card: "RTSP 554".
String portLabel(int port) => '${_portNames[port] ?? 'Port'} $port';

enum _Phase { idle, scanning, noNetwork, failed, done }

/// The first screen: one button that scans the local network and the
/// devices it found. [scan] resolves to null when there is no LAN; a tap on
/// a device with RTSP opens it in a fresh player from [newPlayer].
class ScanPage extends StatefulWidget {
  const ScanPage({
    super.key,
    required this.scan,
    required this.newPlayer,
    required this.findPaths,
    required this.store,
  });

  final Future<List<Device>?> Function() scan;
  final StreamPlayer Function() newPlayer;
  final FindPaths findPaths;
  final CredentialStore store;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  var _phase = _Phase.idle;
  var _devices = const <Device>[];
  var _streams = <String, Map<String, PathStatus>>{};

  Future<void> _scan() async {
    setState(() => _phase = _Phase.scanning);
    try {
      final devices = await widget.scan();
      if (!mounted) return;
      setState(() {
        _devices = devices ?? const [];
        _streams = {};
        _phase = devices == null ? _Phase.noNetwork : _Phase.done;
      });
      for (final device in _devices) {
        if (device.rtspPort != null) unawaited(_checkStream(device));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _checkStream(Device device) async {
    final scan = _devices;
    Map<String, PathStatus> streams;
    try {
      streams = await widget.findPaths(device.address, device.rtspPort!);
    } catch (_) {
      streams = const {};
    }
    if (!mounted || !identical(scan, _devices)) return;
    setState(() => _streams[device.address] = streams);
  }

  void _watch(Device device) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerPage(
        device: device,
        player: widget.newPlayer(),
        findPaths: widget.findPaths,
        store: widget.store,
      ),
    ),
  );

  void _report(Device device) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReportPage(
        device: device,
        streams: _streams[device.address],
        onWatch: device.rtspPort == null ? null : () => _watch(device),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scanning = _phase == _Phase.scanning;
    return Scaffold(
      appBar: AppBar(title: const Text('camwatch')),
      body: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600), child: _body()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: scanning ? null : _scan,
        icon: scanning
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.radar),
        label: Text(switch (_phase) {
          _Phase.idle => 'Scan network',
          _Phase.scanning => 'Scanning…',
          _ => 'Scan again',
        }),
      ),
    );
  }

  Widget _body() => switch (_phase) {
    _Phase.idle => const StatusMessage(
      icon: Icons.videocam_outlined,
      title: 'Find the cameras on your network',
      body: 'camwatch scans your local network only. Nothing leaves your device.',
    ),
    _Phase.scanning => const StatusMessage(
      icon: Icons.radar,
      title: 'Scanning your network',
      body: 'Probing every address on your subnet. This takes a few seconds.',
    ),
    _Phase.noNetwork => const StatusMessage(
      icon: Icons.wifi_off,
      title: 'Not on a local network',
      body: 'Join a Wi-Fi or Ethernet network and scan again.',
    ),
    _Phase.failed => StatusMessage(
      icon: Icons.error_outline,
      iconColor: Theme.of(context).colorScheme.error,
      title: 'The scan failed',
      body: 'Check the connection and try again.',
    ),
    _Phase.done when _devices.isEmpty => const StatusMessage(
      icon: Icons.search_off,
      title: 'No devices found',
      body:
          'Cameras on another subnet or behind a VPN are out of reach. '
          "Scan again from the camera's own network.",
    ),
    _Phase.done => _DeviceList(_devices, streams: _streams, onReport: _report, onWatch: _watch),
  };
}

class _DeviceList extends StatelessWidget {
  const _DeviceList(
    this.devices, {
    required this.streams,
    required this.onReport,
    required this.onWatch,
  });

  final List<Device> devices;
  final Map<String, Map<String, PathStatus>> streams;
  final void Function(Device) onReport;
  final void Function(Device) onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final count = devices.length;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: count + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              '$count ${count == 1 ? 'device' : 'devices'} found',
              style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          );
        }
        final device = devices[index - 1];
        return _DeviceCard(
          device,
          streams: device.rtspPort == null ? const {} : streams[device.address],
          onReport: () => onReport(device),
          onWatch: () => onWatch(device),
        );
      },
    );
  }
}

/// One device: its grade, address and ports; [streams] is null while the
/// stream check is still running.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard(
    this.device, {
    required this.streams,
    required this.onReport,
    required this.onWatch,
  });

  final Device device;
  final Map<String, PathStatus>? streams;
  final VoidCallback onReport;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final playable = device.rtspPort != null;
    final checking = streams == null;
    final found = findings(device, streams ?? const {});
    final grade = checking ? null : gradeOf(found);
    final color = grade?.color(colors) ?? colors.onSurfaceVariant;
    final count = found.length;
    final status = switch (grade) {
      null => 'Checking stream…',
      Grade.green => grade.label,
      _ => '${grade.label} · $count ${count == 1 ? 'finding' : 'findings'}',
    };
    return MergeSemantics(
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onReport,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  foregroundColor: color,
                  child: Icon(grade?.icon ?? Icons.videocam_outlined),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              device.address,
                              style: text.titleMedium?.copyWith(
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          if (device.onvifAddress != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.tertiaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'ONVIF',
                                style: text.labelMedium?.copyWith(
                                  color: colors.onTertiaryContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        device.openPorts.map(portLabel).join(' · '),
                        style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(status, style: text.labelMedium?.copyWith(color: color)),
                    ],
                  ),
                ),
                if (playable)
                  IconButton(
                    onPressed: onWatch,
                    tooltip: 'Watch',
                    icon: Icon(Icons.play_circle_outline, color: colors.primary),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'No stream',
                      style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
