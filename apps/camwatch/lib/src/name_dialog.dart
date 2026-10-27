import 'package:flutter/material.dart';

/// Asks for a camera's name; pops the typed text, or null when cancelled.
/// An empty answer means "just the address again".
Future<String?> askName(BuildContext context, {required String current, required String address}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(current: current, address: address),
    );

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.current, required this.address});

  final String current;
  final String address;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.current.isEmpty ? 'Name this camera' : 'Rename camera'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: _name,
          autofocus: true,
          maxLength: 40,
          // The counter only once the cap is near; next to the helper it is clutter.
          buildCounter: (_, {required currentLength, required maxLength, required isFocused}) =>
              currentLength < 30 ? null : Text('$currentLength/$maxLength'),
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value),
          decoration: InputDecoration(
            labelText: 'Name',
            hintText: 'Garden',
            helperText: 'Leave empty to show ${widget.address}.',
            helperMaxLines: 2,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _name.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
