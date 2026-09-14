import 'package:flutter/material.dart';

/// Ask for a line of text. Returns null when cancelled, and an empty string
/// when [required] is false and the user confirms without typing.
Future<String?> askForText(
  BuildContext context, {
  required String title,
  String message = '',
  String hint = '',
  String confirmLabel = 'Confirm',
  Color? confirmColor,
  bool required = true,
  int maxLines = 3,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextPromptDialog(
      title: title,
      message: message,
      hint: hint,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
      required: required,
      maxLines: maxLines,
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  Color? confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: confirmColor == null
              ? null
              : FilledButton.styleFrom(backgroundColor: confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Owns its controller, so the controller is disposed only after the dialog's
/// closing animation has finished using it.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.message,
    required this.hint,
    required this.confirmLabel,
    required this.confirmColor,
    required this.required,
    required this.maxLines,
  });

  final String title;
  final String message;
  final String hint;
  final String confirmLabel;
  final Color? confirmColor;
  final bool required;
  final int maxLines;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (widget.required && text.isEmpty) {
      setState(() => _error = 'This field is required.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.message.isNotEmpty) ...[
            Text(widget.message),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: widget.maxLines,
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: widget.confirmColor == null
              ? null
              : FilledButton.styleFrom(backgroundColor: widget.confirmColor),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
