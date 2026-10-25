import 'package:flutter/material.dart';

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
