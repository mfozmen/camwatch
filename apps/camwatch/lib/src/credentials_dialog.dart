import 'package:camwatch_core/camwatch_core.dart';
import 'package:flutter/material.dart';

/// Asks for a camera login, starting from [current]. Null when cancelled.
Future<Credentials?> askCredentials(BuildContext context, {Credentials? current}) =>
    showDialog<Credentials>(context: context, builder: (_) => _CredentialsDialog(current));

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog(this.current);

  final Credentials? current;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  late final _user = TextEditingController(text: widget.current?.user);
  late final _password = TextEditingController(text: widget.current?.password);
  var _hidden = true;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_user.text.isEmpty) return;
    Navigator.pop(context, Credentials(_user.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Camera password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _user,
            autofocus: true,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Username'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: _hidden,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show password' : 'Hide password',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _user.text.isEmpty ? null : _submit, child: const Text('Watch')),
      ],
    );
  }
}
