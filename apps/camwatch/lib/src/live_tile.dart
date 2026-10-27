import 'dart:async';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'credential_store.dart';
import 'player.dart';
import 'player_page.dart';

export 'player_page.dart' show FindPaths, connectTimeout, errorGrace;

enum _Picture { connecting, live, locked, off }

/// One saved camera's picture in the grid, streaming while [live]: the first
/// open path, else the protected one with the kept login, else a lock. A
/// tile that is not live holds no player at all, so a hidden grid costs the
/// cameras nothing.
class LiveTile extends StatefulWidget {
  const LiveTile({
    super.key,
    required this.camera,
    required this.live,
    required this.newPlayer,
    required this.findPaths,
    required this.store,
    required this.onTap,
    required this.onRemove,
  });

  final SavedCamera camera;
  final bool live;
  final StreamPlayer Function() newPlayer;
  final FindPaths findPaths;
  final CredentialStore store;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<LiveTile> createState() => _LiveTileState();
}

class _LiveTileState extends State<LiveTile> {
  StreamPlayer? _player;
  final _subscriptions = <StreamSubscription<void>>[];
  Timer? _deadline;
  var _picture = _Picture.connecting;
  // Bumped by every start and stop: a path check that answers after a stop is ignored.
  var _generation = 0;

  @override
  void initState() {
    super.initState();
    if (widget.live) _start();
  }

  @override
  void didUpdateWidget(LiveTile old) {
    super.didUpdateWidget(old);
    if (old.live == widget.live) return;
    widget.live ? _start() : _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    _picture = _Picture.connecting;
    final player = widget.newPlayer();
    _player = player;
    _subscriptions.addAll([
      player.errors.listen((_) {
        if (_picture != _Picture.connecting) return;
        _deadline?.cancel();
        _deadline = Timer(errorGrace, _off);
      }),
      player.firstFrame.listen((_) => _show(_Picture.live)),
      player.redirected.listen((_) => _off()),
    ]);
    _deadline = Timer(connectTimeout, _off);
    final host = widget.camera.address;
    final port = widget.camera.port;
    Map<String, PathStatus> paths;
    try {
      paths = await widget.findPaths(host, port).timeout(connectTimeout);
    } catch (_) {
      paths = const {};
    }
    if (generation != _generation) return;
    final open = firstPath(paths, PathStatus.open);
    if (open != null) return _play(rtspUrl(host, port, open));
    final protected = firstPath(paths, PathStatus.needsAuth);
    if (protected == null) return _off();
    Credentials? kept;
    try {
      kept = await widget.store.read(host);
    } catch (_) {}
    if (generation != _generation) return;
    if (kept == null) return _show(_Picture.locked);
    _play(rtspUrl(host, port, protected, kept));
  }

  void _play(String url) => unawaited(_player!.open(url).catchError((_) => _off()));

  void _off() => _show(_Picture.off);

  void _show(_Picture picture) {
    _deadline?.cancel();
    if (mounted) setState(() => _picture = picture);
  }

  void _stop() {
    _generation++;
    _deadline?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    unawaited(_player?.dispose());
    _player = null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: Colors.black,
      child: InkWell(
        onTap: widget.onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_player case final player?) player.view,
            Center(
              child: switch (_picture) {
                _Picture.connecting => const CircularProgressIndicator(),
                _Picture.live => const SizedBox.shrink(),
                _Picture.locked => const _Hint(Icons.lock_outline, 'Password needed'),
                _Picture.off => const _Hint(Icons.videocam_off_outlined, 'No stream'),
              },
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.camera.address,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: text.titleSmall?.copyWith(
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More',
                      iconColor: Colors.white,
                      onSelected: (_) => widget.onRemove(),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 32),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}
