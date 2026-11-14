import 'package:flutter/material.dart';

import '../theme/studio_theme.dart';

/// Modal dialog prompting for a new preset name when duplicating a patch
/// via "Save Copy As...".
class SaveCopyAsDialog extends StatefulWidget {
  final String initialName;
  final int? maxLength;
  final String title;

  const SaveCopyAsDialog({
    super.key,
    required this.initialName,
    this.maxLength,
    this.title = 'Save Copy As...',
  });

  static Future<String?> show(
    BuildContext context, {
    required String initialName,
    int? maxLength,
    String title = 'Save Copy As...',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => SaveCopyAsDialog(
        initialName: initialName,
        maxLength: maxLength,
        title: title,
      ),
    );
  }

  @override
  State<SaveCopyAsDialog> createState() => _SaveCopyAsDialogState();
}

class _SaveCopyAsDialogState extends State<SaveCopyAsDialog> {
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    final suggested = '${widget.initialName.trim()} Copy'.trim();
    final initial = widget.maxLength != null && suggested.length > widget.maxLength!
        ? suggested.substring(0, widget.maxLength!).trimRight()
        : suggested;
    _nameController = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StudioTheme.surfaceElevated,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create an independent copy under a new preset name without overwriting the original.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('save_copy_as_name_input'),
                controller: _nameController,
                autofocus: true,
                maxLength: widget.maxLength,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  labelText: 'New Preset Name',
                  labelStyle: const TextStyle(color: Colors.grey),
                  filled: true,
                  fillColor: StudioTheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('save_copy_as_cancel_button'),
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton.icon(
          key: const Key('save_copy_as_confirm_button'),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Save Copy'),
          style: ElevatedButton.styleFrom(
            backgroundColor: StudioTheme.colorModulation,
            foregroundColor: Colors.black,
          ),
          onPressed: _submit,
        ),
      ],
    );
  }
}

