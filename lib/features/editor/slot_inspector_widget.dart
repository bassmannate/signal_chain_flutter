import 'package:flutter/material.dart';

import '../../models/parameter_descriptor.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/studio_theme.dart';
import 'patch_editor_controller.dart';

/// Detailed parameter inspector for the currently selected [EffectSlot], allowing
/// algorithm swapping from [EffectCatalogRegistry] and real-time parameter tweaking.
class SlotInspectorWidget extends StatelessWidget {
  final PatchEditorController controller;

  const SlotInspectorWidget({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final slot = controller.selectedSlot;
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

        final family = controller.connectionController.activeFamily;
        final currentDef = EffectCatalogRegistry.getDefinition(family, slot.effectId);
        final availableEffects = EffectCatalogRegistry.getEffectsForFamily(family);
        final categoryColor = StudioTheme.getCategoryColor(currentDef.category);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: StudioTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: StudioTheme.surfaceBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Slot index, Algorithm Picker, Category Badge
              Wrap(
                spacing: 12,
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
                  _buildEffectDropdown(context, slot.slotIndex, slot.effectId, availableEffects),
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
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: StudioTheme.surfaceBorder, height: 1),
              const SizedBox(height: 16),

              // Parameter Controls Grid or Column
              if (slot.parameters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'This effect block has no adjustable parameters.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: slot.parameters.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, paramIndex) {
                      final param = slot.parameters[paramIndex];
                      return _buildParameterControl(
                        context,
                        slot.slotIndex,
                        paramIndex,
                        param,
                        categoryColor,
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEffectDropdown(
    BuildContext context,
    int slotIndex,
    String currentEffectId,
    List<EffectDefinition> availableEffects,
  ) {
    // Normalization check so dropdown matches currentEffectId
    final cleanId = currentEffectId.trim().toLowerCase();
    final matchedDef = availableEffects.firstWhere(
      (def) =>
          def.effectId.toLowerCase() == cleanId ||
          '0x${def.effectId.toLowerCase()}' == cleanId ||
          def.effectId.toLowerCase() == cleanId.replaceFirst('0x', ''),
      orElse: () => EffectCatalogRegistry.getDefinition(
        controller.connectionController.activeFamily,
        currentEffectId,
      ),
    );

    return DropdownButton<String>(
      key: const Key('effect_model_selector'),
      value: availableEffects.any((e) => e.effectId == matchedDef.effectId)
          ? matchedDef.effectId
          : null,
      hint: Text(matchedDef.name, style: const TextStyle(color: Colors.white)),
      dropdownColor: StudioTheme.surfaceElevated,
      underline: const SizedBox.shrink(),
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
      items: availableEffects.map((def) {
        return DropdownMenuItem<String>(
          value: def.effectId,
          child: Text('${def.name} (${def.category})'),
        );
      }).toList(),
      onChanged: (newId) {
        if (newId != null) {
          controller.changeSlotEffect(slotIndex, newId);
        }
      },
    );
  }

  Widget _buildParameterControl(
    BuildContext context,
    int slotIndex,
    int paramIndex,
    ParameterValue param,
    Color accentColor,
  ) {
    final descriptor = param.descriptor;
    final isDiscrete = descriptor.isDiscrete;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: StudioTheme.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: StudioTheme.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Parameter Label & Value Text
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                descriptor.name,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: StudioTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: StudioTheme.surfaceBorder),
                ),
                child: Text(
                  param.displayValue,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Control: Dropdown for discrete, Slider for continuous
          if (isDiscrete && descriptor.labels != null)
            _buildDiscreteDropdown(slotIndex, paramIndex, param, descriptor.labels!)
          else
            _buildContinuousSlider(context, slotIndex, paramIndex, param, descriptor, accentColor),
        ],
      ),
    );
  }

  Widget _buildDiscreteDropdown(
    int slotIndex,
    int paramIndex,
    ParameterValue param,
    List<String> labels,
  ) {
    final currentIdx = param.currentValue.round().clamp(0, labels.length - 1);

    return DropdownButton<int>(
      key: Key('discrete_param_${slotIndex}_$paramIndex'),
      isExpanded: true,
      value: currentIdx,
      dropdownColor: StudioTheme.surfaceElevated,
      items: List.generate(labels.length, (idx) {
        return DropdownMenuItem<int>(
          value: idx,
          child: Text(
            labels[idx],
            style: const TextStyle(fontSize: 13, color: Colors.white),
          ),
        );
      }),
      onChanged: (newVal) {
        if (newVal != null) {
          controller.updateParameter(slotIndex, paramIndex, newVal);
        }
      },
    );
  }

  Widget _buildContinuousSlider(
    BuildContext context,
    int slotIndex,
    int paramIndex,
    ParameterValue param,
    ParameterDescriptor descriptor,
    Color accentColor,
  ) {
    final min = descriptor.min.toDouble();
    final max = descriptor.max.toDouble();
    final value = param.currentValue.clamp(min, max);
    final divisions = (max - min).round();

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: accentColor,
        thumbColor: accentColor,
      ),
      child: Slider(
        key: Key('param_slider_${slotIndex}_$paramIndex'),
        value: value,
        min: min,
        max: max,
        divisions: divisions > 0 ? divisions : null,
        onChanged: (newValue) {
          controller.updateParameter(slotIndex, paramIndex, newValue.round());
        },
      ),
    );
  }
}
