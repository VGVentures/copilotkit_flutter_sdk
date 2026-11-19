import 'package:flutter/material.dart';

/// A text field with a button that hands its trimmed text to [onSubmit].
/// Blank text is ignored. The field keeps its text: the owner of [controller]
/// decides when to clear it, e.g. once a save worked.
class const TextEntry({
  /// The text of the field.
  required final TextEditingController controller,

  /// What the field asks for.
  required final String hint,

  /// The button's icon and tooltip.
  required final IconData icon,
  required final String tooltip,

  /// Receives the trimmed text.
  required final ValueChanged<String> onSubmit,
  super.key,
}) extends StatelessWidget {
  void _submit() {
    final text = controller.text.trim();
    if (text.isNotEmpty) onSubmit(text);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(hintText: hint),
          ),
        ),
        IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: _submit),
      ],
    ),
  );
}
