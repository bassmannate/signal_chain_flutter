import 'package:flutter/material.dart';

import '../theme/studio_theme.dart';
import 'patch_editor_controller.dart';
import 'write_to_slot_dialog.dart';

/// Real-time header widget for editing patch metadata (Name, Tempo in BPM,
/// dirty status indication, and hardware slot write actions).
class PatchMetadataHeaderWidget extends StatefulWidget {
  final PatchEditorController controller;

  const PatchMetadataHeaderWidget({
    super.key,
    required this.controller,
  });

  @override
  State<PatchMetadataHeaderWidget> createState() => _PatchMetadataHeaderWidgetState();
}

class _PatchMetadataHeaderWidgetState extends State<PatchMetadataHeaderWidget> {
  late final TextEditingController _nameController;
  final FocusNode _nameFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.controller.patch?.name ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant PatchMetadataHeaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentName = widget.controller.patch?.name ?? '';
    if (!_nameFocusNode.hasFocus && _nameController.text != currentName) {
      _nameController.text = currentName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final patch = widget.controller.patch;
        if (patch == null) return const SizedBox.shrink();

        final maxLen = widget.controller.connectionController.activeFamily.maxNameLength;
        final currentTempo = patch.tempo;

        // Keep text controller in sync if user is not actively typing
        if (!_nameFocusNode.hasFocus && _nameController.text != patch.name) {
          _nameController.text = patch.name;
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 560;

            return Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 10 : 12,
                vertical: 6,
              ),
              decoration: const BoxDecoration(
                color: StudioTheme.surfaceElevated,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
                border: Border(
                  bottom: BorderSide(color: StudioTheme.surfaceBorder, width: 1),
                ),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  // Patch Name + Dirty Indicator
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.edit_note,
                        size: 18,
                        color: StudioTheme.colorModulation,
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: isCompact ? 128 : 150,
                        child: TextField(
                          key: const Key('patch_name_textfield'),
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          maxLength: maxLen,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: 'Patch Name',
                            hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            filled: true,
                            fillColor: StudioTheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: StudioTheme.surfaceBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(color: StudioTheme.colorModulation),
                            ),
                          ),
                          onChanged: (val) {
                            widget.controller.updatePatchName(val);
                          },
                        ),
                      ),
                      if (widget.controller.isDirty) ...[
                        const SizedBox(width: 8),
                        Container(
                          key: const Key('patch_dirty_indicator'),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.amberAccent.withValues(alpha: 0.6),
                            ),
                          ),
                          child: const Text(
                            '* UNSAVED',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Tempo Controls (BPM Number & Slider)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed, size: 16, color: StudioTheme.colorFilterEq),
                      const SizedBox(width: 4),
                      Container(
                        key: const Key('patch_tempo_display'),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: StudioTheme.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: StudioTheme.surfaceBorder),
                        ),
                        child: Text(
                          '$currentTempo BPM',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: StudioTheme.colorFilterEq,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('tempo_decrement_button'),
                        icon: const Icon(Icons.remove, size: 16, color: Colors.grey),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        splashRadius: 16,
                        tooltip: 'Decrease Tempo (-1 BPM)',
                        onPressed: () {
                          widget.controller.updatePatchTempo(currentTempo - 1);
                        },
                      ),
                      SizedBox(
                        width: isCompact ? 76 : 90,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: StudioTheme.colorFilterEq,
                            inactiveTrackColor: StudioTheme.surfaceBorder,
                            thumbColor: StudioTheme.colorFilterEq,
                          ),
                          child: Slider(
                            key: const Key('patch_tempo_slider'),
                            min: 40,
                            max: 250,
                            value: currentTempo.toDouble().clamp(40, 250),
                            onChanged: (val) {
                              widget.controller.updatePatchTempo(val.round());
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('tempo_increment_button'),
                        icon: const Icon(Icons.add, size: 16, color: Colors.grey),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        splashRadius: 16,
                        tooltip: 'Increase Tempo (+1 BPM)',
                        onPressed: () {
                          widget.controller.updatePatchTempo(currentTempo + 1);
                        },
                      ),
                    ],
                  ),

                  // "Write to Hardware Slot..." Button
                  OutlinedButton.icon(
                    key: const Key('write_to_hardware_slot_button'),
                    icon: const Icon(
                      Icons.save_alt,
                      size: 14,
                      color: StudioTheme.colorModulation,
                    ),
                    label: const Text(
                      'Write to Slot...',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: StudioTheme.colorModulation,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: StudioTheme.colorModulation),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: isCompact ? VisualDensity.compact : VisualDensity.standard,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    onPressed: () => _showWriteToSlotDialog(context),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showWriteToSlotDialog(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (_) => WriteToSlotDialog(
        editorController: widget.controller,
        connectionController: widget.controller.connectionController,
      ),
    );
  }
}
