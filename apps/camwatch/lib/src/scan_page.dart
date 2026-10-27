import 'dart:async';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'camera_store.dart';
import 'consent_store.dart';
import 'credential_store.dart';
import 'live_tile.dart';
import 'name_dialog.dart';

import 'player.dart';
import 'player_page.dart';
import 'report_page.dart';
import 'status_message.dart';

const _portNames = {
  21: 'FTP',
  22: 'SSH',
  23: 'Telnet',
  80: 'HTTP',
  443: 'HTTPS',
  554: 'RTSP',
  8000: 'SDK',
  8080: 'HTTP',
  8554: 'RTSP',
  34567: 'XMeye',
  37777: 'Dahua',
};

/// A port number as a person reads it on a card: "RTSP 554".
String portLabel(int port) => '${_portNames[port] ?? 'Port'} $port';

enum _Phase { idle, scanning, noNetwork, failed, done }

/// The first screen: one button that scans the local network and the
/// devices it found, or a live grid of the cameras kept in [saved] until
/// then; the grid streams only while this screen is in front. [scan]
/// resolves to null when there is no LAN; a tap on a device with RTSP opens
/// it in a fresh player from [newPlayer]. Nothing is probed until the notice
/// in [consent] has been accepted once.
class ScanPage extends StatefulWidget {
  const ScanPage({
    super.key,
    required this.scan,
    required this.newPlayer,
    required this.findPaths,
    required this.store,
    required this.consent,
    required this.saved,
    this.actions = const [],
  });

  final Future<List<Device>?> Function() scan;
  final StreamPlayer Function() newPlayer;
  final FindPaths findPaths;
  final CredentialStore store;
  final ConsentStore consent;
  final CameraStore saved;
  final List<Widget> actions;

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  var _phase = _Phase.idle;
  var _devices = const <Device>[];
  var _streams = <String, ValueNotifier<Map<String, PathStatus>?>>{};
  var _asking = false;
  var _saved = const <SavedCamera>[];
  var _resumed = true;
  var _watching = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.saved.read().then((cameras) {
      if (mounted) setState(() => _saved = cameras);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Inactive is "visible, not the front window" on desktop: the grid stays live there.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _resumed = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    });
  }

  /// Keeps [cameras] as the saved list; a store that cannot write changes nothing.
  Future<void> _keep(List<SavedCamera> cameras) async {
    try {
      await widget.saved.write(cameras);
    } catch (_) {
      return;
    }
    if (mounted) setState(() => _saved = cameras);
  }

  void _toggleSaved(Device device) {
    final kept = _savedFor(device);
    _keep(
      kept == null
          ? [..._saved, SavedCamera(device.address, device.rtspPort!)]
          : _saved.where((c) => c != kept).toList(),
    );
  }

  /// The saved entry for [device], by address and port; the name is not a key.
  SavedCamera? _savedFor(Device device) =>
      _saved.where((c) => c.address == device.address && c.port == device.rtspPort).firstOrNull;

  Future<void> _rename(SavedCamera camera) async {
    final name = await askName(context, current: camera.name, address: camera.address);
    if (name == null) return;
    await _keep([for (final c in _saved) c == camera ? camera.named(name) : c]);
  }

  /// The name the user gave [device], if it is saved under one.
  String? _nameOf(Device device) {
    final kept = _savedFor(device);
    return kept == null || kept.label == device.address ? null : kept.label;
  }

  Future<void> _remove(SavedCamera camera) async {
    final before = _saved;
    await _keep([..._saved]..remove(camera));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed ${camera.address} · ${portLabel(camera.port)}'),
        action: SnackBarAction(label: 'Undo', onPressed: () => _keep(before)),
      ),
    );
  }

  Future<void> _scan() async {
    if (!await _consented()) return;
    setState(() => _phase = _Phase.scanning);
    try {
      final devices = await widget.scan();
      if (!mounted) return;
      setState(() {
        _devices = devices ?? const [];
        _streams = {
          for (final device in _devices)
            device.address: ValueNotifier(device.rtspPort == null ? const {} : null),
        };
        _phase = devices == null ? _Phase.noNetwork : _Phase.done;
      });
      for (final device in _devices) {
        if (device.rtspPort != null) unawaited(_checkStream(device, _streams[device.address]!));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _checkStream(Device device, ValueNotifier<Map<String, PathStatus>?> into) async {
    try {
      into.value = await widget.findPaths(device.address, device.rtspPort!);
    } catch (_) {
      into.value = const {};
    }
  }

  /// False while the notice is open or refused, and for any tap that lands
  /// while the store is still being read: one tap, one notice.
  Future<bool> _consented() async {
    if (_asking) return false;
    _asking = true;
    try {
      return await _consentGiven();
    } finally {
      _asking = false;
    }
  }

  Future<bool> _consentGiven() async {
    var given = false;
    try {
      given = await widget.consent.read();
    } catch (_) {}
    if (given || !mounted) return given;
    final accepted = await showDialog<bool>(context: context, builder: (_) => const _Notice());
    if (accepted != true) return false;
    try {
      await widget.consent.write();
    } catch (_) {}
    return mounted;
  }

  Future<void> _watch(Device device) async {
    setState(() => _watching = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          device: device,
          name: _nameOf(device),
          player: widget.newPlayer(),
          findPaths: widget.findPaths,
          store: widget.store,
        ),
      ),
    );
    if (mounted) setState(() => _watching = false);
  }

  void _report(Device device) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReportPage(
        device: device,
        name: _nameOf(device),
        streams: _streams[device.address]!,
        onWatch: device.rtspPort == null ? null : () => _watch(device),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scanning = _phase == _Phase.scanning;
    // Lists read best in a 600 px column; a wall of pictures wants the window.
    final grid = _phase == _Phase.idle && _saved.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('camwatch'), actions: widget.actions),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: grid ? 1280 : 600),
          child: _body(),
        ),
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
    _Phase.idle when _saved.isNotEmpty => _SavedGrid(
      _saved,
      live: _resumed && !_watching,
      newPlayer: widget.newPlayer,
      findPaths: widget.findPaths,
      store: widget.store,
      onWatch: (camera) => _watch(camera.device),
      onRemove: _remove,
      onRename: _rename,
    ),
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
    _Phase.done => _DeviceList(
      _devices,
      streams: _streams,
      saved: _saved,
      onReport: _report,
      onWatch: _watch,
      onSave: _toggleSaved,
    ),
  };
}

/// The cameras kept across restarts as live tiles, shown until a scan
/// replaces them; every tile streams only while [live].
class _SavedGrid extends StatelessWidget {
  const _SavedGrid(
    this.cameras, {
    required this.live,
    required this.newPlayer,
    required this.findPaths,
    required this.store,
    required this.onWatch,
    required this.onRemove,
    required this.onRename,
  });

  final List<SavedCamera> cameras;
  final bool live;
  final StreamPlayer Function() newPlayer;
  final FindPaths findPaths;
  final CredentialStore store;
  final void Function(SavedCamera) onWatch;
  final void Function(SavedCamera) onRemove;
  final void Function(SavedCamera) onRename;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saved cameras',
                  style: text.titleSmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'Kept from earlier scans. Scan to check them again.',
                  style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 16 / 10,
            ),
            delegate: SliverChildBuilderDelegate(childCount: cameras.length, (context, index) {
              final camera = cameras[index];
              return LiveTile(
                key: ValueKey(camera),
                camera: camera,
                live: live,
                newPlayer: newPlayer,
                findPaths: findPaths,
                store: store,
                onTap: () => onWatch(camera),
                onRemove: () => onRemove(camera),
                onRename: () => onRename(camera),
              );
            }),
          ),
        ),
      ],
    );
  }
}

/// The notice before the first scan; pops true once accepted.
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      icon: const Icon(Icons.policy_outlined),
      title: const Text('Before the first scan'),
      content: const Text(
        'camwatch probes every device on the network you are connected to. '
        'Scan only your own network, or one you have permission to test.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('I understand'),
        ),
      ],
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList(
    this.devices, {
    required this.streams,
    required this.saved,
    required this.onReport,
    required this.onWatch,
    required this.onSave,
  });

  final List<Device> devices;
  final Map<String, ValueNotifier<Map<String, PathStatus>?>> streams;
  final List<SavedCamera> saved;
  final void Function(Device) onReport;
  final void Function(Device) onWatch;
  final void Function(Device) onSave;

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
        final kept = saved
            .where((c) => c.address == device.address && c.port == device.rtspPort)
            .firstOrNull;
        return _DeviceCard(
          device,
          streams: streams[device.address]!,
          saved: kept != null,
          name: kept == null || kept.label == device.address ? null : kept.label,
          onReport: () => onReport(device),
          onWatch: () => onWatch(device),
          onSave: () => onSave(device),
        );
      },
    );
  }
}

/// One device: its grade, address and ports, following [streams] as the
/// stream check completes.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard(
    this.device, {
    required this.streams,
    required this.saved,
    this.name,
    required this.onReport,
    required this.onWatch,
    required this.onSave,
  });

  final Device device;
  final ValueListenable<Map<String, PathStatus>?> streams;
  final bool saved;
  final String? name;
  final VoidCallback onReport;
  final VoidCallback onWatch;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final playable = device.rtspPort != null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onReport,
        excludeFromSemantics: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: ValueListenableBuilder(
            valueListenable: streams,
            builder: (context, streams, _) {
              final line = gradeLine(device, streams, colors);
              return Row(
                children: [
                  Expanded(
                    // The hint rides the merged node that carries the tap; the watch
                    // button stays outside it.
                    child: MergeSemantics(
                      child: Semantics(
                        button: true,
                        onTap: onReport,
                        onTapHint: 'open the security report',
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: line.color.withValues(alpha: 0.15),
                              foregroundColor: line.color,
                              child: streams == null
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Icon(line.icon),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name ?? device.address,
                                    softWrap: false,
                                    overflow: TextOverflow.fade,
                                    style: text.titleMedium?.copyWith(
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  if (name != null)
                                    Text(
                                      device.address,
                                      softWrap: false,
                                      overflow: TextOverflow.fade,
                                      style: text.bodySmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  Text(
                                    line.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodyMedium?.copyWith(
                                      color: line.color,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          device.openPorts.map(portLabel).join(' · '),
                                          style: text.bodyMedium?.copyWith(
                                            color: colors.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      if (device.onvifAddress != null) const _OnvifBadge(),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!playable)
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
                  if (playable) _CardActions(saved: saved, onSave: onSave, onWatch: onWatch),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OnvifBadge extends StatelessWidget {
  const _OnvifBadge();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'ONVIF',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.onTertiaryContainer),
      ),
    );
  }
}

/// Save and Watch for a device with a stream; only the saved state is coloured.
class _CardActions extends StatelessWidget {
  const _CardActions({required this.saved, required this.onSave, required this.onWatch});

  final bool saved;
  final VoidCallback onSave;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onSave,
          tooltip: saved ? 'Remove from saved' : 'Save camera',
          icon: Icon(
            saved ? Icons.bookmark : Icons.bookmark_outline,
            color: saved ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: onWatch,
          tooltip: 'Watch',
          icon: Icon(Icons.play_circle_outline, color: colors.primary),
        ),
      ],
    );
  }
}
