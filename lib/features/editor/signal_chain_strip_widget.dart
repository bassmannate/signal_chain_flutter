import 'package:flutter/material.dart';

import '../../models/effect_slot.dart';
import '../../protocols/catalogs/effect_catalog.dart';
import '../theme/responsive_layout.dart';
import '../theme/studio_theme.dart';
import 'effect_bank_palette_widget.dart';
import 'effect_picker_dialog.dart';
import 'patch_editor_controller.dart';
import 'patch_metadata_header_widget.dart';

/// Horizontal pedalboard strip displaying the ordered [EffectSlot] blocks in the current patch,
/// supporting slot selection, reordering, adding, removing, and effect algorithm swapping.
class SignalChainStripWidget extends StatelessWidget {
  final PatchEditorController controller;

  const SignalChainStripWidget({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final viewportSize = MediaQuery.sizeOf(context);
    final isCompactOrShort = viewportSize.width < 600 || viewportSize.height < 640;
    final double stripHeight = viewportSize.height <= 600
        ? 148.0
        : (isCompactOrShort ? 156.0 : 172.0);
    final double badgeHeight = stripHeight - 20.0;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final patch = controller.patch;
        if (patch == null || patch.slots.isEmpty) {
          return Container(
            constraints: const BoxConstraints(minHeight: 160),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
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

        final canAdd = controller.canAddEffectSlot;

        return Container(
          decoration: BoxDecoration(
            color: StudioTheme.surface,
            border: Border.all(color: StudioTheme.surfaceBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Metadata Header (Patch Name TextField, Tempo Slider/Input, Write to Slot)
              PatchMetadataHeaderWidget(controller: controller),

              // Subheader
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14, top: 6, bottom: 2),
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'SIGNAL CHAIN (${patch.slots.length} SLOTS)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '• OUT ← IN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: StudioTheme.colorFilterEq,
                      ),
                    ),
                    const Spacer(),
                    if (patch.programNumber != null)
                      Flexible(
                        child: Text(
                          'HARDWARE SLOT #${patch.programNumber!.toString().padLeft(2, '0')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: StudioTheme.colorFilterEq,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Slot Cards, Insertion Zones, & Add Card (Right-to-Left pedalboard order)
              SizedBox(
                height: stripHeight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildRtlSignalChainElements(
                      context,
                      patch.slots,
                      canAdd,
                      badgeHeight: badgeHeight,
                      cardHeight: stripHeight - 12.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildRtlSignalChainElements(
    BuildContext context,
    List<EffectSlot> slots,
    bool canAdd, {
    required double badgeHeight,
    required double cardHeight,
  }) {
    final elements = <Widget>[];
    final numSlots = slots.length;

    // 1. Output Jack / Badge (Far Left)
    elements.add(_buildOutBadge(badgeHeight));

    // 2. Connector & Add Slot Card (if canAdd)
    if (canAdd) {
      elements.add(_buildCableConnector());
      elements.add(_buildAddEffectCard(context));
    }

    // 3. Stompbox slots in RTL order (from slot N-1 down to slot 0) with insertion zones
    for (int i = numSlots - 1; i >= 0; i--) {
      // Insertion zone to the left of slot i (i.e. insertIndex = i + 1)
      elements.add(_buildInsertionZone(i + 1, badgeHeight: badgeHeight));

      // Stompbox slot i
      final slot = slots[i];
      final isSelected = controller.selectedSlotIndex == i;
      elements.add(
        _buildStompboxSlot(
          context,
          slot,
          i,
          isSelected,
          numSlots,
          cardHeight: cardHeight,
        ),
      );
    }

    // 4. Insertion zone 0 (between slot 0 and IN)
    elements.add(_buildInsertionZone(0, badgeHeight: badgeHeight));

    // 5. Input Jack / Badge (Far Right)
    elements.add(_buildInBadge(badgeHeight));

    return elements;
  }

  Widget _buildInBadge(double height) {
    return Center(
      child: Container(
        width: 56,
        height: height,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: StudioTheme.surfaceElevated.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StudioTheme.surfaceBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.arrow_back, size: 18, color: StudioTheme.colorModulation),
            const SizedBox(height: 8),
            const Text(
              'IN',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: StudioTheme.colorModulation,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'INPUT',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutBadge(double height) {
    return Center(
      child: Container(
        width: 56,
        height: height,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: StudioTheme.surfaceElevated.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StudioTheme.surfaceBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.arrow_back, size: 18, color: StudioTheme.colorAmpCab),
            const SizedBox(height: 8),
            const Text(
              'OUT',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: StudioTheme.colorAmpCab,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'OUTPUT',
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsertionZone(int insertIndex, {required double badgeHeight}) {
    return DragTarget<Object>(
      key: Key('insertion_zone_$insertIndex'),
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is SlotReorderPayload) {
          if (!controller.canReorderSlots) return false;
          // In RTL layout, a slot dragged from fromIndex to insertion point insertIndex
          // shifts items so target position is fromIndex < insertIndex ? insertIndex - 1 : insertIndex.
          final targetIndex = data.fromIndex < insertIndex ? insertIndex - 1 : insertIndex;
          return targetIndex != data.fromIndex;
        }
        if (data is EffectDragPayload || data is EffectCatalogEntry) {
          return controller.canAddEffectSlot;
        }
        return false;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is EffectDragPayload) {
          controller.insertEffectSlotAt(insertIndex, data.entry);
        } else if (data is EffectCatalogEntry) {
          controller.insertEffectSlotAt(insertIndex, data);
        } else if (data is SlotReorderPayload) {
          controller.reorderEffectSlots(data.fromIndex, insertIndex);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          width: isHovered ? 32 : 18,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          child: Center(
            child: isHovered
                ? Container(
                    width: 5,
                    height: badgeHeight,
                    decoration: BoxDecoration(
                      color: StudioTheme.colorModulation,
                      borderRadius: BorderRadius.circular(3),
                      boxShadow: [
                        BoxShadow(
                          color: StudioTheme.colorModulation.withValues(alpha: 0.7),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  )
                : _buildCableConnector(),
          ),
        );
      },
    );
  }

  Widget _buildCableConnector() {
    return const Center(
      child: Icon(
        Icons.arrow_back,
        size: 11,
        color: StudioTheme.surfaceBorderFocused,
      ),
    );
  }

  Widget _buildStompboxSlot(
    BuildContext context,
    EffectSlot slot,
    int index,
    bool isSelected,
    int totalSlots, {
    required double cardHeight,
  }) {
    final family = controller.connectionController.activeFamily;
    final def = EffectCatalogRegistry.getDefinition(family, slot.effectId);
    final categoryColor = StudioTheme.getCategoryColor(def.category);
    final isTouch = ResponsiveLayoutMetrics.isTouchPlatform(context);

    return DragTarget<Object>(
      key: Key('slot_drag_target_$index'),
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        if (data is SlotReorderPayload) {
          return data.fromIndex != index && controller.canReorderSlots;
        }
        if (data is EffectDragPayload || data is EffectCatalogEntry) {
          return true;
        }
        return false;
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is SlotReorderPayload) {
          controller.swapEffectSlots(data.fromIndex, index);
        } else if (data is EffectDragPayload) {
          controller.changeSlotEffect(index, data.entry.effectId);
        } else if (data is EffectCatalogEntry) {
          controller.changeSlotEffect(index, data.effectId);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        final slotWidget = _buildSlotCardContent(
          context,
          slot: slot,
          index: index,
          isSelected: isSelected,
          totalSlots: totalSlots,
          categoryColor: categoryColor,
          def: def,
          isHovered: isHovered,
        );

        if (!controller.canReorderSlots) {
          return slotWidget;
        }

        final feedbackWidget = Material(
          elevation: 8,
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 154,
            height: cardHeight,
            child: _buildSlotCardContent(
              context,
              slot: slot,
              index: index,
              isSelected: true,
              totalSlots: totalSlots,
              categoryColor: categoryColor,
              def: def,
              isHovered: false,
              isDragging: true,
            ),
          ),
        );

        final childWhenDragging = Opacity(
          opacity: 0.35,
          child: slotWidget,
        );

        if (isTouch) {
          return LongPressDraggable<SlotReorderPayload>(
            key: Key('slot_draggable_$index'),
            data: SlotReorderPayload(index),
            feedback: feedbackWidget,
            childWhenDragging: childWhenDragging,
            child: slotWidget,
          );
        }

        return Draggable<SlotReorderPayload>(
          key: Key('slot_draggable_$index'),
          data: SlotReorderPayload(index),
          feedback: feedbackWidget,
          childWhenDragging: childWhenDragging,
          child: slotWidget,
        );
      },
    );
  }

  Widget _buildSlotCardContent(
    BuildContext context, {
    required EffectSlot slot,
    required int index,
    required bool isSelected,
    required int totalSlots,
    required Color categoryColor,
    required EffectDefinition def,
    required bool isHovered,
    bool isDragging = false,
  }) {
    final family = controller.connectionController.activeFamily;
    final borderColor = isHovered
        ? StudioTheme.colorModulation
        : (isSelected ? categoryColor : StudioTheme.surfaceBorder);
    final borderWidth = (isHovered || isSelected) ? 2.0 : 1.0;

    return InkWell(
      key: Key('effect_slot_$index'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => controller.selectSlot(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 154,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isHovered
              ? StudioTheme.surfaceElevated
              : (isSelected
                  ? StudioTheme.surfaceElevated
                  : StudioTheme.surfaceElevated.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
          boxShadow: (isHovered || isSelected || isDragging)
              ? [
                  BoxShadow(
                    color: (isHovered ? StudioTheme.colorModulation : categoryColor).withValues(alpha: 0.35),
                    blurRadius: isHovered ? 12 : 8,
                    spreadRadius: isHovered ? 2 : 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Slot # & Category Badge & Delete Slot
            Row(
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
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      def.category.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        color: categoryColor,
                      ),
                    ),
                  ),
                ),
                if (controller.canRemoveEffectSlot)
                  Tooltip(
                    message: 'Remove Effect Slot',
                    child: InkWell(
                      key: Key('delete_slot_$index'),
                      borderRadius: BorderRadius.circular(4),
                      onTap: () => controller.removeEffectSlot(index),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close, size: 15, color: Colors.grey),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),

            // Effect Name
            Text(
              slot.effectName.isEmpty ? def.name : slot.effectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: slot.isEnabled ? Colors.white : Colors.grey,
              ),
            ),

            // Parameter Count
            Text(
              '${slot.parameters.length} params',
              style: const TextStyle(fontSize: 9.5, color: Colors.grey),
            ),
            const Spacer(),

            // Slot Action Controls: Move Left, Change Effect, Move Right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Move Left (towards Output in RTL)
                Tooltip(
                  message: 'Move Left',
                  child: InkWell(
                    key: Key('move_slot_left_$index'),
                    borderRadius: BorderRadius.circular(4),
                    onTap: index < totalSlots - 1 && controller.canReorderSlots
                        ? () => controller.swapEffectSlots(index, index + 1)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.arrow_back,
                        size: 16,
                        color: index < totalSlots - 1 && controller.canReorderSlots
                            ? Colors.white70
                            : Colors.white24,
                      ),
                    ),
                  ),
                ),

                // Change Effect Button
                InkWell(
                  key: Key('change_effect_slot_$index'),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () async {
                    final selected = await EffectPickerDialog.show(
                      context: context,
                      deviceFamily: family,
                      currentEffectId: slot.effectId,
                      title: 'Change Slot #${index + 1} Effect',
                    );
                    if (selected != null) {
                      controller.changeSlotEffect(index, selected.effectId);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: StudioTheme.surface,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isSelected ? categoryColor.withValues(alpha: 0.5) : StudioTheme.surfaceBorder,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swap_horiz, size: 12, color: Colors.grey),
                        SizedBox(width: 2),
                        Text(
                          'Swap',
                          style: TextStyle(fontSize: 9.5, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),

                // Move Right (towards Input in RTL)
                Tooltip(
                  message: 'Move Right',
                  child: InkWell(
                    key: Key('move_slot_right_$index'),
                    borderRadius: BorderRadius.circular(4),
                    onTap: index > 0 && controller.canReorderSlots
                        ? () => controller.swapEffectSlots(index, index - 1)
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: index > 0 && controller.canReorderSlots
                            ? Colors.white70
                            : Colors.white24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),

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
                    const SizedBox(width: 5),
                    Text(
                      slot.isEnabled ? 'ON' : 'BYP',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                        color: slot.isEnabled ? categoryColor : Colors.grey,
                      ),
                    ),
                  ],
                ),

                // Bypass Toggle Button
                IconButton(
                  key: Key('toggle_slot_${index}_button'),
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  iconSize: 19,
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

  Widget _buildAddEffectCard(BuildContext context) {
    final family = controller.connectionController.activeFamily;

    return DragTarget<Object>(
      key: const Key('add_slot_drag_target'),
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return controller.canAddEffectSlot &&
            (data is EffectDragPayload || data is EffectCatalogEntry);
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is EffectDragPayload) {
          controller.addEffectSlot(effectId: data.entry.effectId);
        } else if (data is EffectCatalogEntry) {
          controller.addEffectSlot(effectId: data.effectId);
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovered = candidateData.isNotEmpty;

        return InkWell(
          key: const Key('add_effect_slot_button'),
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final selected = await EffectPickerDialog.show(
              context: context,
              deviceFamily: family,
              title: 'Add Effect to Signal Chain',
            );
            if (selected != null) {
              controller.addEffectSlot(effectId: selected.effectId);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 130,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isHovered
                  ? StudioTheme.colorModulation.withValues(alpha: 0.15)
                  : StudioTheme.surfaceElevated.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isHovered ? StudioTheme.colorModulation : StudioTheme.surfaceBorder,
                style: BorderStyle.solid,
                width: isHovered ? 2.5 : 1.5,
              ),
              boxShadow: isHovered
                  ? [
                      BoxShadow(
                        color: StudioTheme.colorModulation.withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: StudioTheme.colorModulation.withValues(alpha: 0.15),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 22,
                    color: StudioTheme.colorModulation,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '+ Add Effect',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: StudioTheme.colorModulation,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Max ${family.maxEffectSlots} slots',
                  style: const TextStyle(fontSize: 9.5, color: Colors.grey),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
