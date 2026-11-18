import 'package:flutter/material.dart';

/// A text field with a button that hands its text to [onSubmit] and clears
/// it. Blank text is ignored.
class const TextEntry({
  /// What the field asks for.
  required final String hint,

  /// The button's icon and tooltip.
  required final IconData icon,
  required final String tooltip,

  /// Receives the trimmed text.
  required final ValueChanged<String> onSubmit,
  super.key,
}) extends StatefulWidget {
  @override
  State<TextEntry> createState() => _TextEntryState();
}

class _TextEntryState extends State<TextEntry> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ),
        IconButton(
          tooltip: widget.tooltip,
          icon: Icon(widget.icon),
          onPressed: _submit,
        ),
      ],
    ),
  );
}
