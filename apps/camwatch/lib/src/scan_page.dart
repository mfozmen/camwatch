import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'player.dart';
import 'player_page.dart';
import 'status_message.dart';

const _portNames = {80: 'HTTP', 8080: 'HTTP', 554: 'RTSP', 8554: 'RTSP', 8000: 'SDK'};

/// A port number as a person reads it on a card: "RTSP 554".
String portLabel(int port) => '${_portNames[port] ?? 'Port'} $port';

enum _Phase { idle, scanning, noNetwork, failed, done }

/// The first screen: one button that scans the local network and the
/// devices it found. [scan] resolves to null when there is no LAN; a tap on
/// a device with RTSP opens it in a fresh player from [newPlayer].
class ScanPage extends StatefulWidget {
  const ScanPage({super.key, required this.scan, required this.newPlayer, required this.findPaths});

  final Future<List<Device>?> Function() scan;
  final StreamPlayer Function() newPlayer;
  final FindPaths findPaths;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  var _phase = _Phase.idle;
  var _devices = const <Device>[];

  Future<void> _scan() async {
    setState(() => _phase = _Phase.scanning);
    try {
      final devices = await widget.scan();
      if (!mounted) return;
      setState(() {
        _devices = devices ?? const [];
        _phase = devices == null ? _Phase.noNetwork : _Phase.done;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.failed);
    }
  }

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
    _Phase.done => _DeviceList(_devices, newPlayer: widget.newPlayer, findPaths: widget.findPaths),
  };
}

class _DeviceList extends StatelessWidget {
  const _DeviceList(this.devices, {required this.newPlayer, required this.findPaths});

  final List<Device> devices;
  final StreamPlayer Function() newPlayer;
  final FindPaths findPaths;

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
        return _DeviceCard(devices[index - 1], newPlayer: newPlayer, findPaths: findPaths);
      },
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard(this.device, {required this.newPlayer, required this.findPaths});

  final Device device;
  final StreamPlayer Function() newPlayer;
  final FindPaths findPaths;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final playable = device.rtspPort != null;
    return MergeSemantics(
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: playable
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PlayerPage(device: device, player: newPlayer(), findPaths: findPaths),
                  ),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.videocam_outlined),
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
                      const SizedBox(height: 8),
                      Text(
                        device.openPorts.map(portLabel).join(' · '),
                        style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: playable
                      ? Icon(
                          Icons.play_circle_outline,
                          color: colors.primary,
                          semanticLabel: 'Watch',
                        )
                      : Text(
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
