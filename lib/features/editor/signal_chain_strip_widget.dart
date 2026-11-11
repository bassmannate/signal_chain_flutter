import 'package:flutter/material.dart';

import '../../models/effect_slot.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/studio_theme.dart';
import 'patch_editor_controller.dart';

/// Horizontal pedalboard strip displaying the ordered [EffectSlot] blocks in the current patch.
class SignalChainStripWidget extends StatelessWidget {
  final PatchEditorController controller;

  const SignalChainStripWidget({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final patch = controller.patch;
        if (patch == null || patch.slots.isEmpty) {
          return Container(
            height: 180,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: StudioTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: StudioTheme.surfaceBorder),
            ),
            child: const Text(
              'No Effect Chain Loaded',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          );
        }

        return Container(
          height: 205,
          decoration: BoxDecoration(
            color: StudioTheme.surface,
            border: Border.all(color: StudioTheme.surfaceBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14, top: 10, bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.linear_scale, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'SIGNAL CHAIN (${patch.slots.length} SLOTS)',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.grey,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      patch.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: StudioTheme.colorModulation,
                      ),
                    ),
                  ],
                ),
              ),

              // Slot Cards
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: patch.slots.length,
                  separatorBuilder: (context, index) => _buildCableConnector(),
                  itemBuilder: (context, index) {
                    final slot = patch.slots[index];
                    final isSelected = controller.selectedSlotIndex == index;
                    return _buildStompboxSlot(context, slot, index, isSelected);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCableConnector() {
    return Center(
      child: Container(
        width: 22,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: StudioTheme.surfaceBorderFocused,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }

  Widget _buildStompboxSlot(
    BuildContext context,
    EffectSlot slot,
    int index,
    bool isSelected,
  ) {
    final def = EffectCatalogRegistry.getDefinition(
      controller.connectionController.activeFamily,
      slot.effectId,
    );
    final categoryColor = StudioTheme.getCategoryColor(def.category);

    return InkWell(
      key: Key('effect_slot_$index'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => controller.selectSlot(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? StudioTheme.surfaceElevated
              : StudioTheme.surfaceElevated.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? categoryColor : StudioTheme.surfaceBorder,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: categoryColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Slot # & Category Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '#${index + 1}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? categoryColor : Colors.grey,
                  ),
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      def.category.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: categoryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),

            // Effect Name
            Text(
              slot.effectName.isEmpty ? def.name : slot.effectName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: slot.isEnabled ? Colors.white : Colors.grey,
              ),
            ),
            const SizedBox(height: 4),

            // Parameter Count
            Text(
              '${slot.parameters.length} params',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            const Spacer(),

            // LED & Bypass Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // LED Light
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: slot.isEnabled
                            ? categoryColor
                            : Colors.grey.shade700,
                        boxShadow: slot.isEnabled
                            ? [
                                BoxShadow(
                                  color: categoryColor.withValues(alpha: 0.8),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      slot.isEnabled ? 'ON' : 'BYP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: slot.isEnabled ? categoryColor : Colors.grey,
                      ),
                    ),
                  ],
                ),

                // Bypass Toggle Button
                IconButton(
                  key: Key('toggle_slot_${index}_button'),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  iconSize: 22,
                  icon: Icon(
                    slot.isEnabled
                        ? Icons.power_settings_new
                        : Icons.power_settings_new_outlined,
                    color: slot.isEnabled ? categoryColor : Colors.grey,
                  ),
                  tooltip: slot.isEnabled ? 'Bypass Effect' : 'Enable Effect',
                  onPressed: () => controller.toggleSlotEnabled(index),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
