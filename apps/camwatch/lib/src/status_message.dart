import 'package:flutter/material.dart';

/// An app bar title: the camera's name with its address underneath, or the
/// address alone.
class NamedTitle extends StatelessWidget {
  const NamedTitle({super.key, required this.name, required this.address});

  final String? name;
  final String address;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    if (name case final name?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name, softWrap: false, overflow: TextOverflow.fade),
          Text(
            address,
            softWrap: false,
            overflow: TextOverflow.fade,
            style: style.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    }
    return Text(address);
  }
}

/// A centred icon, title and one line of guidance: every empty, busy and
/// failed state in the app looks like this, with an optional [action].
class StatusMessage extends StatelessWidget {
  const StatusMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.iconColor,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: iconColor ?? colors.primary),
          const SizedBox(height: 24),
          Text(title, style: text.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            body,
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          if (action case final action?) ...[const SizedBox(height: 24), action],
        ],
      ),
    );
  }
}
