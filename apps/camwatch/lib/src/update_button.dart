import 'dart:async';
import 'dart:math';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'consent_store.dart';
import 'installer.dart';

/// The one request that leaves the local network, and only once the notice
/// in [consent] has been accepted: [check] asks GitHub for a newer release,
/// on a tap and quietly at start. A newer one is offered in a banner: with
/// an installer, Update fetches and installs it; without one, Download
/// hands the link to the browser.
class UpdateButton extends StatefulWidget {
  const UpdateButton({
    super.key,
    required this.check,
    required this.consent,
    required this.open,
    required this.download,
    this.installer,
  });

  final Future<Release?> Function() check;
  final ConsentStore consent;
  final Future<void> Function(Uri) open;
  final Download download;
  final Installer? installer;

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  @override
  void initState() {
    super.initState();
    _given().then((given) {
      if (given) return _check(quiet: true);
      _askOnce();
    });
  }

  /// The first launch asks by itself; a refusal is kept so it asks no more.
  Future<void> _askOnce() async {
    bool asked;
    try {
      asked = await widget.consent.wasAsked();
    } catch (_) {
      return;
    }
    if (asked || !mounted) return;
    final accepted = await showDialog<bool>(context: context, builder: (_) => const _Notice());
    try {
      accepted == true ? await widget.consent.write() : await widget.consent.refuse();
    } catch (_) {}
    if (accepted == true) await _check(quiet: true);
  }

  Future<bool> _given() async {
    try {
      return await widget.consent.read();
    } catch (_) {
      return false;
    }
  }

  Future<void> _tap() async {
    if (!await _given()) {
      if (!mounted) return;
      final accepted = await showDialog<bool>(context: context, builder: (_) => const _Notice());
      if (accepted != true) return;
      try {
        await widget.consent.write();
      } catch (_) {}
    }
    await _check(quiet: false);
  }

  Future<void> _check({required bool quiet}) async {
    Release? release;
    try {
      release = await widget.check();
    } on GitHubBusy {
      if (!quiet) _say('GitHub is busy, try again later', 'Retry', _tap);
      return;
    } catch (_) {
      if (!quiet) _say('Could not reach github.com', 'Retry', _tap);
      return;
    }
    if (release == null) {
      if (!quiet) _say('You have the newest version', 'Stop checking', _stop);
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // The list sits in a 600 px column; the banner keeps to it on a wide window.
    final margin = max(0.0, (MediaQuery.sizeOf(context).width - 600) / 2);
    messenger.showMaterialBanner(
      MaterialBanner(
        margin: EdgeInsets.symmetric(horizontal: margin),
        leading: const Icon(Icons.system_update_alt),
        content: Text('camwatch ${release.version} is out'),
        actions: [
          TextButton(onPressed: messenger.hideCurrentMaterialBanner, child: const Text('Later')),
          if (widget.installer case final installer?)
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                unawaited(_update(release!, installer));
              },
              child: const Text('Update'),
            )
          else
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                unawaited(
                  widget
                      .open(release!.download)
                      .catchError((_) => _say('Could not open a browser')),
                );
              },
              child: const Text('Download'),
            ),
        ],
      ),
    );
  }

  /// Fetches and installs [release] behind a progress dialog; every way it
  /// can fail is named, nothing is left half done.
  Future<void> _update(Release release, Installer installer) async {
    final progress = ValueNotifier<(int, int?)>((0, null));
    final installing = ValueNotifier(false);
    final navigator = Navigator.of(context);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PopScope(
          canPop: false,
          child: _Progress(version: release.version, progress: progress, installing: installing),
        ),
      ),
    );
    try {
      final file = await widget.download(
        release,
        onProgress: (received, total) => progress.value = (received, total),
      );
      installing.value = true;
      try {
        await installer.install(file);
      } on InstallBlocked {
        rethrow;
      } catch (_) {
        _say('Could not start the install', 'Retry', () => _update(release, installer));
      }
    } on InstallBlocked {
      _say(
        'Allow camwatch to install updates in Settings, then tap Update again',
        'Retry',
        () => _update(release, installer),
      );
    } on SignatureMismatch {
      _say('The update is not signed by camwatch', 'Retry', () => _update(release, installer));
    } on DigestMismatch {
      _say('The download was damaged, try again', 'Retry', () => _update(release, installer));
    } catch (_) {
      _say('Could not download the update', 'Retry', () => _update(release, installer));
    } finally {
      if (mounted) navigator.pop();
      progress.dispose();
      installing.dispose();
    }
  }

  Future<void> _stop() async {
    try {
      await widget.consent.clear();
    } catch (_) {}
  }

  void _say(String text, [String? action, VoidCallback? onAction]) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        action: action == null ? null : SnackBarAction(label: action, onPressed: onAction!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: _tap,
    tooltip: 'Check for updates',
    icon: const Icon(Icons.system_update_alt),
  );
}

/// The download, then the install, of one release; closed by the caller.
class _Progress extends StatelessWidget {
  const _Progress({required this.version, required this.progress, required this.installing});

  final String version;

  /// Bytes so far and the total when the server said.
  final ValueListenable<(int, int?)> progress;

  /// True once the file is whole and the installer has it.
  final ValueListenable<bool> installing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Downloading camwatch $version'),
      content: ValueListenableBuilder(
        valueListenable: installing,
        builder: (context, installing, _) => ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, value, _) {
            final (received, total) = value;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: installing || total == null ? null : received / total,
                ),
                const SizedBox(height: 12),
                Text(
                  installing
                      ? 'Installing…'
                      : total == null
                      ? '${_mb(received)} MB'
                      : '${_mb(received)} MB of ${_mb(total)} MB',
                  style: text.bodyMedium,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _mb(int bytes) => bytes >> 20;
}

/// Asked once before the first check; pops true when accepted.
class _Notice extends StatelessWidget {
  const _Notice();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      icon: const Icon(Icons.system_update_alt),
      title: const Text('Check for updates?'),
      content: const Text(
        'camwatch asks github.com for its newest release, now and each time it starts, '
        'and fetches an update from there when you ask. GitHub and its download servers '
        'are the only places the app ever talks to. It sends nothing about you or your cameras.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
      ],
    );
  }
}
