import 'package:flutter/material.dart';

import '../../models/parameter_descriptor.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/studio_theme.dart';
import 'effect_picker_dialog.dart';
import 'patch_editor_controller.dart';
import 'rotary_knob_widget.dart';

/// Detailed parameter inspector for the currently selected [EffectSlot], displaying
/// an adaptive grid of rotary knobs for known effect parameters and algorithm swapping.
class SlotInspectorWidget extends StatefulWidget {
  final PatchEditorController controller;

  const SlotInspectorWidget({
    super.key,
    required this.controller,
  });

  @override
  State<SlotInspectorWidget> createState() => _SlotInspectorWidgetState();
}

class _SlotInspectorWidgetState extends State<SlotInspectorWidget> {
  bool _showHidden = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final slot = widget.controller.selectedSlot;
        if (slot == null) {
          return Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: StudioTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: StudioTheme.surfaceBorder),
            ),
            child: const Text(
              'Select an effect slot above to inspect and edit parameters',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          );
        }

        final family = widget.controller.connectionController.activeFamily;
        final currentDef = EffectCatalogRegistry.getDefinition(family, slot.effectId);
        final availableEffects = EffectCatalogRegistry.getEffectsForFamily(family);
        final categoryColor = StudioTheme.getCategoryColor(currentDef.category);

        final hasHiddenParams = slot.parameters.any(
          (p) => p.descriptor.name.toLowerCase().startsWith('hidden'),
        );

        // Filter parameters: by default hide internal "Hidden" parameters
        final List<MapEntry<int, ParameterValue>> indexedParams = [];
        for (int i = 0; i < slot.parameters.length; i++) {
          final p = slot.parameters[i];
          final isHidden = p.descriptor.name.toLowerCase().startsWith('hidden');
          if (!isHidden || _showHidden) {
            indexedParams.add(MapEntry(i, p));
          }
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final hasBoundedHeight = constraints.hasBoundedHeight;
            final isNarrow = constraints.maxWidth < 480;

            final knobGrid = Wrap(
              spacing: isNarrow ? 10 : 16,
              runSpacing: isNarrow ? 12 : 16,
              alignment: isNarrow ? WrapAlignment.spaceEvenly : WrapAlignment.start,
              children: indexedParams.map((entry) {
                final originalIdx = entry.key;
                final param = entry.value;

                return RotaryKnobWidget(
                  key: Key('param_knob_${slot.slotIndex}_$originalIdx'),
                  param: param,
                  paramIndex: originalIdx,
                  slotIndex: slot.slotIndex,
                  accentColor: categoryColor,
                  onChanged: (newVal) {
                    widget.controller.updateParameter(
                      slot.slotIndex,
                      originalIdx,
                      newVal,
                    );
                  },
                );
              }).toList(),
            );

            return Container(
              padding: EdgeInsets.all(isNarrow ? 12 : 16),
              decoration: BoxDecoration(
                color: StudioTheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: StudioTheme.surfaceBorder),
              ),
              child: Column(
                mainAxisSize: hasBoundedHeight ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Bar: Slot index, Algorithm Picker, Category Badge, Show Hidden Toggle
                  Wrap(
                    spacing: isNarrow ? 8 : 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: categoryColor, width: 1),
                        ),
                        child: Text(
                          'SLOT #${slot.slotIndex + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: categoryColor,
                          ),
                        ),
                      ),
                      _buildEffectDropdown(
                        context,
                        slot.slotIndex,
                        slot.effectId,
                        availableEffects,
                        maxWidth: isNarrow ? 165 : 210,
                      ),
                      IconButton(
                        key: const Key('open_effect_picker_button'),
                        icon: const Icon(Icons.search, size: 20, color: StudioTheme.colorModulation),
                        tooltip: 'Browse Effect Catalog',
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        onPressed: () async {
                          final selected = await EffectPickerDialog.show(
                            context: context,
                            deviceFamily: family,
                            currentEffectId: slot.effectId,
                            title: 'Change Slot #${slot.slotIndex + 1} Effect',
                          );
                          if (selected != null) {
                            widget.controller.changeSlotEffect(slot.slotIndex, selected.effectId);
                          }
                        },
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: StudioTheme.surfaceElevated,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: StudioTheme.surfaceBorder),
                        ),
                        child: Text(
                          currentDef.category,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: categoryColor,
                          ),
                        ),
                      ),
                      if (hasHiddenParams)
                        InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => setState(() => _showHidden = !_showHidden),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _showHidden
                                  ? StudioTheme.colorModulation.withValues(alpha: 0.2)
                                  : StudioTheme.surfaceElevated,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: _showHidden
                                    ? StudioTheme.colorModulation
                                    : StudioTheme.surfaceBorder,
                              ),
                            ),
                            child: Text(
                              _showHidden ? 'Hide Internal' : 'Show Internal',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _showHidden
                                    ? StudioTheme.colorModulation
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: isNarrow ? 12 : 16),
                  const Divider(color: StudioTheme.surfaceBorder, height: 1),
                  SizedBox(height: isNarrow ? 12 : 16),

                  // Parameter Controls: Adaptive Grid of Rotary Knobs
                  if (indexedParams.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'This effect block has no adjustable parameters.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ),
                    )
                  else if (hasBoundedHeight)
                    Expanded(
                      child: SingleChildScrollView(
                        child: knobGrid,
                      ),
                    )
                  else
                    knobGrid,
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEffectDropdown(
    BuildContext context,
    int slotIndex,
    String currentEffectId,
    List<EffectDefinition> availableEffects, {
    double maxWidth = 180,
  }) {
    final cleanId = currentEffectId.trim().toLowerCase();
    final matchedDef = availableEffects.firstWhere(
      (def) =>
          def.effectId.toLowerCase() == cleanId ||
          '0x${def.effectId.toLowerCase()}' == cleanId ||
          def.effectId.toLowerCase() == cleanId.replaceFirst('0x', ''),
      orElse: () => EffectCatalogRegistry.getDefinition(
        widget.controller.connectionController.activeFamily,
        currentEffectId,
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 120, maxWidth: maxWidth),
      child: DropdownButton<String>(
        key: const Key('effect_model_selector'),
        isExpanded: true,
        value: availableEffects.any((e) => e.effectId == matchedDef.effectId)
            ? matchedDef.effectId
            : null,
        hint: Text(matchedDef.name, style: const TextStyle(color: Colors.white)),
        dropdownColor: StudioTheme.surfaceElevated,
        underline: const SizedBox.shrink(),
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        items: availableEffects.map((def) {
          return DropdownMenuItem<String>(
            value: def.effectId,
            child: Text(
              '${def.name} (${def.category})',
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (newId) {
          if (newId != null) {
            widget.controller.changeSlotEffect(slotIndex, newId);
          }
        },
      ),
    );
  }
}
