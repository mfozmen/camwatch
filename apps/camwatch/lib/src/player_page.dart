import 'dart:async';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'player.dart';
import 'status_message.dart';

/// How long a camera gets to send its first frames before the page gives up.
const connectTimeout = Duration(seconds: 15);

/// What is left of that once the player reports an error: cameras often fail
/// on audio alone (G.726 has no decoder here) and still deliver a picture.
const errorGrace = Duration(seconds: 3);

/// Which stream paths a camera serves; [probeStreamPaths] in the app.
typedef FindPaths = Future<Map<String, PathStatus>> Function(String host, int port);

/// Full-screen playback of one device's RTSP stream: the first path that
/// streams without a password.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.device,
    required this.player,
    required this.findPaths,
  });

  final Device device;
  final StreamPlayer player;
  final FindPaths findPaths;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final StreamSubscription<String> _errors;
  late final StreamSubscription<void> _frames;
  Timer? _deadline;
  var _connecting = true;
  var _failed = false;
  var _needsPassword = false;
  var _graceArmed = false;

  @override
  void initState() {
    super.initState();
    // The player's message can carry the URL, credentials included: it is never shown.
    _errors = widget.player.errors.listen((_) {
      if (!_connecting || _failed || _graceArmed) return;
      _graceArmed = true;
      _deadline?.cancel();
      _deadline = Timer(errorGrace, _fail);
    });
    _frames = widget.player.firstFrame.listen((_) {
      _deadline?.cancel();
      setState(() => _connecting = false);
    });
    _open();
  }

  Future<void> _open() async {
    _deadline?.cancel();
    _graceArmed = false;
    setState(() {
      _connecting = true;
      _failed = false;
      _needsPassword = false;
    });
    final host = widget.device.address;
    final port = widget.device.rtspPort;
    Map<String, PathStatus> paths;
    try {
      paths = await widget.findPaths(host, port!);
    } catch (_) {
      paths = const {};
    }
    if (!mounted) return;
    final path = firstOpenPath(paths);
    if (path == null) {
      _needsPassword = paths.containsValue(PathStatus.needsAuth);
      return _fail();
    }
    _deadline = Timer(connectTimeout, _fail);
    unawaited(widget.player.open('rtsp://$host:$port$path').catchError((_) => _fail()));
  }

  void _fail() {
    _deadline?.cancel();
    if (!mounted) return;
    setState(() => _failed = true);
  }

  @override
  void dispose() {
    _deadline?.cancel();
    _errors.cancel();
    _frames.cancel();
    widget.player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal, brightness: Brightness.dark),
    );
    return Theme(
      data: dark,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(backgroundColor: Colors.transparent, title: Text(widget.device.address)),
        body: Center(
          child: _failed
              ? StatusMessage(
                  icon: _needsPassword ? Icons.lock_outline : Icons.videocam_off_outlined,
                  iconColor: dark.colorScheme.error,
                  title: _needsPassword
                      ? 'The camera asks for a password'
                      : 'The camera did not answer',
                  body: _needsPassword
                      ? 'Entering one is not supported yet.'
                      : 'No stream came from port ${widget.device.rtspPort}.',
                  action: FilledButton.tonalIcon(
                    onPressed: _open,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    widget.player.view,
                    if (_connecting)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text('Connecting…', style: dark.textTheme.bodyMedium),
                        ],
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}
