import 'dart:async';
import 'dart:math';

import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

import 'consent_store.dart';

/// The one request that leaves the local network, and only once the notice
/// in [consent] has been accepted: [check] asks GitHub for a newer release,
/// on a tap and quietly at start. A newer one is offered in a banner whose
/// Download hands its link to [open].
class UpdateButton extends StatefulWidget {
  const UpdateButton({super.key, required this.check, required this.consent, required this.open});

  final Future<Release?> Function() check;
  final ConsentStore consent;
  final Future<void> Function(Uri) open;

  @override
  State<UpdateButton> createState() => _UpdateButtonState();
}

class _UpdateButtonState extends State<UpdateButton> {
  @override
  void initState() {
    super.initState();
    _given().then((given) {
      if (given) _check(quiet: true);
    });
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
          TextButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              unawaited(
                widget.open(release!.download).catchError((_) => _say('Could not open a browser')),
              );
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
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
        'camwatch asks github.com for its newest release, now and each time it starts. '
        'That is the only request that leaves your network. It sends nothing about you '
        'or your cameras.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Allow')),
      ],
    );
  }
}
