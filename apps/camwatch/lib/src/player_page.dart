import 'dart:async';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'credential_store.dart';
import 'credentials_dialog.dart';
import 'player.dart';
import 'status_message.dart';

/// How long a camera gets to send its first frames before the page gives up.
const connectTimeout = Duration(seconds: 15);

/// What is left of that once the player reports an error: cameras often fail
/// on audio alone (G.726 has no decoder here) and still deliver a picture.
const errorGrace = Duration(seconds: 3);

/// Which stream paths a camera serves; [probeStreamPaths] in the app.
typedef FindPaths = Future<Map<String, PathStatus>> Function(String host, int port);

/// Full-screen playback of one device's RTSP stream: the first open path,
/// else the first protected one with the login kept in [store].
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.device,
    required this.player,
    required this.findPaths,
    required this.store,
    this.name,
  });

  final Device device;

  /// What the user calls the camera, shown over the address when set.
  final String? name;
  final StreamPlayer player;
  final FindPaths findPaths;
  final CredentialStore store;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final StreamSubscription<String> _errors;
  late final StreamSubscription<void> _frames;
  late final StreamSubscription<void> _redirects;
  Timer? _deadline;
  var _connecting = true;
  var _failed = false;
  var _needsPassword = false;
  var _redirected = false;
  var _graceArmed = false;
  String? _protectedPath;
  Credentials? _credentials;

  String get _host => widget.device.address;
  int get _port => widget.device.rtspPort!;

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
    _redirects = widget.player.redirected.listen((_) {
      _redirected = true;
      _fail();
    });
    _open();
  }

  Future<void> _open() async {
    _restart();
    setState(() {
      _needsPassword = false;
      _credentials = null;
    });
    Map<String, PathStatus> paths;
    try {
      paths = await widget.findPaths(_host, _port).timeout(connectTimeout);
    } catch (_) {
      paths = const {};
    }
    if (!mounted) return;
    final path = firstPath(paths, PathStatus.open);
    if (path != null) return _play(rtspUrl(_host, _port, path));
    _protectedPath = firstPath(paths, PathStatus.needsAuth);
    if (_protectedPath == null) return _fail();
    Credentials? kept;
    try {
      kept = await widget.store.read(_host);
    } catch (_) {}
    if (!mounted) return;
    if (kept == null) {
      _needsPassword = true;
      return _fail();
    }
    _login(kept);
  }

  Future<void> _askPassword() async {
    final typed = await askCredentials(context, current: _credentials);
    if (typed == null || !mounted) return;
    try {
      await widget.store.write(_host, typed);
    } catch (_) {}
    if (!mounted) return;
    _restart();
    setState(() => _needsPassword = false);
    _login(typed);
  }

  void _login(Credentials credentials) {
    _credentials = credentials;
    _play(rtspUrl(_host, _port, _protectedPath!, credentials));
  }

  void _restart() {
    _deadline?.cancel();
    _graceArmed = false;
    _connecting = true;
    _failed = false;
    _redirected = false;
  }

  void _play(String url) {
    _deadline = Timer(connectTimeout, _fail);
    unawaited(widget.player.open(url).catchError((_) => _fail()));
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
    _redirects.cancel();
    widget.player.dispose();
    super.dispose();
  }

  Widget _failure(ThemeData theme) {
    final tryAgain = FilledButton.tonalIcon(
      onPressed: _open,
      icon: const Icon(Icons.refresh),
      label: const Text('Try again'),
    );
    if (_redirected) {
      return StatusMessage(
        icon: Icons.alt_route,
        iconColor: theme.colorScheme.error,
        title: 'The camera tried to send you elsewhere',
        body:
            'It answered with a redirect, which camwatch never follows: the new address '
            'could be outside your network. A camera that does this is misconfigured or hostile.',
        action: tryAgain,
      );
    }
    if (_needsPassword) {
      return StatusMessage(
        icon: Icons.lock_outline,
        title: 'The camera asks for a password',
        body:
            "Enter its username and password to watch. They stay in your device's secure "
            'storage, tied to this address.',
        action: FilledButton.icon(
          onPressed: _askPassword,
          icon: const Icon(Icons.key_outlined),
          label: const Text('Enter password'),
        ),
      );
    }
    if (_credentials != null) {
      return StatusMessage(
        icon: Icons.lock_outline,
        iconColor: theme.colorScheme.error,
        title: 'The camera did not let you in',
        body: 'Wrong password, or the stream is down.',
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: _askPassword,
              icon: const Icon(Icons.key_outlined),
              label: const Text('Change password'),
            ),
            tryAgain,
          ],
        ),
      );
    }
    return StatusMessage(
      icon: Icons.videocam_off_outlined,
      iconColor: theme.colorScheme.error,
      title: 'The camera did not answer',
      body: 'No stream came from port $_port.',
      action: tryAgain,
    );
  }

  @override
  Widget build(BuildContext context) {
    // A full dark theme, not copyWith: that would keep the light text colours.
    final dark = ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark);
    return Theme(
      data: dark,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          // A scrim under the title, so a bright frame never swallows it.
          flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black54, Colors.transparent],
              ),
            ),
          ),
          title: NamedTitle(name: widget.name, address: _host),
        ),
        body: Center(
          child: _failed
              ? _failure(dark)
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
