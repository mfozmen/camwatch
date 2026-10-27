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
  var _graced = false;
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
    _graced = false;
    final player = widget.newPlayer();
    _player = player;
    _subscriptions.addAll([
      // One grace per start: a camera erroring every second must not spin forever.
      player.errors.listen((_) {
        if (_picture != _Picture.connecting || _graced) return;
        _graced = true;
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

  /// Gives up: the picture says so and the player, with its relay and
  /// camera connection, is released.
  void _off() {
    _show(_Picture.off);
    _stop();
  }

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
    final address = widget.camera.address;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The menu stays outside the merged node, as on the device card.
          MergeSemantics(
            child: Semantics(
              button: true,
              onTapHint: 'watch',
              child: InkWell(
                onTap: widget.onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_player case final player?) player.view,
                    Padding(
                      padding: const EdgeInsets.only(bottom: _barHeight),
                      child: Center(
                        child: switch (_picture) {
                          _Picture.connecting => const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          _Picture.live => const SizedBox.shrink(),
                          _Picture.locked => const _Hint(
                            Icons.lock_outline,
                            'Tap to enter password',
                          ),
                          _Picture.off => const _Hint(Icons.videocam_off_outlined, 'No stream'),
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: _barHeight + 24,
                        padding: const EdgeInsets.fromLTRB(12, 24, 48, 0),
                        alignment: Alignment.centerLeft,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Text(
                          address,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style: text.titleSmall?.copyWith(
                            color: Colors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomRight,
            child: PopupMenuButton<String>(
              tooltip: 'Options for $address',
              iconColor: Colors.white,
              onSelected: (_) => widget.onRemove(),
              itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove'))],
            ),
          ),
        ],
      ),
    );
  }
}

/// The label bar along the tile's bottom edge; the hint is centred above it.
const _barHeight = 40.0;

class _Hint extends StatelessWidget {
  const _Hint(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white70)),
      ],
    );
  }
}
